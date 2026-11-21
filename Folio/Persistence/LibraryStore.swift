import Foundation
import SwiftData

@Model final class LibraryBook {
    @Attribute(.unique) var id: String
    var metadata: Data
    var added: Date
    var relativePath: String?
    var downloadState: String = "saved"
    var downloadError: String?
    var downloadToken: String?
    var locator: String?
    var pdfPage: Int = 0
    var progress: Double = 0
    var completed: Bool = false
    var lastRead: Date?
    init(book: Book) throws {
        id = book.id; metadata = try JSONEncoder().encode(book); added = Date()
    }
    var book: Book? { try? JSONDecoder().decode(Book.self, from: metadata) }
    var fileURL: URL? { relativePath.map { LibraryFiles.directory.appendingPathComponent($0) } }
    var isDownloading: Bool { downloadState == "downloading" || downloadState == "validating" || downloadState == "retrying" }
    var isDownloaded: Bool { fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
}
@Model final class Annotation {
    var id: UUID
    var bookID: String
    var locator: String
    var text: String
    var note: String
    var kind: String
    var created: Date
    init(bookID: String, locator: String, text: String, note: String = "", kind: String = "bookmark") {
        id = UUID(); self.bookID = bookID; self.locator = locator; self.text = text
        self.note = note; self.kind = kind; created = Date()
    }
}
@Model final class ReadingDay {
    @Attribute(.unique) var day: Date
    var seconds: Double
    init(day: Date, seconds: Double = 0) { self.day = day; self.seconds = seconds }
}
enum LibraryFiles {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Books", isDirectory: true)
    }
    static func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    static func remove(_ record: LibraryBook) throws {
        if let url = record.fileURL, FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        record.relativePath = nil; record.downloadState = "saved"; record.downloadError = nil; record.downloadToken = nil
    }
    static func usage() -> Int64 {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}
@MainActor enum LibraryRepository {
    static func remove(_ record: LibraryBook, context: ModelContext) throws {
        DownloadManager.shared.cancel(record.id)
        try LibraryFiles.remove(record)
        let id = record.id
        for annotation in try context.fetch(FetchDescriptor<Annotation>(predicate: #Predicate { $0.bookID == id })) { context.delete(annotation) }
        context.delete(record); try context.save()
    }
    static func save(_ book: Book, context: ModelContext) throws -> LibraryBook {
        let id = book.id
        let descriptor = FetchDescriptor<LibraryBook>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            existing.metadata = try JSONEncoder().encode(book); try context.save(); return existing
        }
        let record = try LibraryBook(book: book); context.insert(record); try context.save(); return record
    }
}
struct Streaks {
    static func calculate(days: [Date], today: Date = Date(), calendar: Calendar = .current) -> (current: Int, longest: Int) {
        let dates = Set(days.map { calendar.startOfDay(for: $0) }).sorted()
        var longest = 0, run = 0, previous: Date?
        for date in dates {
            run = previous.flatMap { calendar.dateComponents([.day], from: $0, to: date).day } == 1 ? run + 1 : 1
            longest = max(longest, run); previous = date
        }
        let start = calendar.startOfDay(for: today)
        guard let last = dates.last, let gap = calendar.dateComponents([.day], from: last, to: start).day, (0...1).contains(gap) else { return (0, longest) }
        var current = 0, cursor = last
        let set = Set(dates)
        while set.contains(cursor) {
            current += 1
            guard let earlier = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = earlier
        }
        return (current, longest)
    }
}

@MainActor enum AnnotationRepository {
    static func updateNote(_ annotation: Annotation, note: String, context: ModelContext) throws {
        let previous = annotation.note
        annotation.note = note
        do { try context.save() } catch { annotation.note = previous; throw error }
    }
    @discardableResult static func save(_ annotation: Annotation, context: ModelContext) throws -> Annotation {
        let id = annotation.bookID, locator = annotation.locator, kind = annotation.kind
        let matches = try context.fetch(FetchDescriptor<Annotation>(predicate: #Predicate { $0.bookID == id && $0.locator == locator && $0.kind == kind }))
        if let existing = matches.first {
            if !annotation.note.isEmpty { existing.note = annotation.note }
            try context.save(); return existing
        }
        context.insert(annotation); try context.save(); return annotation
    }
}
