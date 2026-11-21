import Foundation
import SwiftData
import UIKit

struct DownloadTicket: Codable { var bookID: String; var file: BookFile; var token: String = UUID().uuidString; var mirrorAttempted: Bool? }
struct DownloadReceipt: Codable {
    var ticket: DownloadTicket
    var filename: String
    static func url(for file: URL) -> URL { file.appendingPathExtension("receipt") }
    func incomingURL() -> URL? {
        guard filename.hasPrefix("incoming-"), !filename.contains("/"), !filename.contains("\\"), !filename.contains("..") else { return nil }
        return LibraryFiles.directory.appendingPathComponent(filename)
    }
}
// URLSession invokes these methods on a serial delegate queue. Move temporary files
// synchronously: their lifetime ends when didFinishDownloadingTo returns.
final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let description = downloadTask.taskDescription, let ticket = description.data(using: .utf8).flatMap({ try? JSONDecoder().decode(DownloadTicket.self, from: $0) }) else { return }
        Task { @MainActor in DownloadManager.shared.reportProgress(ticket, value: totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : -1) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let text = downloadTask.taskDescription, let data = text.data(using: .utf8), let ticket = try? JSONDecoder().decode(DownloadTicket.self, from: data) else { return }
        do {
            guard let response = downloadTask.response as? HTTPURLResponse else { throw FolioError.message("The download server returned an invalid response.") }
            guard (200...299).contains(response.statusCode) else {
                Task { @MainActor in DownloadManager.shared.handleHTTPFailure(ticket, status: response.statusCode) }
                return
            }
            guard response.url?.scheme == "https" else { throw FolioError.message("The server redirected to an insecure download URL.") }
            try LibraryFiles.prepare()
            let incoming = LibraryFiles.directory.appendingPathComponent("incoming-\(UUID().uuidString).\(ticket.file.format)")
            try FileManager.default.moveItem(at: location, to: incoming)
            do {
                let receipt = DownloadReceipt(ticket: ticket, filename: incoming.lastPathComponent)
                try JSONEncoder().encode(receipt).write(to: DownloadReceipt.url(for: incoming), options: .atomic)
            } catch { try? FileManager.default.removeItem(at: incoming); throw error }
            Task { @MainActor in await DownloadManager.shared.finish(ticket, incoming: incoming) }
        } catch { Task { @MainActor in DownloadManager.shared.failed(ticket, error: error) } }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let text = task.taskDescription, let data = text.data(using: .utf8), let ticket = try? JSONDecoder().decode(DownloadTicket.self, from: data) else { return }
        Task { @MainActor in DownloadManager.shared.failed(ticket, error: error) }
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
    private var pendingRetries = 0
    private var validatingTokens = Set<String>()
    private var recoveryDepth = 0
    private var finishedEvents = false
    var backgroundCompletion: (() -> Void)? { didSet { completeBackgroundIfReady() } }
    lazy var session: URLSession = {
        #if targetEnvironment(simulator)
        // The simulator's background-transfer daemon is not a device lifecycle
        // environment. Exercise the same delegate/storage pipeline in foreground.
        let config = URLSessionConfiguration.default
        #else
        let config = URLSessionConfiguration.background(withIdentifier: "com.folio.reader.downloads")
        config.sessionSendsLaunchEvents = true; config.isDiscretionary = false
        #endif
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
                if record.isDownloading, !active.contains(record.id) {
                    record.downloadState = "failed"; record.downloadError = "Interrupted download. Open details to retry."
                }
                if record.relativePath != nil, !record.isDownloaded { record.relativePath = nil; record.downloadState = "failed" }
            }
            // Receipts survive termination between transfer completion and validation.
            await recoverReceipts()
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
        let values = try LibraryFiles.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let capacity = max(values.volumeAvailableCapacityForImportantUsage ?? 0, Int64(values.volumeAvailableCapacity ?? 0))
        let expected = file.expectedBytes ?? 50_000_000
        guard expected >= 0, expected < Int64.max / 2 else { throw FolioError.message("The source reports an invalid file size.") }
        // An unavailable capacity estimate is not evidence that storage is full.
        // Filesystem write errors still report actual disk-full failures.
        if capacity > 0, capacity < max(expected * 2, 100_000_000) { throw FolioError.message("Free some device storage before downloading.") }
        let record = try LibraryRepository.save(book, context: context)
        guard !record.isDownloading else { return }
        let ticket = DownloadTicket(bookID: book.id, file: file)
        record.downloadState = "downloading"; record.downloadError = nil; record.downloadToken = ticket.token; try context.save()
        progress[book.id] = 0
        do { try enqueue(ticket, url: file.url) }
        catch { failed(ticket, error: error); throw error }
    }
    private func enqueue(_ ticket: DownloadTicket, url: URL) throws {
        var request = URLRequest(url: url)
        request.setValue("Folio/1.1 (com.folio.reader)", forHTTPHeaderField: "User-Agent")
        let description = String(data: try JSONEncoder().encode(ticket), encoding: .utf8)
        let task = session.downloadTask(with: request); task.taskDescription = description; task.resume()
    }
    func handleHTTPFailure(_ ticket: DownloadTicket, status: Int) {
        guard let record = record(ticket.bookID), record.downloadToken == ticket.token, record.downloadState != "cancelled" else { return }
        guard record.book?.origin == "Project Gutenberg", ticket.file.format == "epub", ticket.mirrorAttempted != true,
              let mirror = GutenbergMirror.url(for: ticket.file.url, status: status) else {
            failed(ticket, error: FolioError.message(GutenbergMirror.errorMessage(status: status))); return
        }
        var retry = ticket; retry.mirrorAttempted = true; retry.token = UUID().uuidString
        record.downloadToken = retry.token; record.downloadState = "retrying"; record.downloadError = nil
        progress[ticket.bookID] = nil
        do { try context?.save() } catch { failed(retry, error: error); return }
        pendingRetries += 1
        Task {
            defer { pendingRetries -= 1; completeBackgroundIfReady() }
            do {
                try await Task.sleep(for: .seconds(1))
                guard let current = self.record(retry.bookID), current.downloadToken == retry.token, current.downloadState == "retrying" else { return }
                current.downloadState = "downloading"; try context?.save()
                try enqueue(retry, url: mirror)
            } catch { failed(retry, error: error) }
        }
    }
    func cancel(_ id: String) {
        guard let record = record(id), let token = record.downloadToken else { return }
        record.downloadState = "cancelled"; progress[id] = nil; try? context?.save()
        Task {
            for task in await session.allTasks {
                if let text = task.taskDescription, let data = text.data(using: .utf8), (try? JSONDecoder().decode(DownloadTicket.self, from: data).token) == token { task.cancel() }
            }
        }
    }
    private func record(_ id: String) -> LibraryBook? {
        try? context?.fetch(FetchDescriptor<LibraryBook>(predicate: #Predicate { $0.id == id })).first
    }
    func finish(_ ticket: DownloadTicket, incoming: URL) async {
        guard context != nil else { return } // Keep the receipt until persistence is ready.
        guard validatingTokens.insert(ticket.token).inserted else { return }
        pendingValidations += 1
        defer {
            try? FileManager.default.removeItem(at: DownloadReceipt.url(for: incoming))
            validatingTokens.remove(ticket.token); pendingValidations -= 1; completeBackgroundIfReady()
        }
        guard let initial = record(ticket.bookID), initial.downloadToken == ticket.token, initial.downloadState != "cancelled" else {
            try? FileManager.default.removeItem(at: incoming); return
        }
        do {
            initial.downloadState = "validating"; try context?.save()
            try await ReaderEngine.shared.validate(incoming, file: ticket.file)
            guard let record = record(ticket.bookID), record.downloadToken == ticket.token, record.downloadState != "cancelled" else { try? FileManager.default.removeItem(at: incoming); return }
            let name = "\(UUID().uuidString).\(ticket.file.format)"
            let destination = LibraryFiles.directory.appendingPathComponent(name)
            try FileManager.default.moveItem(at: incoming, to: destination)
            let old = record.fileURL, oldPath = record.relativePath
            record.relativePath = name; record.downloadState = "downloaded"; record.downloadError = nil
            do { try context?.save() } catch {
                record.relativePath = oldPath
                try? FileManager.default.removeItem(at: destination); throw error
            }
            if let old { try? FileManager.default.removeItem(at: old) }
            progress[ticket.bookID] = nil
        } catch {
            try? FileManager.default.removeItem(at: incoming)
            failed(ticket, error: error)
        }
    }
    func reportProgress(_ ticket: DownloadTicket, value: Double) {
        guard let record = record(ticket.bookID), record.downloadToken == ticket.token, record.downloadState == "downloading" else { return }
        progress[ticket.bookID] = value
    }
    func failed(_ ticket: DownloadTicket, error: Error) {
        guard let record = record(ticket.bookID), record.downloadToken == ticket.token else { return }
        let cancelled = (error as NSError).code == NSURLErrorCancelled
        record.downloadState = cancelled ? "cancelled" : "failed"
        record.downloadError = cancelled ? "Download cancelled. Tap Download to retry." : error.localizedDescription
        progress[ticket.bookID] = nil
        if !cancelled { message = error.localizedDescription }; try? context?.save()
    }
    private func recoverReceipts() async {
        recoveryDepth += 1
        defer { recoveryDepth -= 1; completeBackgroundIfReady() }
        let urls = (try? FileManager.default.contentsOfDirectory(at: LibraryFiles.directory, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.pathExtension == "receipt" {
            guard let data = try? Data(contentsOf: url), let receipt = try? JSONDecoder().decode(DownloadReceipt.self, from: data), let incoming = receipt.incomingURL() else {
                try? FileManager.default.removeItem(at: url); continue
            }
            await finish(receipt.ticket, incoming: incoming)
        }
    }
    func eventsFinished() {
        finishedEvents = true; recoveryDepth += 1
        Task {
            await recoverReceipts()
            recoveryDepth -= 1; completeBackgroundIfReady()
        }
    }
    private func completeBackgroundIfReady() {
        if finishedEvents && pendingValidations == 0 && pendingRetries == 0 && recoveryDepth == 0, let completion = backgroundCompletion {
            finishedEvents = false; backgroundCompletion = nil; completion()
        }
    }
}
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        Task { @MainActor in DownloadManager.shared.backgroundCompletion = completionHandler; _ = DownloadManager.shared.session }
    }
}
