import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: \LibraryBook.added, order: .reverse) private var records: [LibraryBook]
    @Environment(\.modelContext) private var context
    @State private var query = ""
    @State private var filter: LibraryFilter = .all
    @AppStorage("librarySort") private var sort = LibrarySort.recent.rawValue
    @State private var reader: LibraryBook?
    @State private var removal: LibraryBook?
    @State private var error: String?
    var filtered: [LibraryBook] { LibraryQuery.select(records, query: query, filter: filter, sort: LibrarySort(rawValue: sort) ?? .recent) }
    var continuing: LibraryBook? { records.filter { $0.isDownloaded && $0.lastRead != nil && !$0.completed }.max { ($0.lastRead ?? .distantPast) < ($1.lastRead ?? .distantPast) } }
    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty, filter == .all, let record = continuing, let book = record.book {
                    Section("Continue reading") {
                        Button { reader = record } label: {
                            HStack(spacing: 16) {
                                BookCover(book: book, height: 100).frame(width: 64)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(book.title).font(.system(.title3, design: .serif, weight: .semibold))
                                    Text("\(Int(record.progress * 100))% complete").font(.subheadline).foregroundStyle(.secondary)
                                    Label("Continue Reading", systemImage: "play.circle.fill").font(.headline)
                                }
                            }.padding(.vertical, 6)
                        }.buttonStyle(.plain).accessibilityIdentifier("library.continue")
                    }
                }
                Section {
                    Picker("Show books", selection: $filter) {
                        ForEach(LibraryFilter.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu)
                    if filtered.isEmpty {
                        ContentUnavailableView(records.isEmpty ? "Your next chapter awaits" : "No matching books", systemImage: "books.vertical", description: Text(records.isEmpty ? "Save or download books from Discover and Search." : "Try another title, author or filter."))
                    }
                    ForEach(filtered) { record in
                        LibraryBookRow(record: record, open: { reader = record }, remove: { removal = record }, toggleCompletion: {
                            record.completed.toggle()
                            if !record.completed { record.lastRead = Date() }
                            do { try context.save() } catch { self.error = error.localizedDescription }
                        })
                    }
                } header: { Text("\(filtered.count) \(filtered.count == 1 ? "book" : "books")") }
            }.navigationTitle("Library")
                .searchable(text: $query, prompt: "Search your library")
                .toolbar {
                    Menu {
                        Picker("Sort books", selection: $sort) { ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                    } label: { Label("Sort books", systemImage: "arrow.up.arrow.down") }
                }
                .fullScreenCover(item: $reader) { ReaderDestination(record: $0) }
                .confirmationDialog("Remove this book from your library?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
                    Button("Remove book", role: .destructive) {
                        guard let record = removal else { return }
                        do { try LibraryRepository.remove(record, context: context) } catch { self.error = error.localizedDescription }
                        removal = nil
                    }
                } message: { Text("This removes the download, bookmarks and notes for this edition.") }
                .alert("Library error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }
    }
}
private struct LibraryBookRow: View {
    var record: LibraryBook
    var open: () -> Void
    var remove: () -> Void
    var toggleCompletion: () -> Void
    var body: some View {
        if let book = record.book {
            NavigationLink { BookDetailView(book: book) } label: {
                HStack(spacing: 16) {
                    BookCover(book: book, height: 100).frame(width: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title).font(.headline)
                        Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                        Label(record.completed ? "Finished" : (record.isDownloaded ? "Available offline" : record.downloadState.capitalized), systemImage: record.completed ? "checkmark.seal.fill" : (record.isDownloaded ? "checkmark.circle.fill" : "cloud")).font(.caption).foregroundStyle(.secondary)
                        ProgressView(value: record.progress).accessibilityLabel("Reading progress").accessibilityValue("\(Int(record.progress * 100)) percent")
                    }
                }.padding(.vertical, 4)
            }.accessibilityIdentifier("library.\(book.id)")
                .swipeActions(edge: .leading) { if record.isDownloaded { Button("Read", systemImage: "book", action: open).tint(.accentColor) } }
                .swipeActions { Button("Remove", role: .destructive, action: remove) }
                .contextMenu {
                    if record.isDownloaded { Button("Read", systemImage: "book", action: open) }
                    Button(record.completed ? "Mark as reading" : "Mark as finished", systemImage: "checkmark.seal", action: toggleCompletion)
                    Button("Remove from Library", role: .destructive, action: remove)
                }
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
                    LabeledContent("Currently reading", value: "\(books.filter { $0.lastRead != nil && !$0.completed }.count)")
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
                Section { LabeledContent("Folio", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1") · iOS 17+") }
            }.navigationTitle("Settings").onAppear { usage = LibraryFiles.usage() }
                .confirmationDialog("Delete every downloaded book?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete downloads", role: .destructive) {
                        do { for book in books { DownloadManager.shared.cancel(book.id); try LibraryFiles.remove(book) }; try context.save(); usage = LibraryFiles.usage() }
                        catch { self.error = error.localizedDescription }
                    }
                }
        }
    }
}
