import SwiftUI
import PDFKit
import SwiftData

struct PDFReader: UIViewControllerRepresentable {
    var record: LibraryBook; var context: ModelContext
    func makeUIViewController(context: Context) -> UINavigationController { UINavigationController(rootViewController: PDFController(record: record, context: self.context)) }
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
@MainActor final class PDFController: UIViewController {
    let record: LibraryBook; let context: ModelContext
    let pdfView = PDFView(); var clock: ReadingClock?
    private var needsRestore = true
    init(record: LibraryBook, context: ModelContext) { self.record = record; self.context = context; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Unsupported") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground; title = record.book?.title
        view.addSubview(pdfView); pdfView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor), pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor), pdfView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), pdfView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)])
        pdfView.autoScales = true; pdfView.displayMode = .singlePageContinuous
        if let url = record.fileURL, let document = PDFDocument(url: url), !document.isLocked {
            pdfView.document = document
            pdfView.accessibilityLabel = "PDF document"
        } else {
            let label = UILabel(frame: view.bounds); label.text = "The PDF is missing, locked or corrupt."; label.textAlignment = .center; view.addSubview(label)
        }
        let close = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.clock?.stop(); self?.dismiss(animated: true) })
        close.accessibilityIdentifier = "reader.close"; close.accessibilityLabel = "Close book"
        navigationItem.leftBarButtonItem = close
        navigationItem.rightBarButtonItems = [UIBarButtonItem(title: "Search", style: .plain, target: self, action: #selector(search)), UIBarButtonItem(title: "Page", style: .plain, target: self, action: #selector(pagePrompt))]
        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView)
        if pdfView.document != nil {
            clock = ReadingClock(context: context, isReading: { [weak self] in
                guard let self else { return false }
                return self.viewIfLoaded?.window != nil && self.presentedViewController == nil && self.navigationController?.presentedViewController == nil
            }); clock?.start()
        }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard needsRestore, let document = pdfView.document, document.pageCount > 0 else { return }
        needsRestore = false
        pdfView.layoutIfNeeded()
        if let page = document.page(at: PageNavigation.clamp(record.pdfPage, count: document.pageCount)) { pdfView.go(to: page) }
        pageChanged()
    }
    func presentTool(_ controller: UIViewController, animated: Bool) {
        clock?.pause(); present(controller, animated: animated)
    }
    @objc func pageChanged() {
        guard let document = pdfView.document, let page = pdfView.currentPage else { return }
        record.pdfPage = document.index(for: page)
        navigationItem.prompt = "Page \(record.pdfPage + 1) of \(document.pageCount)"
        record.progress = Double(record.pdfPage + 1) / Double(max(1, document.pageCount)); record.lastRead = Date()
        if record.progress >= 1 { record.completed = true }; try? context.save(); clock?.interact()
    }
    @objc func pagePrompt() {
        guard let document = pdfView.document, document.pageCount > 0 else { return }
        let picker = PDFPagePicker(count: document.pageCount, current: record.pdfPage, go: { [weak self] index in
            self?.dismiss(animated: true) {
                guard let self, let page = self.pdfView.document?.page(at: index) else { return }
                self.pdfView.go(to: page)
            }
        }, close: { [weak self] in self?.dismiss(animated: true) })
        let controller = UIHostingController(rootView: picker)
        controller.modalPresentationStyle = .pageSheet; controller.sheetPresentationController?.detents = [.medium()]
        presentTool(controller, animated: true)
    }
    @objc func search() {
        let alert = UIAlertController(title: "Search PDF", message: nil, preferredStyle: .alert); alert.addTextField()
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Search", style: .default) { [weak self, weak alert] _ in
            guard let self, let query = alert?.textFields?.first?.text, !query.isEmpty else { return }
            let matches = self.pdfView.document?.findString(query, withOptions: .caseInsensitive) ?? []
            let list = ReaderList(title: "PDF matches", labels: matches.map { $0.string ?? "Match" }) { [weak self] index in
                self?.dismiss(animated: true) { self?.pdfView.setCurrentSelection(matches[index], animate: true); self?.pdfView.go(to: matches[index]) }
            }
            self.presentTool(UIHostingController(rootView: list), animated: true)
        }); presentTool(alert, animated: true)
    }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); if navigationController?.isBeingDismissed == true { clock?.stop() } }
    deinit { NotificationCenter.default.removeObserver(self) }
}
struct TextReader: View {
    var record: LibraryBook
    @State var text = ""; @State var error: String?
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack { ScrollView { Text(error ?? text).textSelection(.enabled).padding() }
            .navigationTitle(record.book?.title ?? "Text").toolbar { Button("Done") { dismiss() } }
        }.task { do { if let url = record.fileURL { text = try String(contentsOf: url, encoding: .utf8) } } catch { self.error = error.localizedDescription } }
    }
}
struct ReaderDestination: View {
    var record: LibraryBook
    @Environment(\.modelContext) var context
    var body: some View {
        switch record.fileURL?.pathExtension {
        case "epub": EPUBReader(record: record, context: context).ignoresSafeArea()
        case "pdf": PDFReader(record: record, context: context).ignoresSafeArea()
        default: TextReader(record: record)
        }
    }
}

enum PageNavigation {
    static func index(for text: String, count: Int) -> Int? {
        guard count > 0, let page = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), page >= 1, page <= count else { return nil }
        return page - 1
    }
    static func clamp(_ index: Int, count: Int) -> Int { max(0, min(index, max(0, count - 1))) }
}
struct PDFPagePicker: View {
    var count: Int
    var go: (Int) -> Void
    var close: () -> Void
    @State private var text: String
    init(count: Int, current: Int, go: @escaping (Int) -> Void, close: @escaping () -> Void) {
        self.count = count; self.go = go; self.close = close
        _text = State(initialValue: String(PageNavigation.clamp(current, count: count) + 1))
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Page number", text: $text).keyboardType(.numberPad).accessibilityIdentifier("pdf.pageNumber")
                Text("Enter a page from 1 to \(count).").foregroundStyle(.secondary)
                if !text.isEmpty && PageNavigation.index(for: text, count: count) == nil { Text("That page is outside this document.").foregroundStyle(.red) }
            }.navigationTitle("Go to page")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: close) }
                    ToolbarItem(placement: .confirmationAction) { Button("Go") { if let index = PageNavigation.index(for: text, count: count) { go(index) } }.disabled(PageNavigation.index(for: text, count: count) == nil) }
                }
        }
    }
}
