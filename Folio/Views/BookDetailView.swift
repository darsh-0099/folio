import SwiftUI
import SwiftData

struct BookDetailView: View {
    @State var book: Book
    @State private var loading = false
    @State private var error: String?
    @State private var reader: LibraryBook?
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
                    Button(record.locator != nil || record.pdfPage > 0 ? "Continue Reading" : "Read") { reader = record }.buttonStyle(.borderedProminent).controlSize(.large)
                    ProgressView(value: record.progress) { Text("\(Int(record.progress * 100))% read") }
                }
                if record?.downloadState == "downloading" {
                    ProgressView(value: downloads.progress[book.id] ?? 0) { Text("Downloading…") }
                    Button("Cancel download", role: .destructive) { downloads.cancel(book.id) }
                } else if record?.isDownloaded != true {
                    ForEach(book.files) { file in
                        VStack(alignment: .leading) {
                            Button("Download \(file.format.uppercased())") { perform { try downloads.start(file, book: book) } }.buttonStyle(.borderedProminent)
                            Text(file.rights).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let message = record?.downloadError { Text(message).foregroundStyle(.red).font(.callout) }
                if let record {
                    if record.isDownloaded { Button("Delete download", role: .destructive) { perform { try LibraryFiles.remove(record); try context.save() } } }
                    Button("Remove from Library", role: .destructive) {
                        perform {
                            downloads.cancel(record.id); try LibraryFiles.remove(record)
                            let id = record.id
                            for annotation in try context.fetch(FetchDescriptor<Annotation>(predicate: #Predicate { $0.bookID == id })) { context.delete(annotation) }
                            context.delete(record); try context.save()
                        }
                    }.disabled(record.downloadState == "downloading")
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
                Link(book.availability.contains("Borrow") ? "Borrow through Open Library" : "View source and rights", destination: book.source)
                if book.files.isEmpty && !loading { Text("No directly downloadable edition with confirmed rights was found. Use the source link for authorized access.").font(.callout).foregroundStyle(.secondary) }
            }.padding(24)
        }.navigationTitle("Book details").navigationBarTitleDisplayMode(.inline)
            .task { await enrich() }
            .fullScreenCover(item: $reader) { ReaderDestination(record: $0) }
    }
    func perform(_ work: () throws -> Void) { do { try work() } catch { self.error = error.localizedDescription } }
    func enrich() async {
        loading = true; error = nil
        do { book = try await CatalogService.shared.enrich(book) } catch { self.error = error.localizedDescription }
        loading = false
    }
}
