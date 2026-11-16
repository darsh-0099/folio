import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: \LibraryBook.added, order: .reverse) private var records: [LibraryBook]
    @State private var downloadedOnly = false
    @State private var reader: LibraryBook?
    var filtered: [LibraryBook] { records.filter { !downloadedOnly || $0.isDownloaded } }
    var body: some View {
        NavigationStack {
            List {
                Toggle("Downloaded only", isOn: $downloadedOnly)
                if filtered.isEmpty { ContentUnavailableView("Your next chapter awaits", systemImage: "books.vertical", description: Text("Save or download books from Discover and Search.")) }
                ForEach(filtered) { record in
                    if let book = record.book {
                        NavigationLink { BookDetailView(book: book) } label: {
                            HStack(spacing: 16) {
                                BookCover(book: book, height: 100).frame(width: 64)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(book.title).font(.headline); Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                                    Label(record.isDownloaded ? "Available offline" : record.downloadState.capitalized, systemImage: record.isDownloaded ? "checkmark.circle.fill" : "cloud") .font(.caption).foregroundStyle(.secondary)
                                    ProgressView(value: record.progress)
                                }
                            }
                        }.swipeActions(edge: .leading) { if record.isDownloaded { Button("Read") { reader = record }.tint(.accentColor) } }
                    }
                }
            }.navigationTitle("Library").fullScreenCover(item: $reader) { ReaderDestination(record: $0) }
        }
    }
}
struct ActivityView: View {
    @Query(sort: \ReadingDay.day) var days: [ReadingDay]
    @Query var books: [LibraryBook]
    @AppStorage("dailyGoal") var goal = 20
    var todaySeconds: Double { days.first { Calendar.current.isDateInToday($0.day) }?.seconds ?? 0 }
    var streak: (current: Int, longest: Int) { Streaks.calculate(days: days.filter { $0.seconds >= 60 }.map(\.day)) }
    var body: some View {
        NavigationStack {
            List {
                Section("Today") {
                    Text("Make room for a good book.").font(.system(.title2, design: .serif, weight: .semibold))
                    LabeledContent("Reading time", value: "\(Int(todaySeconds / 60)) minutes")
                    ProgressView(value: min(todaySeconds / (Double(goal) * 60), 1)) { Text("Daily goal: \(goal) minutes") }
                    Stepper("Goal: \(goal) minutes", value: $goal, in: 5...180, step: 5)
                }
                Section("Your reading life") {
                    LabeledContent("Current streak", value: "\(streak.current) days")
                    LabeledContent("Longest streak", value: "\(streak.longest) days")
                    LabeledContent("Books completed", value: "\(books.filter(\.completed).count)")
                    LabeledContent("Currently reading", value: "\(books.filter { $0.progress > 0 && !$0.completed }.count)")
                    LabeledContent("Total reading time", value: "\(Int(days.reduce(0) { $0 + $1.seconds } / 60)) minutes")
                }
                Section("Recent days") {
                    ForEach(days.suffix(14).reversed()) { day in LabeledContent(day.day.formatted(date: .abbreviated, time: .omitted), value: "\(Int(day.seconds / 60)) min") }
                    if days.isEmpty { Text("Start reading to see your activity here.").foregroundStyle(.secondary) }
                }
                Section { Text("A streak day requires at least one minute of reading. Time is counted while the reader is visible and the app is active; an unattended reader pauses after two minutes without navigation.").font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle("Activity")
        }
    }
}
struct SettingsView: View {
    @AppStorage("appAppearance") var appearance = "system"
    @Query var books: [LibraryBook]
    @Environment(\.modelContext) var context
    @State var usage: Int64 = 0
    @State var error: String?
    @State var confirmDelete = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("App theme", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                    NavigationLink("Reader preferences") { ReaderAppearance().navigationTitle("Reader preferences") }
                }
                Section("Storage") {
                    LabeledContent("Books on device", value: ByteCountFormatter.string(fromByteCount: usage, countStyle: .file))
                    Button("Delete all downloads", role: .destructive) { confirmDelete = true }
                    Text("Saved library entries, bookmarks and reading positions are retained.").font(.caption)
                }
                Section("AI assistance") {
                    Text("No AI provider is configured.")
                    Text("Folio does not send your book text to an AI service. System Look Up and Translate are available in the EPUB selection menu. Reading never requires an API key.").font(.callout).foregroundStyle(.secondary)
                }
                Section("Sources and privacy") {
                    Link("Project Gutenberg", destination: URL(string: "https://www.gutenberg.org/policy/terms_of_use.html")!)
                    Link("Open Library", destination: URL(string: "https://openlibrary.org/developers/api")!)
                    Link("Internet Archive", destination: URL(string: "https://archive.org/about/terms.php")!)
                    Text("Search queries are sent to Gutendex and Open Library. Covers and downloads contact the listed sources. Your library and reading activity stay on this device. No analytics or account required.").font(.caption)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section { LabeledContent("Folio", value: "1.0 · iOS 17+") }
            }.navigationTitle("Settings").onAppear { usage = LibraryFiles.usage() }
                .confirmationDialog("Delete every downloaded book?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete downloads", role: .destructive) {
                        do { for book in books where book.downloadState != "downloading" { try LibraryFiles.remove(book) }; try context.save(); usage = LibraryFiles.usage() }
                        catch { self.error = error.localizedDescription }
                    }
                }
        }
    }
}
