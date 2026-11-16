import Foundation
import SwiftData
import UIKit

struct DownloadTicket: Codable { var bookID: String; var file: BookFile }
// URLSession invokes these methods on a serial delegate queue. Move temporary files
// synchronously: their lifetime ends when didFinishDownloadingTo returns.
final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let description = downloadTask.taskDescription, let ticket = description.data(using: .utf8).flatMap({ try? JSONDecoder().decode(DownloadTicket.self, from: $0) }) else { return }
        Task { @MainActor in DownloadManager.shared.progress[ticket.bookID] = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0 }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let text = downloadTask.taskDescription, let data = text.data(using: .utf8), let ticket = try? JSONDecoder().decode(DownloadTicket.self, from: data) else { return }
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, (200...299).contains(response.statusCode), response.url?.scheme == "https" else { throw FolioError.message("The download server refused this file.") }
            try LibraryFiles.prepare()
            let incoming = LibraryFiles.directory.appendingPathComponent("incoming-\(UUID().uuidString).\(ticket.file.format)")
            try FileManager.default.moveItem(at: location, to: incoming)
            Task { @MainActor in await DownloadManager.shared.finish(ticket, incoming: incoming) }
        } catch { Task { @MainActor in DownloadManager.shared.failed(ticket.bookID, error: error) } }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let text = task.taskDescription, let data = text.data(using: .utf8), let ticket = try? JSONDecoder().decode(DownloadTicket.self, from: data) else { return }
        Task { @MainActor in DownloadManager.shared.failed(ticket.bookID, error: error) }
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in DownloadManager.shared.eventsFinished() }
    }
}
@MainActor final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    @Published var progress: [String: Double] = [:]
    @Published var message: String?
    private var context: ModelContext?
    private let delegate = DownloadDelegate()
    private var pendingValidations = 0
    private var finishedEvents = false
    var backgroundCompletion: (() -> Void)?
    lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.folio.reader.downloads")
        config.sessionSendsLaunchEvents = true; config.isDiscretionary = false
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()
    func configure(_ context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        _ = session
        Task {
            let tasks = await session.allTasks
            let active = Set(tasks.compactMap { task in task.taskDescription?.data(using: .utf8).flatMap { try? JSONDecoder().decode(DownloadTicket.self, from: $0).bookID } })
            for record in (try? context.fetch(FetchDescriptor<LibraryBook>())) ?? [] {
                if record.downloadState == "downloading", !active.contains(record.id) {
                    record.downloadState = "failed"; record.downloadError = "Interrupted download. Open details to retry."
                }
                if record.relativePath != nil, !record.isDownloaded { record.relativePath = nil; record.downloadState = "failed" }
            }
            // Files interrupted during validation are not exposed as readable books.
            let incoming = (try? FileManager.default.contentsOfDirectory(at: LibraryFiles.directory, includingPropertiesForKeys: nil)) ?? []
            for url in incoming where url.lastPathComponent.hasPrefix("incoming-") {
                let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                if let modified, modified.timeIntervalSinceNow < -86400 { try? FileManager.default.removeItem(at: url) }
            }
            try? context.save()
        }
    }
    func start(_ file: BookFile, book: Book) throws {
        guard let context else { throw FolioError.message("Library is not ready.") }
        guard book.files.contains(file), file.url.scheme == "https", !file.rights.isEmpty else { throw FolioError.message("No authorized download is available.") }
        try LibraryFiles.prepare()
        let capacity = try LibraryFiles.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard capacity > max((file.expectedBytes ?? 50_000_000) * 2, 100_000_000) else { throw FolioError.message("Free some device storage before downloading.") }
        let record = try LibraryRepository.save(book, context: context)
        guard record.downloadState != "downloading" else { return }
        let ticket = DownloadTicket(bookID: book.id, file: file)
        var request = URLRequest(url: file.url)
        request.setValue("Folio/1.0 (com.folio.reader)", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        task.taskDescription = String(data: try JSONEncoder().encode(ticket), encoding: .utf8)
        record.downloadState = "downloading"; record.downloadError = nil; try context.save()
        progress[book.id] = 0; task.resume()
    }
    func cancel(_ id: String) {
        Task {
            for task in await session.allTasks {
                if let text = task.taskDescription, let data = text.data(using: .utf8), (try? JSONDecoder().decode(DownloadTicket.self, from: data).bookID) == id { task.cancel() }
            }
        }
    }
    private func record(_ id: String) -> LibraryBook? {
        try? context?.fetch(FetchDescriptor<LibraryBook>(predicate: #Predicate { $0.id == id })).first
    }
    func finish(_ ticket: DownloadTicket, incoming: URL) async {
        pendingValidations += 1
        defer { pendingValidations -= 1; completeBackgroundIfReady() }
        do {
            try await ReaderEngine.shared.validate(incoming, file: ticket.file)
            guard let record = record(ticket.bookID), record.downloadState == "downloading" else { try? FileManager.default.removeItem(at: incoming); return }
            let name = "\(UUID().uuidString).\(ticket.file.format)"
            let destination = LibraryFiles.directory.appendingPathComponent(name)
            try FileManager.default.moveItem(at: incoming, to: destination)
            let old = record.fileURL
            record.relativePath = name; record.downloadState = "downloaded"; record.downloadError = nil
            do { try context?.save() } catch { try? FileManager.default.removeItem(at: destination); throw error }
            if let old { try? FileManager.default.removeItem(at: old) }
            progress[ticket.bookID] = nil
        } catch {
            try? FileManager.default.removeItem(at: incoming)
            failed(ticket.bookID, error: error)
        }
    }
    func failed(_ id: String, error: Error) {
        record(id)?.downloadState = "failed"; record(id)?.downloadError = error.localizedDescription
        progress[id] = nil; message = error.localizedDescription; try? context?.save()
    }
    func eventsFinished() { finishedEvents = true; completeBackgroundIfReady() }
    private func completeBackgroundIfReady() {
        if finishedEvents && pendingValidations == 0 { finishedEvents = false; backgroundCompletion?(); backgroundCompletion = nil }
    }
}
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        Task { @MainActor in DownloadManager.shared.backgroundCompletion = completionHandler; _ = DownloadManager.shared.session }
    }
}
