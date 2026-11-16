import SwiftUI

@MainActor final class CatalogViewModel: ObservableObject {
    @Published var books: [Book] = []
    @Published var loading = false
    @Published var messages: [String] = []
    @Published var query = ""
    @Published var field = "q"
    @Published var language = ""
    private var generation = UUID()
    private var page = 1
    func load(more: Bool = false) async {
        let token = UUID(); generation = token
        if !more { page = 1 }
        loading = true
        let (results, messages) = await CatalogService.shared.search(query, field: field, language: language, page: page)
        guard token == generation, !Task.isCancelled else { return }
        self.messages = messages
        books = Book.deduplicate((more ? books : []) + results)
        if !results.isEmpty { page += 1 }
        loading = false
    }
}
struct CatalogView: View {
    var discover = false
    @StateObject private var model = CatalogViewModel()
    let categories = ["Fiction", "Adventure", "History", "Science", "Poetry", "Philosophy"]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if discover {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("A world between\nthe pages.").font(.system(.largeTitle, design: .serif, weight: .bold))
                            Text("Find your next great read in the open library.").foregroundStyle(.secondary)
                        }.padding(.vertical)
                        ScrollView(.horizontal, showsIndicators: false) { HStack {
                            ForEach(categories, id: \.self) { category in
                                Button(category) { model.query = category; Task { await model.load() } }
                                    .buttonStyle(.bordered).tint(.accentColor)
                            }
                        } }
                        Text(model.query.isEmpty ? "Popular public-domain books" : model.query).font(.title2.bold())
                    } else {
                        HStack {
                            Picker("Search by", selection: $model.field) { Text("All").tag("q"); Text("Title").tag("title"); Text("Author").tag("author"); Text("Subject").tag("subject") }
                            Picker("Language", selection: $model.language) { Text("All languages").tag(""); Text("English").tag("en"); Text("French").tag("fr"); Text("German").tag("de"); Text("Spanish").tag("es"); Text("Italian").tag("it"); Text("Portuguese").tag("pt") }
                        }.pickerStyle(.menu)
                    }
                    ForEach(model.messages, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
                    if model.books.isEmpty && !model.loading {
                        ContentUnavailableView("No books found", systemImage: "books.vertical", description: Text("Try another search or check your connection."))
                        Button("Retry") { Task { await model.load() } }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 20)], spacing: 24) {
                        ForEach(model.books) { book in NavigationLink(value: book) { BookCard(book: book) }.buttonStyle(.plain) }
                    }
                    if model.loading { ProgressView().frame(maxWidth: .infinity) }
                    else if !model.books.isEmpty { Button("Load more") { Task { await model.load(more: true) } }.frame(maxWidth: .infinity) }
                    Text("Open Library · Internet Archive · Project Gutenberg\nPublic-domain status varies by country. Source records contain rights information.").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(discover ? "Discover" : "Search")
            .searchable(text: $model.query, prompt: "Title, author or subject")
            .onSubmit(of: .search) { Task { await model.load() } }
            .onChange(of: model.field) { Task { await model.load() } }
            .onChange(of: model.language) { Task { await model.load() } }
            .navigationDestination(for: Book.self) { BookDetailView(book: $0) }
            .task { if model.books.isEmpty { await model.load() } }
            .refreshable { await model.load() }
        }
    }
}
struct BookCover: View {
    var book: Book
    var height: CGFloat = 205
    var body: some View {
        AsyncImage(url: book.cover) { image in image.resizable().scaledToFit() } placeholder: {
            ZStack {
                LinearGradient(colors: [Color.accentColor.opacity(0.7), Color.accentColor.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 12) { Image(systemName: "book.closed").font(.largeTitle); Text(book.title).font(.system(.headline, design: .serif)).multilineTextAlignment(.center).lineLimit(4) }.padding().foregroundStyle(.white)
            }
        }.frame(maxWidth: .infinity).frame(height: height).clipShape(RoundedRectangle(cornerRadius: 10)).shadow(color: .black.opacity(0.12), radius: 6, y: 4).accessibilityHidden(true)
    }
}
struct BookCard: View {
    var book: Book
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BookCover(book: book)
            Text(book.title).font(.headline).lineLimit(2)
            Text(book.author.isEmpty ? "Unknown author" : book.author).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            Text(book.files.isEmpty ? book.origin : "EPUB available").font(.caption).foregroundStyle(Color.accentColor)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}
