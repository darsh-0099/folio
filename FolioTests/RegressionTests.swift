import XCTest
import UIKit
import PDFKit
import SwiftData
@testable import Folio

final class ReadingSessionTests: XCTestCase {
    func testBackgroundAndPauseIntervalsAreExcluded() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var session = ReadingSession()
        session.resume(at: start)
        XCTAssertEqual(session.pause(at: start.addingTimeInterval(10)).reduce(0) { $0 + $1.seconds }, 10)
        XCTAssertTrue(session.sample(at: start.addingTimeInterval(100)).isEmpty)
        session.resume(at: start.addingTimeInterval(100))
        XCTAssertEqual(session.sample(at: start.addingTimeInterval(110)).reduce(0) { $0 + $1.seconds }, 10)
    }
    func testIdleTimeIsClippedAndInteractionRestartsCounting() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var session = ReadingSession(); session.resume(at: start)
        XCTAssertEqual(session.sample(at: start.addingTimeInterval(300)).reduce(0) { $0 + $1.seconds }, 120)
        XCTAssertTrue(session.interact(at: start.addingTimeInterval(310)).isEmpty)
        XCTAssertEqual(session.sample(at: start.addingTimeInterval(320)).reduce(0) { $0 + $1.seconds }, 10)
    }
    func testMidnightIsSplitBetweenDays() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = ISO8601DateFormatter().date(from: "2026-11-21T23:59:50Z")!
        var session = ReadingSession(); session.resume(at: start)
        let slices = session.sample(at: start.addingTimeInterval(20), calendar: calendar)
        XCTAssertEqual(slices.count, 2)
        XCTAssertEqual(slices.map(\.seconds), [10, 10])
        XCTAssertEqual(calendar.dateComponents([.day], from: slices[0].day, to: slices[1].day).day, 1)
    }
}

final class SourceRegressionTests: XCTestCase {
    func testPrivateAndRestrictedArchiveFlagsCannotBeBypassedByScalarTypes() throws {
        for flag in ["true", "1", "\"1\"", "\"TRUE\"", "{}"] {
            let json = "{\"metadata\":{\"licenseurl\":\"https://creativecommons.org/publicdomain/zero/1.0/\"},\"files\":[{\"name\":\"book.epub\",\"private\":\(flag)}]}"
            XCTAssertTrue(try JSONDecoder().decode(ArchiveItem.self, from: Data(json.utf8)).downloads(identifier: "book").isEmpty)
            let restricted = "{\"metadata\":{\"licenseurl\":\"https://creativecommons.org/publicdomain/zero/1.0/\",\"access_restricted_item\":\(flag)},\"files\":[{\"name\":\"book.epub\"}]}"
            XCTAssertTrue(try JSONDecoder().decode(ArchiveItem.self, from: Data(restricted.utf8)).downloads(identifier: "book").isEmpty)
        }
    }
    func testLegacyLicenseAndNumericSizeDecodeWithoutWeakeningAccessChecks() throws {
        let json = #"{"metadata":{"licenseurl":"http://creativecommons.org/publicdomain/zero/1.0","access_restricted_item":false},"is_dark":"false","files":[{"name":"book.epub","size":42,"private":0}]}"#
        let files = try JSONDecoder().decode(ArchiveItem.self, from: Data(json.utf8)).downloads(identifier: "book")
        XCTAssertEqual(files.count, 1); XCTAssertEqual(files.first?.expectedBytes, 42)
        XCTAssertEqual(files.first?.rights, "https://creativecommons.org/publicdomain/zero/1.0/")
    }
    func testSubjectUsesGutenbergTopicAndEscapesQuery() throws {
        let url = CatalogService.gutenbergURL("science & history", field: "subject", language: "en", page: 2)
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "topic" }?.value, "science & history")
        XCTAssertEqual(query.first { $0.name == "page" }?.value, "2")
        XCTAssertEqual(query.first { $0.name == "languages" }?.value, "en")
        XCTAssertNil(query.first { $0.name == "search" })
    }
    func testRepeatedMetadataDoesNotDuplicateFiles() {
        let file = BookFile(url: URL(string: "https://example.com/book.epub")!, format: "epub", rights: "CC0")
        XCTAssertEqual(BookFile.deduplicate([file, file, file]).count, 1)
    }
    func testDownloadReceiptRejectsTraversalAndSurvivesEncoding() throws {
        let file = BookFile(url: URL(string: "https://example.com/book.epub")!, format: "epub", rights: "CC0")
        let receipt = DownloadReceipt(ticket: DownloadTicket(bookID: "book", file: file), filename: "incoming-test.epub")
        let decoded = try JSONDecoder().decode(DownloadReceipt.self, from: JSONEncoder().encode(receipt))
        XCTAssertEqual(decoded.ticket.token, receipt.ticket.token)
        XCTAssertEqual(decoded.incomingURL()?.lastPathComponent, "incoming-test.epub")
        for path in ["../book.epub", "incoming-../book.epub", "incoming-..\\book.epub"] {
            var invalid = receipt; invalid.filename = path; XCTAssertNil(invalid.incomingURL())
        }
    }
}

