import SwiftUI
import SwiftData

@main struct FolioApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage("appAppearance") var appearance = "system"
    var body: some Scene {
        WindowGroup {
            RootView().tint(Color(red: 0.19, green: 0.38, blue: 0.34))
                .preferredColorScheme(appearance == "system" ? nil : (appearance == "dark" ? .dark : .light))
        }.modelContainer(for: [LibraryBook.self, Annotation.self, ReadingDay.self])
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
