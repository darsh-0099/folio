import XCTest
import UIKit
import PDFKit
import SwiftData
@testable import Folio

final class PDFPageNavigationTests: XCTestCase {
    func testValidPageNumbersAreConvertedToZeroBasedIndices() {
        XCTAssertEqual(PageNavigation.index(for: "1", count: 10), 0)
        XCTAssertEqual(PageNavigation.index(for: " 10 ", count: 10), 9)
    }
    func testInvalidPagesNeverReachPDFKit() {
        for input in ["", "0", "-1", "11", "3.5", "hello", "999999999999999999999999999999"] {
            XCTAssertNil(PageNavigation.index(for: input, count: 10))
        }
        XCTAssertNil(PageNavigation.index(for: "1", count: 0))
    }
    func testResumeIndexIsClampedToTheDocument() {
        XCTAssertEqual(PageNavigation.clamp(-3, count: 10), 0)
        XCTAssertEqual(PageNavigation.clamp(20, count: 10), 9)
        XCTAssertEqual(PageNavigation.clamp(2, count: 10), 2)
    }
}

@MainActor final class BookImportTests: XCTestCase {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: LibraryBook.self, Annotation.self, ReadingDay.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    private func pdf() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 320, height: 480), format: {
            let format = UIGraphicsPDFRendererFormat(); format.documentInfo = [kCGPDFContextTitle as String: "Imported test PDF", kCGPDFContextAuthor as String: "Folio tests"]; return format
        }())
        try renderer.writePDF(to: url) { context in context.beginPage(); ("A local document" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: nil) }
        return url
    }
    func testPDFImportCreatesARealOfflineRecordWithMetadata() async throws {
        let source = try pdf(); defer { try? FileManager.default.removeItem(at: source) }
        let store = try container(), context = ModelContext(store)
        let record = try await BookImporter.importBook(at: source, context: context)
        defer { try? LibraryFiles.remove(record) }
        XCTAssertTrue(record.isDownloaded)
        XCTAssertEqual(record.book?.title, "Imported test PDF")
        XCTAssertEqual(record.book?.authors, ["Folio tests"])
        XCTAssertEqual(record.book?.origin, "Imported file")
        XCTAssertEqual(PDFDocument(url: try XCTUnwrap(record.fileURL))?.pageCount, 1)
        XCTAssertTrue(record.id.hasPrefix("local:"))
    }
    func testDuplicateImportDoesNotDuplicateFilesOrEraseProgress() async throws {
        let source = try pdf(); defer { try? FileManager.default.removeItem(at: source) }
        let store = try container(), context = ModelContext(store)
        let first = try await BookImporter.importBook(at: source, context: context)
        defer { try? LibraryFiles.remove(first) }
        first.locator = "saved locator"; first.progress = 0.4; try context.save()
        let path = first.relativePath
        let second = try await BookImporter.importBook(at: source, context: context)
        XCTAssertEqual(first.id, second.id); XCTAssertEqual(second.relativePath, path)
        XCTAssertEqual(second.locator, "saved locator"); XCTAssertEqual(second.progress, 0.4)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LibraryBook>()), 1)
    }
    func testReimportAfterFileDeletionRestoresFileAndPreservesPosition() async throws {
        let source = try pdf(); defer { try? FileManager.default.removeItem(at: source) }
        let store = try container(), context = ModelContext(store)
        let first = try await BookImporter.importBook(at: source, context: context)
        first.pdfPage = 3; first.progress = 0.6; try LibraryFiles.remove(first); try context.save()
        let restored = try await BookImporter.importBook(at: source, context: context)
        defer { try? LibraryFiles.remove(restored) }
        XCTAssertTrue(restored.isDownloaded); XCTAssertEqual(restored.pdfPage, 3); XCTAssertEqual(restored.progress, 0.6)
    }
    func testValidEPUBImportReadsRealPublicationMetadata() async throws {
        let source = try XCTUnwrap(Bundle(for: BookImportTests.self).url(forResource: "Minimal", withExtension: "epub"))
        let store = try container(), context = ModelContext(store)
        let record = try await BookImporter.importBook(at: source, context: context)
        defer { try? LibraryFiles.remove(record) }
        XCTAssertTrue(record.isDownloaded)
        XCTAssertEqual(record.book?.title, "Folio test publication")
        XCTAssertEqual(record.book?.authors, ["Folio contributors"])
        let publication = try await ReaderEngine.shared.open(XCTUnwrap(record.fileURL))
        XCTAssertFalse(publication.readingOrder.isEmpty)
    }
    func testUnicodeTextImportIsStoredOffline() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("Café 日本語 — a local book".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let store = try container(), context = ModelContext(store)
        let record = try await BookImporter.importBook(at: source, context: context)
        defer { try? LibraryFiles.remove(record) }
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(record.fileURL), encoding: .utf8), "Café 日本語 — a local book")
    }
    func testOversizedPlainTextIsRejectedWithoutLoadingIt() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        FileManager.default.createFile(atPath: source.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: source) }
        let handle = try FileHandle(forWritingTo: source); try handle.truncate(atOffset: 10_000_001); try handle.close()
        let file = BookFile(url: source, format: "txt", rights: "Test fixture")
        do { try await ReaderEngine.shared.validate(source, file: file); XCTFail("Oversized text accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("10 MB")) }
    }
    func testInvalidEPUBIsNotAddedToLibrary() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        try Data("Not an EPUB".utf8).write(to: source); defer { try? FileManager.default.removeItem(at: source) }
        let store = try container(), context = ModelContext(store)
        do { _ = try await BookImporter.importBook(at: source, context: context); XCTFail("Invalid EPUB imported") } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LibraryBook>()), 0)
    }
    func testUnsupportedFileTypeIsRejected() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".html")
        try Data("<html>Not a book</html>".utf8).write(to: source); defer { try? FileManager.default.removeItem(at: source) }
        XCTAssertThrowsError(try FileImportStager.stage(source))
    }
    func testEditedNoteKeepsItsIdentityAndLocator() throws {
        let store = try container(), context = ModelContext(store)
        let annotation = Annotation(bookID: "book", locator: "stable locator", text: "Passage", note: "Old note")
        _ = try AnnotationRepository.save(annotation, context: context)
        let id = annotation.id
        try AnnotationRepository.updateNote(annotation, note: "Revised note — café", context: context)
        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<Annotation>()).first)
        XCTAssertEqual(stored.id, id); XCTAssertEqual(stored.locator, "stable locator")
        XCTAssertEqual(stored.note, "Revised note — café")
    }
}
