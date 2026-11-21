import Foundation
import SwiftData
import CryptoKit
import PDFKit
import ReadiumShared

struct StagedImport: Sendable {
    var url: URL
    var digest: String
    var format: String
    var originalTitle: String
}

enum FileImportStager {
    static func digest(_ url: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
        var hash = SHA256()
        while let data = try input.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func stage(_ source: URL) throws -> StagedImport {
        guard source.isFileURL else { throw FolioError.message("Choose a local EPUB, PDF or UTF-8 text file.") }
        let format = source.pathExtension.lowercased()
        guard ["epub", "pdf", "txt"].contains(format) else { throw FolioError.message("This file type is not supported. Choose EPUB, PDF or TXT.") }
        var result: Result<StagedImport, Error>?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { coordinated in
            result = Result {
                let values = try coordinated.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isDirectory != true, values.isSymbolicLink != true else { throw FolioError.message("Choose a regular book file, not a folder or symbolic link.") }
                try LibraryFiles.prepare()
                let storage = try LibraryFiles.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
                let available = max(storage.volumeAvailableCapacityForImportantUsage ?? 0, Int64(storage.volumeAvailableCapacity ?? 0))
                let bytes = Int64(values.fileSize ?? 0)
                if available > 0, available < max(bytes, 10_000_000) { throw FolioError.message("Free some storage before importing this file.") }
                let destination = LibraryFiles.directory.appendingPathComponent("incoming-import-\(UUID().uuidString).\(format)")
                do {
                    try FileManager.default.copyItem(at: coordinated, to: destination)
                    let hash = try digest(destination)
                    return StagedImport(url: destination, digest: hash, format: format, originalTitle: source.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " "))
                } catch { try? FileManager.default.removeItem(at: destination); throw error }
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw FolioError.message("The file provider could not open this book. Download it in Files and retry.") }
        return try result.get()
    }
}

@MainActor enum BookImporter {
    static func importBook(at source: URL, context: ModelContext) async throws -> LibraryBook {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let staged = try await Task.detached(priority: .userInitiated) { try FileImportStager.stage(source) }.value
        defer { try? FileManager.default.removeItem(at: staged.url) }
        let file = BookFile(url: staged.url, format: staged.format, rights: "Imported by the user")
        try await ReaderEngine.shared.validate(staged.url, file: file)
        let id = "local:\(staged.digest)"
        let existing = try context.fetch(FetchDescriptor<LibraryBook>(predicate: #Predicate { $0.id == id })).first
        if let existing, let url = existing.fileURL, existing.isDownloaded {
            let hash = try? await Task.detached(priority: .userInitiated) { try FileImportStager.digest(url) }.value
            if hash == staged.digest { return existing }
        }
        var title = staged.originalTitle, authors: [String] = []
        if staged.format == "epub" {
            let publication = try await ReaderEngine.shared.open(staged.url)
            title = publication.metadata.title ?? title
            authors = publication.metadata.authors.map(\.name)
        } else if staged.format == "pdf", let pdf = PDFKit.PDFDocument(url: staged.url) {
            title = (pdf.documentAttributes?[PDFKit.PDFDocumentAttribute.titleAttribute.rawValue] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? title
            if let author = pdf.documentAttributes?[PDFKit.PDFDocumentAttribute.authorAttribute.rawValue] as? String, !author.isEmpty { authors = [author] }
        }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { title = "Untitled book" }
        let book = Book(id: id, title: title, authors: authors,
                        summary: "Imported \(staged.format.uppercased()) file, stored on this iPhone for offline reading.",
                        source: URL(string: "urn:sha256:\(staged.digest)")!, origin: "Imported file", availability: "Available offline")
        let record = try existing ?? LibraryBook(book: book)
        let oldPath = record.relativePath, oldState = record.downloadState, oldMetadata = record.metadata
        let name = "\(staged.digest).\(staged.format)"
        let destination = LibraryFiles.directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: staged.url, to: destination)
        if existing == nil { context.insert(record) }
        record.metadata = try JSONEncoder().encode(book); record.relativePath = name
        record.downloadState = "downloaded"; record.downloadError = nil; record.downloadToken = nil
        do { try context.save() }
        catch {
            record.relativePath = oldPath; record.downloadState = oldState; record.metadata = oldMetadata
            if existing == nil { context.delete(record) }
            try? FileManager.default.removeItem(at: destination); throw error
        }
        if let oldPath, oldPath != name { try? FileManager.default.removeItem(at: LibraryFiles.directory.appendingPathComponent(oldPath)) }
        return record
    }
}
