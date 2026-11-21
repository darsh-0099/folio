import Foundation

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All", downloaded = "Downloaded", reading = "Reading", finished = "Finished"
    var id: String { rawValue }
}
enum LibrarySort: String, CaseIterable, Identifiable {
    case recent = "Recently read", added = "Recently added", title = "Title", author = "Author"
    var id: String { rawValue }
}
struct LibraryQuery {
    static func select(_ records: [LibraryBook], query: String, filter: LibraryFilter, sort: LibrarySort) -> [LibraryBook] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return records.filter { record in
            guard let book = record.book else { return false }
            let matches = query.isEmpty || book.title.localizedStandardContains(query) || book.author.localizedStandardContains(query)
            switch filter {
            case .all: return matches
            case .downloaded: return matches && record.isDownloaded
            case .reading: return matches && record.lastRead != nil && !record.completed
            case .finished: return matches && record.completed
            }
        }.sorted { lhs, rhs in
            switch sort {
            case .recent:
                let l = lhs.lastRead ?? .distantPast, r = rhs.lastRead ?? .distantPast
                if l != r { return l > r }
                if lhs.added != rhs.added { return lhs.added > rhs.added }
            case .added: if lhs.added != rhs.added { return lhs.added > rhs.added }
            case .title:
                let comparison = (lhs.book?.title ?? "").localizedStandardCompare(rhs.book?.title ?? "")
                if comparison != .orderedSame { return comparison == .orderedAscending }
            case .author:
                let comparison = (lhs.book?.author ?? "").localizedStandardCompare(rhs.book?.author ?? "")
                if comparison != .orderedSame { return comparison == .orderedAscending }
            }
            return lhs.id < rhs.id
        }
    }
}
