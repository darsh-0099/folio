import Foundation

actor CatalogService {
    static let shared = CatalogService()
    private var lastRequest: [String: Date] = [:]
    private var cache: [URL: (Date, Data)] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.urlCache = URLCache(memoryCapacity: 16_000_000, diskCapacity: 40_000_000)
        return URLSession(configuration: config)
    }()
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
        request.setValue("Folio/1.0 (personal iOS ebook reader; com.folio.reader)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw FolioError.message("The catalog is unavailable. Please try again later.")
        }
        let result = try JSONDecoder().decode(T.self, from: data)
        cache[url] = (Date(), data)
        return result
    }
    func search(_ query: String, field: String = "q", language: String = "", page: Int = 1) async -> ([Book], [String]) {
        async let gutenberg = gutenbergSearch(query, language: language, page: page)
        async let library = openLibrarySearch(query, field: field, language: language, page: page)
        let results = await [gutenberg, library]
        return (Book.deduplicate(results.flatMap(\.0)), results.flatMap(\.1))
    }
    private func gutenbergSearch(_ query: String, language: String, page: Int) async -> ([Book], [String]) {
        do {
            var c = URLComponents(string: "https://gutendex.com/books/")!
            c.queryItems = [.init(name: "search", value: query), .init(name: "page", value: String(page)), .init(name: "copyright", value: "false")]
            if !language.isEmpty { c.queryItems?.append(.init(name: "languages", value: language)) }
            let response: GutenbergPage = try await get(c.url!)
            return (response.results.map(\.book), [])
        } catch { return ([], ["Project Gutenberg: \(error.localizedDescription)"]) }
    }
    private func openLibrarySearch(_ query: String, field: String, language: String, page: Int) async -> ([Book], [String]) {
        do {
            var c = URLComponents(string: "https://openlibrary.org/search.json")!
            c.queryItems = [.init(name: field, value: query.isEmpty ? "public domain" : query),
                            .init(name: "limit", value: "24"), .init(name: "page", value: String(page)),
                            .init(name: "fields", value: "key,title,author_name,first_publish_year,cover_i,language,ia,edition_key,subject,ebook_access")]
            if !language.isEmpty { c.queryItems?.append(.init(name: "language", value: Self.olLanguage(language))) }
            let response: OpenLibraryPage = try await get(c.url!)
            return (response.docs.map(\.book), [])
        } catch { return ([], ["Open Library: \(error.localizedDescription)"]) }
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
struct ArchiveItem: Decodable {
    struct Metadata: Decodable {
        var licenseurl: String?; var rights: String?; var access_restricted_item: String?
        enum CodingKeys: String, CodingKey { case licenseurl, rights, access_restricted_item }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            licenseurl = try? c.decode(String.self, forKey: .licenseurl)
            rights = try? c.decode(String.self, forKey: .rights)
            access_restricted_item = (try? c.decode(String.self, forKey: .access_restricted_item)) ?? ((try? c.decode(Bool.self, forKey: .access_restricted_item)) == true ? "true" : nil)
        }
    }
    struct File: Decodable { var name: String; var format: String?; var size: String?; var md5: String?; var `private`: String? }
    var metadata: Metadata; var files: [File]; var is_dark: Bool?
    func downloads(identifier: String) -> [BookFile] {
        let license = (metadata.licenseurl ?? "").lowercased()
        let allowed = ["https://creativecommons.org/publicdomain/zero/1.0/", "https://creativecommons.org/publicdomain/mark/1.0/", "https://creativecommons.org/licenses/by/4.0/", "https://creativecommons.org/licenses/by-sa/4.0/"]
        guard is_dark != true, !["true", "1"].contains((metadata.access_restricted_item ?? "").lowercased()), allowed.contains(license) else { return [] }
        return files.compactMap { file in
            guard file.private != "true", !file.name.contains(".."), !file.name.contains("/"),
                  let ext = file.name.split(separator: ".").last.map(String.init)?.lowercased(), ["epub", "pdf", "txt"].contains(ext) else { return nil }
            let url = URL(string: "https://archive.org/download/\(identifier)/")!.appendingPathComponent(file.name)
            return BookFile(url: url, format: ext, rights: license, expectedBytes: file.size.flatMap(Int64.init), md5: file.md5)
        }
    }
}
