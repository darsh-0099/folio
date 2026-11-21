import Foundation

struct Book: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var authors: [String]
    var summary: String = ""
    var languages: [String] = []
    var subjects: [String] = []
    var year: Int?
    var cover: URL?
    var source: URL
    var origin: String
    var archiveIDs: [String] = []
    var editions: [String] = []
    var files: [BookFile] = []
    var availability: String = "Metadata only"
    var alternateEditions: [Book] = []
    var author: String { authors.joined(separator: ", ") }
    // Cross-catalog matches become an explicit edition group. Edition metadata and
    // source links remain available rather than being discarded in a title merge.
    static func deduplicate(_ books: [Book]) -> [Book] {
        var output: [Book] = []
        var ids = Set<String>(), urls = Set<URL>()
        func normalized(_ text: String) -> String {
            text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.sorted().joined(separator: " ")
        }
        for book in books {
            guard ids.insert(book.id).inserted else { continue }
            if let url = book.files.first?.url, !urls.insert(url).inserted { continue }
            if !book.author.isEmpty, let index = output.firstIndex(where: {
                $0.origin != book.origin && normalized($0.title) == normalized(book.title) && normalized($0.author) == normalized(book.author)
            }) {
                output[index].alternateEditions.append(book)
            } else { output.append(book) }
            for alternate in book.alternateEditions { ids.insert(alternate.id) }
        }
        return output
    }
}
struct BookFile: Codable, Hashable, Identifiable {
    var url: URL
    var format: String
    var rights: String
    var expectedBytes: Int64?
    var md5: String?
    var id: String { url.absoluteString }
    static func deduplicate(_ files: [BookFile]) -> [BookFile] {
        var seen = Set<URL>()
        return files.filter { seen.insert($0.url).inserted }
    }
}
enum FolioError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct GutenbergPage: Decodable { var next: URL?; var results: [GutenbergBook] }
struct GutenbergBook: Decodable {
    struct Author: Decodable { var name: String }
    var id: Int; var title: String; var authors: [Author]
    var languages: [String]; var subjects: [String]; var formats: [String: String]
    var copyright: Bool?
    var book: Book {
        let preferred = formats["application/epub+zip"]
        let files: [BookFile] = copyright == false ? preferred.flatMap(URL.init(string:)).map {
            [BookFile(url: $0.https, format: "epub", rights: "Project Gutenberg: public domain in the USA; check local law.")]
        } ?? [] : []
        return Book(id: "gutenberg:\(id)", title: title, authors: authors.map(\.name),
                    languages: languages, subjects: subjects,
                    cover: formats["image/jpeg"].flatMap(URL.init(string:))?.https,
                    source: URL(string: "https://www.gutenberg.org/ebooks/\(id)")!, origin: "Project Gutenberg",
                    files: files, availability: files.isEmpty ? "Rights not confirmed" : "Public domain in the USA")
    }
}
struct OpenLibraryPage: Decodable { var docs: [OpenLibraryBook]; var numFound: Int? }
struct OpenLibraryBook: Decodable {
    var key: String; var title: String; var author_name: [String]?
    var first_publish_year: Int?; var cover_i: Int?; var language: [String]?
    var ia: [String]?; var edition_key: [String]?; var subject: [String]?
    var ebook_access: String?
    var book: Book {
        Book(id: "ol:\(key)", title: title, authors: author_name ?? [], languages: language ?? [],
             subjects: Array((subject ?? []).prefix(12)), year: first_publish_year,
             cover: cover_i.flatMap { URL(string: "https://covers.openlibrary.org/b/id/\($0)-L.jpg") },
             source: URL(string: "https://openlibrary.org\(key)")!, origin: "Open Library",
             archiveIDs: Array((ia ?? []).prefix(4)), editions: Array((edition_key ?? []).prefix(8)),
             availability: ebook_access == "borrowable" ? "Borrow through Open Library" : "Check edition availability")
    }
}
extension URL {
    var https: URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        if components.scheme == "http" { components.scheme = "https" }
        return components.url ?? self
    }
}

/// Maintenance fallback for the same public-domain EPUB on PG's distribution host.
/// Authentication errors, missing editions and other providers never use this route.
enum GutenbergMirror {
    static func url(for original: URL, status: Int) -> URL? {
        guard [502, 503, 504].contains(status), original.scheme == "https",
              ["www.gutenberg.org", "gutenberg.org"].contains(original.host?.lowercased() ?? ""),
              original.query == nil, original.fragment == nil, original.user == nil, original.password == nil, original.port == nil else { return nil }
        let name = original.lastPathComponent.components(separatedBy: ".")
        guard name.count == 3, name[1] == "epub3", name[2] == "images", let id = Int(name[0]), id > 0,
              original.path == "/ebooks/\(id).epub3.images" else { return nil }
        return URL(string: "https://gutenberg.pglaf.org/cache/epub/\(id)/pg\(id)-images-3.epub")
    }
    static func errorMessage(status: Int) -> String {
        switch status {
        case 401, 403: return "Access denied (HTTP \(status)). View the source for authorized access."
        case 404: return "This file is no longer available (HTTP 404). Choose another edition or view the source."
        case 429: return "The source is busy (HTTP 429). Please wait before retrying."
        case 500...599: return "The source is temporarily unavailable (HTTP \(status)). Please try again later."
        default: return "The download server returned HTTP \(status). Please retry or view the source."
        }
    }
}
