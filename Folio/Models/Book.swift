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
struct OpenLibraryPage: Decodable { var docs: [OpenLibraryBook] }
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
