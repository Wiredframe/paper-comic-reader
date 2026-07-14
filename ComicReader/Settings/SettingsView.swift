//
//  SettingsView.swift
//  Comic Reader
//
//  The Settings tab: reader behaviour, the global paper effect, and a little
//  library info — laid out like the reference app's grouped sections.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var paper: PaperSettings
    @EnvironmentObject private var reader: ReaderSettings
    @Query private var books: [ComicBook]

    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.dark.rawValue

    private let repoURL = URL(string: "https://github.com/Wiredframe/paper-comic-reader")!
    private let issuesURL = URL(string: "https://github.com/Wiredframe/paper-comic-reader/issues")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Double Page (Landscape)", isOn: $reader.doublePage)
                    Toggle("Tap to Navigate", isOn: $reader.tapToNavigate)
                    Toggle("Live Text", isOn: $reader.liveText)
                    Toggle("Fast Animations", isOn: $reader.fastAnimations)
                } header: {
                    Text("Reader")
                } footer: {
                    Text("Double Page shows two pages side by side in landscape (cover alone, then pairs). Tap to Navigate lets you tap the left/right edges to move through the page a third at a time and turn pages — off by default, so swipe to turn pages. Live Text lets you select text on a page by pressing and holding.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Fit-Width Zoom")
                            Spacer()
                            Text("\(Int((reader.doubleTapZoom * 100).rounded()))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $reader.doubleTapZoom, in: 0.7...1.0, step: 0.05)
                    }
                } header: {
                    Text("Zoom")
                } footer: {
                    Text("How wide a single page fills the screen — the default view and the double-tap zoom. Lower it if fit-width feels too wide or too zoomed-in; the page then sits centred with more of its height on screen.")
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearanceRaw) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.label).tag(appearance.rawValue)
                        }
                    }
                }

                Section("Paper Effect") {
                    Toggle("Paper Effect", isOn: $paper.isEnabled)
                    NavigationLink {
                        PaperSettingsView(settings: paper)
                    } label: {
                        Label("Adjust…", systemImage: "slider.horizontal.3")
                    }
                    .disabled(!paper.isEnabled)
                }

                Section("Library") {
                    LabeledContent("Comics", value: "\(books.count)")
                    LabeledContent("Storage", value: storageDescription)
                    Button("Clear Cache") { Storage.clearCaches() }
                }

                Section("Project") {
                    Link(destination: repoURL) {
                        Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: issuesURL) {
                        Label("Report an Issue", systemImage: "exclamationmark.bubble")
                    }
                }

                Section("About") {
                    NavigationLink {
                        LegalTextView(title: "Terms of Use", body_: Legal.terms)
                    } label: { Label("Terms of Use", systemImage: "doc.text") }
                    NavigationLink {
                        LegalTextView(title: "Privacy Policy", body_: Legal.privacy)
                    } label: { Label("Privacy Policy", systemImage: "hand.raised") }
                    NavigationLink {
                        LegalTextView(title: "License", body_: Legal.license)
                    } label: { Label("License", systemImage: "checkmark.seal") }
                    NavigationLink {
                        LegalTextView(title: "Acknowledgements", body_: Legal.acknowledgements)
                    } label: { Label("Acknowledgements", systemImage: "text.book.closed") }
                }

                Section {
                } footer: {
                    Text(appVersion)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Paper Comic Reader \(version) (\(build))"
    }

    private var storageDescription: String {
        let bytes = folderSize(Storage.comics) + folderSize(Storage.covers) + folderSize(Storage.bookmarkThumbs)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func folderSize(_ url: URL) -> Int64 {
        guard let items = try? Storage.fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return items.reduce(0) { sum, item in
            let size = (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
    }
}
