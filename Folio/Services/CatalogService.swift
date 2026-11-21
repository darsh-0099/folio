import Foundation

struct CatalogCursor: Equatable {
    var gutenberg: Int? = 1
    var openLibrary: Int? = 1
    var hasMore: Bool { gutenberg != nil || openLibrary != nil }
}
struct CatalogPage {
    var books: [Book]
    var messages: [String]
    var next: CatalogCursor
}

actor CatalogService {
    static let shared = CatalogService()
    private var lastRequest: [String: Date] = [:]
    private var cache: [URL: (Date, Data)] = [:]
    private let session: URLSession
    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.urlCache = URLCache(memoryCapacity: 16_000_000, diskCapacity: 40_000_000)
            self.session = URLSession(configuration: config)
        }
    }
    func get<T: Decodable>(_ url: URL, as: T.Type = T.self) async throws -> T {
        guard url.scheme == "https" else { throw FolioError.message("An insecure catalog URL was rejected.") }
        if let (date, data) = cache[url], Date().timeIntervalSince(date) < 900 {
            return try JSONDecoder().decode(T.self, from: data)
        }
        let host = url.host ?? ""
        // Reserve a slot before suspension, so concurrent callers remain spaced out.
        let slot = max(Date(), (lastRequest[host] ?? .distantPast).addingTimeInterval(1.1))
        lastRequest[host] = slot
        let delay = slot.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        var request = URLRequest(url: url)
        request.setValue("Folio/1.2 (personal iOS ebook reader; com.folio.reader)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw FolioError.message("The catalog is unavailable. Please try again later.")
        }
        let result = try JSONDecoder().decode(T.self, from: data)
        cache = cache.filter { Date().timeIntervalSince($0.value.0) < 900 }
        if cache.count >= 128, let oldest = cache.min(by: { $0.value.0 < $1.value.0 })?.key { cache[oldest] = nil }
        cache[url] = (Date(), data)
        return result
    }
    func search(_ query: String, field: String = "q", language: String = "", cursor: CatalogCursor = CatalogCursor()) async -> CatalogPage {
        async let gutenberg = gutenbergSearch(query, field: field, language: language, page: cursor.gutenberg)
        async let library = openLibrarySearch(query, field: field, language: language, page: cursor.openLibrary)
        let (g, o) = await (gutenberg, library)
        return CatalogPage(books: Book.deduplicate(g.books + o.books), messages: [g.error, o.error].compactMap { $0 },
                           next: CatalogCursor(gutenberg: g.next, openLibrary: o.next))
    }
    nonisolated static func gutenbergURL(_ query: String, field: String, language: String, page: Int) -> URL {
        var c = URLComponents(string: "https://gutendex.com/books/")!
        c.queryItems = [.init(name: field == "subject" ? "topic" : "search", value: query), .init(name: "page", value: String(page)), .init(name: "copyright", value: "false")]
        if !language.isEmpty { c.queryItems?.append(.init(name: "languages", value: language)) }
        return c.url!
    }
    private struct SourcePage {
        var books: [Book] = []
        var next: Int?
        var error: String?
    }
    private func gutenbergSearch(_ query: String, field: String, language: String, page: Int?) async -> SourcePage {
        guard let page else { return SourcePage() }
        do {
            let response: GutenbergPage = try await get(Self.gutenbergURL(query, field: field, language: language, page: page))
            return SourcePage(books: response.results.map(\.book), next: response.next == nil ? nil : page + 1)
        } catch { return SourcePage(next: page, error: "Project Gutenberg: \(error.localizedDescription)") }
    }
    private func openLibrarySearch(_ query: String, field: String, language: String, page: Int?) async -> SourcePage {
        guard let page else { return SourcePage() }
        do {
            var c = URLComponents(string: "https://openlibrary.org/search.json")!
            let field = ["q", "title", "author", "subject"].contains(field) ? field : "q"
            c.queryItems = [.init(name: field, value: query.isEmpty ? "public domain" : query),
                            .init(name: "limit", value: "24"), .init(name: "page", value: String(page)),
                            .init(name: "fields", value: "key,title,author_name,first_publish_year,cover_i,language,ia,edition_key,subject,ebook_access")]
            if !language.isEmpty { c.queryItems?.append(.init(name: "language", value: Self.olLanguage(language))) }
            let response: OpenLibraryPage = try await get(c.url!)
            let more = response.numFound.map { page * 24 < $0 } ?? (response.docs.count == 24)
            return SourcePage(books: response.docs.map(\.book), next: more && !response.docs.isEmpty ? page + 1 : nil)
        } catch { return SourcePage(next: page, error: "Open Library: \(error.localizedDescription)") }
    }
    static func olLanguage(_ code: String) -> String {
        ["en":"eng", "fr":"fre", "de":"ger", "es":"spa", "it":"ita", "pt":"por"][code] ?? code
    }
    func enrich(_ original: Book) async throws -> Book {
        var book = original
        if book.origin == "Open Library" {
            struct Work: Decodable {
                struct Text: Decodable { var value: String }
                var description: String?
                enum CodingKeys: String, CodingKey { case description }
                init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    description = (try? c.decode(String.self, forKey: .description)) ?? (try? c.decode(Text.self, forKey: .description).value)
                }
            }
            let work: Work = try await get(book.source.appendingPathExtension("json"))
            book.summary = work.description ?? "No description supplied by Open Library."
            for id in book.archiveIDs {
                let files = (try? await archiveFiles(id)) ?? []
                book.files.append(contentsOf: files)
            }
            book.files = BookFile.deduplicate(book.files)
            if !book.files.isEmpty { book.availability = "Openly licensed edition available" }
        } else {
            book.summary = "A Project Gutenberg edition. Download availability is based on the catalog’s copyright declaration. Check the source record and copyright law in your country before downloading."
        }
        return book
    }
    func archiveFiles(_ identifier: String) async throws -> [BookFile] {
        guard identifier.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil else { return [] }
        let item: ArchiveItem = try await get(URL(string: "https://archive.org/metadata/\(identifier)")!)
        return item.downloads(identifier: identifier)
    }
}
private extension KeyedDecodingContainer {
    func archiveFlag(forKey key: Key) -> Bool? {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return nil }
        if let value = try? decode(Bool.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return value != 0 }
        if let value = try? decode(String.self, forKey: key) {
            return !["false", "0"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        return true // Unrecognized access flags are restricted, never guessed public.
    }
}
struct ArchiveItem: Decodable {
    struct Metadata: Decodable {
        var licenseurl: String?; var rights: String?; var access_restricted_item: Bool?
        enum CodingKeys: String, CodingKey { case licenseurl, rights, access_restricted_item }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            licenseurl = try? c.decode(String.self, forKey: .licenseurl)
            rights = try? c.decode(String.self, forKey: .rights)
            access_restricted_item = c.archiveFlag(forKey: .access_restricted_item)
        }
    }
    struct File: Decodable {
        var name: String; var size: String?; var md5: String?; var isPrivate: Bool?
        enum CodingKeys: String, CodingKey { case name, size, md5; case isPrivate = "private" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            size = (try? c.decode(String.self, forKey: .size)) ?? (try? c.decode(Int64.self, forKey: .size)).map(String.init)
            md5 = try? c.decode(String.self, forKey: .md5)
            isPrivate = c.archiveFlag(forKey: .isPrivate)
        }
    }
    var metadata: Metadata; var files: [File]; var is_dark: Bool?
    enum CodingKeys: String, CodingKey { case metadata, files, is_dark }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metadata = try c.decode(Metadata.self, forKey: .metadata)
        files = try c.decode([File].self, forKey: .files)
        is_dark = c.archiveFlag(forKey: .is_dark)
    }
    func downloads(identifier: String) -> [BookFile] {
        guard var license = URLComponents(string: (metadata.licenseurl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(license.scheme?.lowercased() ?? ""), license.host?.lowercased() == "creativecommons.org",
              license.user == nil, license.password == nil, license.port == nil, license.query == nil, license.fragment == nil else { return [] }
        var path = license.path.lowercased()
        if !path.hasSuffix("/") { path += "/" }
        guard ["/publicdomain/zero/1.0/", "/publicdomain/mark/1.0/", "/licenses/by/4.0/", "/licenses/by-sa/4.0/"].contains(path),
              is_dark != true, metadata.access_restricted_item != true else { return [] }
        license.scheme = "https"; license.host = "creativecommons.org"; license.path = path
        guard let rights = license.url?.absoluteString else { return [] }
        return BookFile.deduplicate(files.compactMap { file in
            guard file.isPrivate != true, !file.name.contains(".."), !file.name.contains("/"), !file.name.contains("\\"),
                  let ext = file.name.split(separator: ".").last.map(String.init)?.lowercased(), ["epub", "pdf", "txt"].contains(ext) else { return nil }
            let bytes = file.size.flatMap(Int64.init)
            if let bytes, bytes <= 0 { return nil }
            let url = URL(string: "https://archive.org/download/\(identifier)/")!.appendingPathComponent(file.name)
            return BookFile(url: url, format: ext, rights: rights, expectedBytes: bytes, md5: file.md5)
        })
    }
}
