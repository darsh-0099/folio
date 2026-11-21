import SwiftUI
import ReadiumNavigator

@MainActor enum ReaderSettings {
    static var preferences: EPUBPreferences {
        let d = UserDefaults.standard
        let font: FontFamily = d.string(forKey: "readerFont") == "Sans" ? .sansSerif : .serif
        return EPUBPreferences(fontFamily: font, fontSize: d.object(forKey: "readerSize") as? Double ?? 110,
                               lineHeight: d.object(forKey: "readerLine") as? Double ?? 1.5,
                               pageMargins: d.object(forKey: "readerMargin") as? Double ?? 1,
                               publisherStyles: false, scroll: d.bool(forKey: "readerScroll"),
                               theme: d.string(forKey: "readerTheme") == "dark" ? .dark : (d.string(forKey: "readerTheme") == "sepia" ? .sepia : .light))
    }
}
struct ReaderAppearance: View {
    @AppStorage("readerSize") var size = 110.0
    @AppStorage("readerLine") var line = 1.5
    @AppStorage("readerMargin") var margin = 1.0
    @AppStorage("readerFont") var font = "Serif"
    @AppStorage("readerTheme") var theme = "light"
    @AppStorage("readerScroll") var scroll = false
    @State private var reset = false
    var changed: () -> Void = {}
    var body: some View {
        Form {
            Section("Text") {
                Picker("Font family", selection: $font) { Text("Serif").tag("Serif"); Text("Sans serif").tag("Sans") }
                LabeledContent("Font size", value: "\(Int(size))%")
                Slider(value: $size, in: 70...220, step: 10).accessibilityLabel("Font size")
                LabeledContent("Line spacing", value: line.formatted(.number.precision(.fractionLength(1))))
                Slider(value: $line, in: 1...2.5, step: 0.1).accessibilityLabel("Line spacing")
                Text("Margins"); Slider(value: $margin, in: 0.3...2.0, step: 0.1).accessibilityLabel("Margins")
            }
            Section("Page") {
                Picker("Theme", selection: $theme) { Text("Light").tag("light"); Text("Sepia").tag("sepia"); Text("Dark").tag("dark") }
                Toggle("Continuous scrolling", isOn: $scroll)
            }
            Section { Button("Reset reader preferences", role: .destructive) { reset = true } }
        }.confirmationDialog("Reset reader appearance?", isPresented: $reset, titleVisibility: .visible) {
            Button("Reset preferences", role: .destructive) {
                size = 110; line = 1.5; margin = 1; font = "Serif"; theme = "light"; scroll = false
                changed()
            }
        }.onChange(of: size) { changed() }.onChange(of: line) { changed() }.onChange(of: margin) { changed() }
            .onChange(of: font) { changed() }.onChange(of: theme) { changed() }.onChange(of: scroll) { changed() }
    }
}

struct ReaderAppearanceSheet: View {
    var changed: () -> Void
    var close: () -> Void
    var body: some View {
        NavigationStack {
            ReaderAppearance(changed: changed).navigationTitle("Reader appearance")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close).accessibilityIdentifier("appearance.done") } }
        }
    }
}
