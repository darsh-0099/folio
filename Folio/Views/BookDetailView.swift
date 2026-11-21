import SwiftUI
import SwiftData

struct BookDetailView: View {
    @State var book: Book
    @State private var loading = false
    @State private var error: String?
    @State private var reader: LibraryBook?
    @State private var confirmDelete = false
    @State private var confirmRemove = false
    @Environment(\.modelContext) var context
    @Query private var records: [LibraryBook]
    @ObservedObject private var downloads = DownloadManager.shared
    var record: LibraryBook? { records.first { $0.id == book.id } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                BookCover(book: book).frame(maxWidth: 230).frame(maxWidth: .infinity).padding(.top)
                Text(book.title).font(.system(.largeTitle, design: .serif, weight: .bold))
                Text(book.author.isEmpty ? "Unknown author" : book.author).font(.title3).foregroundStyle(.secondary)
                Text(book.availability).font(.callout).foregroundStyle(Color.accentColor)
                if let record, record.isDownloaded {
                    Button(record.locator != nil || record.pdfPage > 0 ? "Continue Reading" : "Read") { reader = record }.buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("reader.open")
                    ProgressView(value: record.progress) { Text("\(Int(record.progress * 100))% read") }
                }
                if record?.isDownloading == true {
                    if record?.downloadState == "retrying" { ProgressView("Trying Gutenberg distribution mirror…") }
                    else if record?.downloadState == "validating" { ProgressView("Checking book…") }
                    else if let progress = downloads.progress[book.id], progress >= 0 {
                        ProgressView(value: min(1, progress)) { Text("Downloading \(Int(min(1, progress) * 100))%") }
                    } else { ProgressView("Downloading…") }
                    Button("Cancel download", role: .destructive) { downloads.cancel(book.id) }
                } else if record?.isDownloaded != true {
                    ForEach(book.files) { file in
                        VStack(alignment: .leading) {
                            Button("Download \(file.format.uppercased())") { perform { try downloads.start(file, book: book) } }.buttonStyle(.borderedProminent).accessibilityIdentifier("download.\(file.format)")
                            Text(file.rights).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let message = record?.downloadError { Text(message).foregroundStyle(.red).font(.callout).accessibilityIdentifier("download.error") }
                if let record {
                    if record.isDownloaded { Button("Delete download", role: .destructive) { confirmDelete = true } }
                    Button("Remove from Library", role: .destructive) { confirmRemove = true }
                        .disabled(record.isDownloading)
                } else { Button("Add to Library", systemImage: "plus") { perform { _ = try LibraryRepository.save(book, context: context) } }.buttonStyle(.bordered) }
                if loading { ProgressView("Checking edition metadata…") }
                if let error { Text(error).foregroundStyle(.red); Button("Retry metadata") { Task { await enrich() } } }
                if !book.alternateEditions.isEmpty {
                    Text("Other editions and sources").font(.headline)
                    ForEach(book.alternateEditions) { edition in
                        NavigationLink { BookDetailView(book: edition) } label: {
                            Label("\(edition.origin): \(edition.title)", systemImage: "books.vertical")
                        }
                    }
                }
                Divider()
                Text("About this edition").font(.title2.bold())
                Text(book.summary.isEmpty ? "No description supplied." : book.summary).textSelection(.enabled)
                LabeledContent("Source", value: book.origin)
                if let year = book.year { LabeledContent("First published", value: String(year)) }
                LabeledContent("Languages", value: book.languages.joined(separator: ", "))
                if !book.subjects.isEmpty { Text(book.subjects.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary) }
                if !book.editions.isEmpty { Text("Open Library editions: \(book.editions.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary) }
                if book.origin == "Imported file" {
                    Text("Imported from Files. If you delete the downloaded file, import the same file again to restore it and retain your reading position.").font(.callout).foregroundStyle(.secondary)
                } else {
                    Link(book.availability.contains("Borrow") ? "Borrow through Open Library" : "View source and rights", destination: book.source)
                }
                if book.origin != "Imported file" && book.files.isEmpty && !loading { Text("No directly downloadable edition with confirmed rights was found. Use the source link for authorized access.").font(.callout).foregroundStyle(.secondary) }
            }.padding(24)
        }.navigationTitle("Book details").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete downloaded file?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete file", role: .destructive) { if let record { perform { try LibraryFiles.remove(record); try context.save() } } }
            } message: { Text("Your saved position, bookmarks and notes will remain in your library.") }
            .confirmationDialog("Remove book from Library?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove book", role: .destructive) { if let record { perform { try LibraryRepository.remove(record, context: context) } } }
            } message: { Text("The download, bookmarks and notes for this edition will be removed.") }
            .task { await enrich() }
            .fullScreenCover(item: $reader) { ReaderDestination(record: $0) }
    }
    func perform(_ work: () throws -> Void) { do { try work() } catch { self.error = error.localizedDescription } }
    func enrich() async {
        loading = true; error = nil
        defer { loading = false }
        if book.origin == "Imported file" || record?.isDownloaded == true {
            if let saved = record?.book { book = saved }
            return
        }
        do {
            if let saved = record?.book, !saved.summary.isEmpty { book = saved }
            book = try await CatalogService.shared.enrich(book)
            if let record { record.metadata = try JSONEncoder().encode(book); try context.save() }
        } catch { self.error = error.localizedDescription }
    }
}
