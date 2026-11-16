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
    init(record: LibraryBook, context: ModelContext) { self.record = record; self.context = context; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Unsupported") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground; title = record.book?.title
        pdfView.frame = view.bounds; pdfView.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.addSubview(pdfView)
        pdfView.autoScales = true; pdfView.displayMode = .singlePageContinuous
        if let url = record.fileURL, let document = PDFDocument(url: url), !document.isLocked {
            pdfView.document = document
            if let page = document.page(at: min(record.pdfPage, max(0, document.pageCount - 1))) { pdfView.go(to: page) }
        } else {
            let label = UILabel(frame: view.bounds); label.text = "The PDF is missing, locked or corrupt."; label.textAlignment = .center; view.addSubview(label)
        }
        let close = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        close.accessibilityIdentifier = "reader.close"; close.accessibilityLabel = "Close book"
        navigationItem.leftBarButtonItem = close
        navigationItem.rightBarButtonItems = [UIBarButtonItem(title: "Search", style: .plain, target: self, action: #selector(search)), UIBarButtonItem(title: "Page", style: .plain, target: self, action: #selector(pagePrompt))]
        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView)
        clock = ReadingClock(context: context); clock?.start()
    }
    @objc func pageChanged() {
        guard let document = pdfView.document, let page = pdfView.currentPage else { return }
        record.pdfPage = document.index(for: page); record.progress = Double(record.pdfPage + 1) / Double(max(1, document.pageCount)); record.lastRead = Date()
        if record.progress >= 1 { record.completed = true }; try? context.save(); clock?.interact()
    }
    @objc func pagePrompt() {
        let alert = UIAlertController(title: "Go to page", message: "1–\(pdfView.document?.pageCount ?? 0)", preferredStyle: .alert)
        alert.addTextField { $0.keyboardType = .numberPad }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Go", style: .default) { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text, let number = Int(text), let page = self.pdfView.document?.page(at: number - 1) else { return }
            self.pdfView.go(to: page)
        }); present(alert, animated: true)
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
            self.present(UIHostingController(rootView: list), animated: true)
        }); present(alert, animated: true)
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