@MainActor final class LibraryRegressionTests: XCTestCase {
    func testLibrarySearchSortAndReadingFilter() throws {
        let a = try LibraryBook(book: Book(id: "a", title: "Zebra", authors: ["Jane"], source: URL(string: "https://example.com")!, origin: "test"))
        let b = try LibraryBook(book: Book(id: "b", title: "Apple", authors: ["Smith"], source: URL(string: "https://example.com")!, origin: "test"))
        a.lastRead = Date(); b.completed = true
        XCTAssertEqual(LibraryQuery.select([a, b], query: "", filter: .all, sort: .title).map(\.id), ["b", "a"])
        XCTAssertEqual(LibraryQuery.select([a, b], query: "jane", filter: .all, sort: .recent).map(\.id), ["a"])
        XCTAssertEqual(LibraryQuery.select([a, b], query: "", filter: .reading, sort: .recent).map(\.id), ["a"])
        XCTAssertEqual(LibraryQuery.select([a, b], query: "", filter: .finished, sort: .recent).map(\.id), ["b"])
    }
    func testDuplicateBookmarksAreMergedAndNotesAreRetained() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Annotation.self, configurations: config)
        let context = ModelContext(container)
        _ = try AnnotationRepository.save(Annotation(bookID: "book", locator: "locator", text: "Passage"), context: context)
        _ = try AnnotationRepository.save(Annotation(bookID: "book", locator: "locator", text: "Passage", note: "Remember"), context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Annotation>()), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Annotation>()).first?.note, "Remember")
    }
    func testDeletingDownloadClearsTransferStateButPreservesPosition() throws {
        let record = try LibraryBook(book: Book(id: "a", title: "Book", authors: [], source: URL(string: "https://example.com")!, origin: "test"))
        record.downloadToken = "stale"; record.downloadError = "Failure"; record.locator = "position"; record.progress = 0.4
        try LibraryFiles.remove(record)
        XCTAssertNil(record.downloadToken); XCTAssertNil(record.downloadError)
        XCTAssertEqual(record.locator, "position"); XCTAssertEqual(record.progress, 0.4)
    }
}

@MainActor final class PDFValidationTests: XCTestCase {
    func testRealGeneratedPDFCanBeValidatedOffline() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 320, height: 480))
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            ("Folio PDF test" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: nil)
            context.beginPage()
        }
        let file = BookFile(url: URL(string: "https://example.com/test.pdf")!, format: "pdf", rights: "Test fixture")
        try await ReaderEngine.shared.validate(url, file: file)
        XCTAssertEqual(PDFDocument(url: url)?.pageCount, 2)
    }
    func testCorruptPDFIsRejected() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("Not a PDF".utf8).write(to: url)
        let file = BookFile(url: URL(string: "https://example.com/test.pdf")!, format: "pdf", rights: "Test fixture")
        do { try await ReaderEngine.shared.validate(url, file: file); XCTFail("Corrupt PDF accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("PDF")) }
    }
}

private final class CatalogStubProtocol: Foundation.URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var responses: [String: (Int, String)] = [:]
    static func set(_ responses: [String: (Int, String)]) { lock.lock(); defer { lock.unlock() }; self.responses = responses }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock(); let response = Self.responses[url.host ?? ""] ?? (500, "{}"); Self.lock.unlock()
        let http = HTTPURLResponse(url: url, statusCode: response.0, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.1.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class CatalogPaginationTests: XCTestCase {
    private func service() -> CatalogService {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CatalogStubProtocol.self]
        return CatalogService(session: URLSession(configuration: config))
    }
    func testExhaustedSourcesStopPagination() async {
        CatalogStubProtocol.set(["gutendex.com": (200, #"{"next":null,"results":[]}"#), "openlibrary.org": (200, #"{"numFound":0,"docs":[]}"#)])
        let result = await service().search("test")
        XCTAssertFalse(result.next.hasMore); XCTAssertTrue(result.messages.isEmpty)
    }
    func testFailedSourceKeepsItsCursorForRetry() async {
        CatalogStubProtocol.set(["gutendex.com": (200, #"{"next":null,"results":[]}"#), "openlibrary.org": (503, "{}")])
        let catalog = service()
        let result = await catalog.search("test")
        XCTAssertNil(result.next.gutenberg); XCTAssertEqual(result.next.openLibrary, 1)
        XCTAssertEqual(result.messages.count, 1)
        CatalogStubProtocol.set(["openlibrary.org": (200, #"{"numFound":0,"docs":[]}"#)])
        let retry = await catalog.search("test", cursor: result.next)
        XCTAssertFalse(retry.next.hasMore); XCTAssertTrue(retry.messages.isEmpty)
    }
}
