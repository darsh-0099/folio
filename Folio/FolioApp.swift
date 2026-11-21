import SwiftUI
import SwiftData

@main @MainActor struct FolioApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage("appAppearance") var appearance = "system"
    private let storage: Result<ModelContainer, Error>
    init() {
        storage = Result { try ModelContainer(for: LibraryBook.self, Annotation.self, ReadingDay.self) }
        if case .success(let container) = storage { DownloadManager.shared.configure(container.mainContext) }
    }
    var body: some Scene {
        WindowGroup {
            switch storage {
            case .success(let container):
                RootView().modelContainer(container).tint(Color("AccentColor"))
                    .preferredColorScheme(appearance == "system" ? nil : (appearance == "dark" ? .dark : .light))
            case .failure(let error):
                ContentUnavailableView("Library unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text("Folio could not open its library: \(error.localizedDescription). Free storage if needed and relaunch the app."))
            }
        }
    }
}
struct RootView: View {
    @Environment(\.modelContext) var context
    var body: some View {
        TabView {
            CatalogView(discover: true).tabItem { Label("Discover", systemImage: "sparkles") }
            CatalogView().tabItem { Label("Search", systemImage: "magnifyingglass") }
            LibraryView().tabItem { Label("Library", systemImage: "books.vertical") }
            ActivityView().tabItem { Label("Activity", systemImage: "chart.bar") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }.task { DownloadManager.shared.configure(context) }
    }
}
