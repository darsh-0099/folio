import XCTest
import SwiftData
import ReadiumShared
@testable import Folio

final class CatalogTests: XCTestCase {
    func testGutenbergDecodingAndCopyrightGate() throws {
        let json = #"{"next":null,"results":[{"id":1342,"title":"Pride and Prejudice","authors":[{"name":"Austen, Jane"}],"languages":["en"],"subjects":["Fiction"],"formats":{"application/epub+zip":"https://www.gutenberg.org/ebooks/1342.epub3.images"},"copyright":false}]}"#
        let page = try JSONDecoder().decode(GutenbergPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.results.first?.book.files.first?.format, "epub")
        let restricted = json.replacingOccurrences(of: "\"copyright\":false", with: "\"copyright\":true")
        XCTAssertTrue(try JSONDecoder().decode(GutenbergPage.self, from: Data(restricted.utf8)).results[0].book.files.isEmpty)
    }
    func testMissingOpenLibraryMetadata() throws {
        let json = #"{"docs":[{"key":"/works/OL1W","title":"A book"}]}"#
        let book = try JSONDecoder().decode(OpenLibraryPage.self, from: Data(json.utf8)).docs[0].book
        XCTAssertTrue(book.authors.isEmpty); XCTAssertTrue(book.files.isEmpty); XCTAssertNil(book.cover)
    }
    func testArchiveLicenseAndRestrictionGates() throws {
        let json = #"{"metadata":{"licenseurl":"https://creativecommons.org/publicdomain/zero/1.0/"},"files":[{"name":"book.epub","size":"100","md5":"abc"},{"name":"../escape.epub"},{"name":"locked.pdf","private":"true"}]}"#
        let item = try JSONDecoder().decode(ArchiveItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.downloads(identifier: "book").count, 1)
        XCTAssertEqual(item.downloads(identifier: "book").first?.expectedBytes, 100)
        for replacement in ["https://example.com/copyright", "", "https://creativecommons.org.evil.test/publicdomain/zero/1.0/"] {
            let data = Data(json.replacingOccurrences(of: "https://creativecommons.org/publicdomain/zero/1.0/", with: replacement).utf8)
            XCTAssertTrue(try JSONDecoder().decode(ArchiveItem.self, from: data).downloads(identifier: "book").isEmpty)
        }
        let restricted = json.replacingOccurrences(of: "\"metadata\":{", with: "\"metadata\":{\"access_restricted_item\":true,")
        XCTAssertTrue(try JSONDecoder().decode(ArchiveItem.self, from: Data(restricted.utf8)).downloads(identifier: "book").isEmpty)
    }
    func testDuplicateDetectionPreservesEditions() {
        let first = Book(id: "a", title: "Book", authors: [], source: URL(string: "https://example.com/a")!, origin: "test")
        var edition = first; edition.id = "b"; edition.year = 1900
        XCTAssertEqual(Book.deduplicate([first, first, edition]).count, 2)
    }
    func testCrossSourceDeduplicationRetainsAlternateEdition() {
        let first = Book(id: "g:1", title: "Pride and Prejudice", authors: ["Austen, Jane"], source: URL(string: "https://gutenberg.org")!, origin: "Gutenberg")
        let second = Book(id: "o:1", title: "Pride and Prejudice", authors: ["Jane Austen"], source: URL(string: "https://openlibrary.org")!, origin: "Open Library")
        let results = Book.deduplicate([first, second, second])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].alternateEditions.first?.id, second.id)
    }
    func testMalformedResponsesFail() {
        XCTAssertThrowsError(try JSONDecoder().decode(GutenbergPage.self, from: Data("<html>Error</html>".utf8)))
    }
    func testStreakAcrossYearAndMissingToday() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date: (String) -> Date = { ISO8601DateFormatter().date(from: $0 + "T12:00:00Z")! }
        let streak = Streaks.calculate(days: [date("2025-12-30"), date("2025-12-31"), date("2026-01-01")], today: date("2026-01-02"), calendar: calendar)
        XCTAssertEqual(streak.current, 3); XCTAssertEqual(streak.longest, 3)
        XCTAssertEqual(Streaks.calculate(days: [date("2026-01-01")], today: date("2026-01-03"), calendar: calendar).current, 0)
    }
}
@MainActor final class PersistenceTests: XCTestCase {
    func testOfflineLibraryLocatorAndBookmarkSurviveReopeningStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([LibraryBook.self, Annotation.self, ReadingDay.self])
        let config = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("test.store"))
        let book = Book(id: "test", title: "Offline book", authors: ["Author"], source: URL(string: "https://example.com")!, origin: "test")
        let locator = Locator(href: try XCTUnwrap(RelativeURL(path: "chapter.xhtml")), mediaType: .xhtml, locations: .init(progression: 0.5, totalProgression: 0.25))
        do {
            let container = try ModelContainer(for: schema, configurations: [config]); let context = ModelContext(container)
            let record = try LibraryRepository.save(book, context: context)
            _ = try LibraryRepository.save(book, context: context)
            record.locator = locator.jsonString; record.progress = 0.25
            context.insert(Annotation(bookID: book.id, locator: locator.jsonString!, text: "Passage", note: "Remember", kind: "highlight"))
            try context.save()
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<LibraryBook>()), 1)
        }
        let reopened = try ModelContainer(for: schema, configurations: [config]); let context = ModelContext(reopened)
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<LibraryBook>()).first)
        XCTAssertEqual(record.progress, 0.25)
        XCTAssertEqual(try Locator(jsonString: XCTUnwrap(record.locator))?.locations.totalProgression, 0.25)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Annotation>()).first?.note, "Remember")
        XCTAssertEqual(record.book?.title, book.title)
    }
    func testFileDeletionAndMissingFileDetection() throws {
        try LibraryFiles.prepare()
        let record = try LibraryBook(book: Book(id: "file-test", title: "Test", authors: [], source: URL(string: "https://example.com")!, origin: "test"))
        record.relativePath = "test-\(UUID().uuidString).txt"
        let url = try XCTUnwrap(record.fileURL)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("Public domain test text".utf8).write(to: url)
        XCTAssertTrue(record.isDownloaded)
        try LibraryFiles.remove(record)
        XCTAssertFalse(record.isDownloaded); XCTAssertNil(record.relativePath)
    }
    func testCorruptEPUBAndWrongSizeRejected() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        try Data("<html>Not a book</html>".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = BookFile(url: URL(string: "https://example.com/book.epub")!, format: "epub", rights: "CC0")
        do { try await ReaderEngine.shared.validate(url, file: file); XCTFail("Corrupt EPUB accepted") } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        var wrongSize = file; wrongSize.expectedBytes = 1
        do { try await ReaderEngine.shared.validate(url, file: wrongSize); XCTFail("Wrong size accepted") } catch { XCTAssertTrue(error.localizedDescription.contains("incomplete")) }
    }
}
