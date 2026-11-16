import Foundation
import ReadiumShared
import ReadiumStreamer
import ReadiumAdapterGCDWebServer
import PDFKit
import CryptoKit

@MainActor final class ReaderEngine {
    static let shared = ReaderEngine()
    let httpClient = DefaultHTTPClient()
    lazy var retriever = AssetRetriever(httpClient: httpClient)
    lazy var server = GCDHTTPServer(assetRetriever: retriever)
    lazy var opener = PublicationOpener(parser: DefaultPublicationParser(httpClient: httpClient, assetRetriever: retriever, pdfFactory: DefaultPDFDocumentFactory()), contentProtections: [])
    func open(_ url: URL) async throws -> Publication {
        guard let file = FileURL(url: url) else { throw FolioError.message("Invalid local book URL.") }
        let asset = try await retriever.retrieve(url: file).get()
        let publication = try await opener.open(asset: asset, allowUserInteraction: false).get()
        guard !publication.isRestricted else { throw FolioError.message("This edition requires authorized borrowing or DRM software.") }
        return publication
    }
    func validate(_ url: URL, file: BookFile) async throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard bytes > 0, file.expectedBytes == nil || bytes == file.expectedBytes else { throw FolioError.message("The download is incomplete. Please retry.") }
        if let expected = file.md5 {
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            var digest = Insecure.MD5()
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { digest.update(data: data) }
            guard digest.finalize().map({ String(format: "%02x", $0) }).joined() == expected.lowercased() else { throw FolioError.message("The download failed its integrity check.") }
        }
        switch file.format {
        case "epub":
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            guard try handle.read(upToCount: 4) == Data([0x50, 0x4b, 0x03, 0x04]) else { throw FolioError.message("The server did not return an EPUB archive.") }
            let publication = try await open(url)
            guard !publication.readingOrder.isEmpty else { throw FolioError.message("This EPUB has no readable chapters.") }
        case "pdf":
            guard let pdf = PDFDocument(url: url), pdf.pageCount > 0, !pdf.isLocked else { throw FolioError.message("The PDF is corrupt or locked.") }
        case "txt":
            guard (try? String(contentsOf: url, encoding: .utf8)) != nil else { throw FolioError.message("This text file is not valid UTF-8.") }
        default: throw FolioError.message("Unsupported book format.")
        }
    }
}
