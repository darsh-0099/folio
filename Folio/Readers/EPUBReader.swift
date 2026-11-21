import SwiftUI
import SwiftData
import ReadiumNavigator
import ReadiumShared
import AVFoundation

struct EPUBReader: UIViewControllerRepresentable {
    let record: LibraryBook
    let context: ModelContext
    func makeUIViewController(context: Context) -> UINavigationController {
        UINavigationController(rootViewController: EPUBController(record: record, context: self.context))
    }
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
@MainActor final class EPUBController: UIViewController, EPUBNavigatorDelegate {
    let record: LibraryBook
    let context: ModelContext
    var navigator: EPUBNavigatorViewController?
    var publication: Publication?
    var searchIterator: SearchIterator?
    let speech = AVSpeechSynthesizer()
    var clock: ReadingClock?
    var loading = UIActivityIndicatorView(style: .large)
    init(record: LibraryBook, context: ModelContext) { self.record = record; self.context = context; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        title = record.book?.title
        let close = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.clock?.stop(); self?.dismiss(animated: true) })
        close.accessibilityIdentifier = "reader.close"; close.accessibilityLabel = "Close book"
        navigationItem.leftBarButtonItem = close
        loading.center = view.center; loading.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.addSubview(loading); loading.startAnimating()
        Task { await load() }
    }
    func load() async {
        do {
            guard let url = record.fileURL, record.isDownloaded else { throw FolioError.message("The downloaded file is missing. Download this edition again.") }
            let publication = try await ReaderEngine.shared.open(url)
            self.publication = publication
            let location = record.locator.flatMap { try? Locator(jsonString: $0) }
            let config = EPUBNavigatorViewController.Configuration(preferences: ReaderSettings.preferences,
                editingActions: EditingAction.defaultActions + [EditingAction(title: "Highlight", action: #selector(highlight)), EditingAction(title: "Add Note", action: #selector(addNote)), EditingAction(title: "Read Aloud", action: #selector(speakSelection))])
            let navigator = try EPUBNavigatorViewController(publication: publication, initialLocation: location, config: config, httpServer: ReaderEngine.shared.server)
            self.navigator = navigator; navigator.delegate = self
            addChild(navigator); view.addSubview(navigator.view); navigator.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([navigator.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), navigator.view.trailingAnchor.constraint(equalTo: view.trailingAnchor), navigator.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), navigator.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)])
            navigator.didMove(toParent: self); loading.removeFromSuperview()
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(image: UIImage(systemName: "textformat.size"), style: .plain, target: self, action: #selector(appearance)),
                UIBarButtonItem(image: UIImage(systemName: "bookmark"), style: .plain, target: self, action: #selector(bookmark)),
                UIBarButtonItem(image: UIImage(systemName: "list.bullet"), style: .plain, target: self, action: #selector(contents))]
            navigationItem.rightBarButtonItems?.enumerated().forEach { index, item in item.accessibilityLabel = ["Reader appearance", "Bookmark this position", "Chapters, search and annotations"][index] }
            restoreHighlights()
            clock = ReadingClock(context: context, isReading: { [weak self] in
                guard let self else { return false }
                return self.viewIfLoaded?.window != nil && self.presentedViewController == nil && self.navigationController?.presentedViewController == nil
            }); clock?.start()
        } catch { loading.stopAnimating(); showError(error) }
    }
    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        record.locator = locator.jsonString; record.progress = min(1, max(0, locator.locations.totalProgression ?? record.progress))
        record.lastRead = Date(); if record.progress >= 0.995 { record.completed = true }
        do { try context.save() } catch { showError(error) }
        clock?.interact()
    }
    func navigator(_ navigator: Navigator, presentError error: NavigatorError) { showError(error) }
    func navigator(_ navigator: Navigator, didFailToLoadResourceAt href: RelativeURL, withError error: ReadError) { showError(error) }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); if isBeingDismissed || navigationController?.isBeingDismissed == true { clock?.stop(); speech.stopSpeaking(at: .immediate) } }
    func presentTool(_ controller: UIViewController, animated: Bool) {
        clock?.pause(); present(controller, animated: animated)
    }
    @objc func bookmark() {
        guard let location = navigator?.currentSelection?.locator ?? navigator?.currentLocation, let json = location.jsonString else { return }
        persist(Annotation(bookID: record.id, locator: json, text: location.text.highlight ?? location.title ?? "Reading position"))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    @objc func highlight() { saveSelection(note: "") }
    @objc func addNote() {
        guard navigator?.currentSelection != nil else { return }
        let alert = UIAlertController(title: "Note", message: "Attach a note to the selected passage.", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Your note" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in self?.saveSelection(note: alert?.textFields?.first?.text ?? "") })
        presentTool(alert, animated: true)
    }
    func saveSelection(note: String) {
        guard let location = navigator?.currentSelection?.locator, let json = location.jsonString else { return }
        persist(Annotation(bookID: record.id, locator: json, text: location.text.highlight ?? "Passage", note: note, kind: "highlight"))
        navigator?.clearSelection(); restoreHighlights()
    }
    func persist(_ annotation: Annotation) {
        do { _ = try AnnotationRepository.save(annotation, context: context) } catch { showError(error) }
    }
    func annotations() -> [Annotation] {
        let id = record.id
        return (try? context.fetch(FetchDescriptor<Annotation>(predicate: #Predicate { $0.bookID == id }, sortBy: [SortDescriptor(\.created)]))) ?? []
    }
    func restoreHighlights() {
        navigator?.apply(decorations: annotations().filter { $0.kind == "highlight" }.compactMap {
            guard let locator = try? Locator(jsonString: $0.locator) else { return nil }
            return Decoration(id: $0.id.uuidString, locator: locator, style: .highlight(tint: .systemYellow, isActive: false))
        }, in: "highlights")
    }
    @objc func appearance() {
        let controller = UIHostingController(rootView: ReaderAppearanceSheet(changed: { [weak self] in self?.navigator?.submitPreferences(ReaderSettings.preferences) }, close: { [weak self] in self?.dismiss(animated: true) }))
        controller.modalPresentationStyle = .pageSheet
        controller.sheetPresentationController?.detents = [.medium(), .large()]
        presentTool(controller, animated: true)
    }
    @objc func contents() {
        let menu = UIAlertController(title: "Reading tools", message: nil, preferredStyle: .actionSheet)
        menu.addAction(UIAlertAction(title: "Chapters", style: .default) { [weak self] _ in self?.chapters() })
        menu.addAction(UIAlertAction(title: "Search in book", style: .default) { [weak self] _ in self?.searchPrompt() })
        menu.addAction(UIAlertAction(title: "Bookmarks, highlights and notes", style: .default) { [weak self] _ in self?.showAnnotations() })
        menu.addAction(UIAlertAction(title: "Speech controls (selected text)", style: .default) { [weak self] _ in self?.speechControls() })
        menu.addAction(UIAlertAction(title: "Mark finished", style: .default) { [weak self] _ in self?.record.completed = true; try? self?.context.save() })
        menu.addAction(UIAlertAction(title: "Cancel", style: .cancel)); presentTool(menu, animated: true)
    }
    func chapters() {
        Task {
            guard let publication else { return }
            do {
                let links = try await publication.tableOfContents().get()
                func flatten(_ links: [ReadiumShared.Link], depth: Int = 0) -> [(String, ReadiumShared.Link)] {
                    links.flatMap { [(String(repeating: "  ", count: depth) + ($0.title ?? "Chapter"), $0)] + flatten($0.children, depth: depth + 1) }
                }
                let rows = flatten(links)
                showList(title: "Chapters", labels: rows.map(\.0)) { [weak self] index in Task { await self?.navigator?.go(to: rows[index].1) } }
            } catch { showError(error) }
        }
    }
    func showAnnotations() {
        let items = annotations()
        let list = AnnotationList(items: items, onSelect: { [weak self] item in
            guard let locator = try? Locator(jsonString: item.locator) else { return }
            self?.dismiss(animated: true) { Task { await self?.navigator?.go(to: locator) } }
        }, onDelete: { [weak self] item in
            self?.context.delete(item); try? self?.context.save(); self?.restoreHighlights()
        }, onClose: { [weak self] in self?.dismiss(animated: true) })
        presentTool(UIHostingController(rootView: list), animated: true)
    }
    func searchPrompt() {
        let alert = UIAlertController(title: "Search in book", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Words or phrase" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Search", style: .default) { [weak self, weak alert] _ in
            guard let self, let query = alert?.textFields?.first?.text, !query.isEmpty else { return }
            Task {
                do {
                    self.searchIterator = try await self.publication?.search(query: query).get()
                    await self.nextSearchPage()
                } catch { self.showError(error) }
            }
        }); presentTool(alert, animated: true)
    }
    func nextSearchPage() async {
        do {
            let collection = try await searchIterator?.next().get()
            let locators = collection?.locators ?? []
            showList(title: "Search results", labels: locators.map { $0.text.highlight ?? $0.title ?? "Match" } + (collection == nil ? [] : ["More results…"])) { [weak self] index in
                if index < locators.count { Task { await self?.navigator?.go(to: locators[index]) } }
                else { Task { await self?.nextSearchPage() } }
            }
        } catch { showError(error) }
    }
    func showList(title: String, labels: [String], select: @escaping (Int) -> Void) {
        let list = ReaderList(title: title, labels: labels, select: { [weak self] index in self?.dismiss(animated: true) { select(index) } })
        presentTool(UIHostingController(rootView: list), animated: true)
    }
    @objc func speakSelection() {
        guard let text = navigator?.currentSelection?.locator.text.highlight, !text.isEmpty else { return }
        speech.stopSpeaking(at: .immediate)
        speech.speak(AVSpeechUtterance(string: text))
    }
    func speechControls() {
        let alert = UIAlertController(title: "Read selected text aloud", message: "Select a passage and choose Read Aloud. Speech stops when you leave the reader.", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Play selected passage", style: .default) { [weak self] _ in self?.speakSelection() })
        alert.addAction(UIAlertAction(title: "Pause", style: .default) { [weak self] _ in self?.speech.pauseSpeaking(at: .word) })
        alert.addAction(UIAlertAction(title: "Resume", style: .default) { [weak self] _ in self?.speech.continueSpeaking() })
        alert.addAction(UIAlertAction(title: "Stop", style: .destructive) { [weak self] _ in self?.speech.stopSpeaking(at: .immediate) })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel)); presentTool(alert, animated: true)
    }
    func showError(_ error: Error) {
        let alert = UIAlertController(title: "Unable to read", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default)); presentTool(alert, animated: true)
    }
}
struct ReaderList: View {
    var title: String; var labels: [String]; var select: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { List {
            if labels.isEmpty { Text("No entries found").foregroundStyle(.secondary) }
            ForEach(labels.indices, id: \.self) { index in Button(labels[index]) { select(index) } }
        }.navigationTitle(title).toolbar { Button("Done") { dismiss() } } }
    }
}
struct AnnotationList: View {
    var items: [Annotation]; var onSelect: (Annotation) -> Void; var onDelete: (Annotation) -> Void
    var onClose: () -> Void
    @State private var deleted = Set<UUID>()
    @State private var query = ""
    private var visible: [Annotation] {
        items.filter { !deleted.contains($0.id) && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || $0.note.localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        NavigationStack { List {
            ForEach(visible) { item in
                Button { onSelect(item) } label: {
                    VStack(alignment: .leading) { Text(item.text).lineLimit(4); if !item.note.isEmpty { Text(item.note).font(.caption).foregroundStyle(.secondary) } }
                }.swipeActions { Button("Delete", role: .destructive) { onDelete(item); deleted.insert(item.id) } }
            }
            if visible.isEmpty { Text(query.isEmpty ? "Save a bookmark or highlight to find it here." : "No passages or notes match your search.").foregroundStyle(.secondary) }
        }.navigationTitle("Annotations").searchable(text: $query, prompt: "Passage or note").toolbar { Button("Done") { onClose() } } }
    }
}
