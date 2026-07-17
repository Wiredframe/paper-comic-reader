//
//  SettingsView.swift
//  Comic Reader
//
//  The Settings tab: reader behaviour, the global paper effect, and a little
//  library info — laid out like the reference app's grouped sections.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var paper: PaperSettings
    @EnvironmentObject private var reader: ReaderSettings
    @Environment(\.modelContext) private var context
    @Query private var books: [ComicBook]

    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

    // Computed on appear rather than in `body`: `body` re-evaluates whenever the ComicBook
    // @Query republishes (every per-page-turn save while reading), and the size is a disk
    // walk over three folders — no need to repeat it on every render.
    @State private var storageText = "—"

    // The optional library folder (see LibrarySource). `folderName` mirrors the stored display
    // name so the row updates the moment a folder is chosen or removed; `scan` is non-nil while a
    // scan runs, driving the inline progress.
    @State private var folderName = LibrarySource.displayName
    @State private var showFolderPicker = false
    @State private var scan: (done: Int, total: Int)?
    #if DEBUG
    @State private var showPaperForShot = false   // screenshot deep-link to the Paper Effect detail
    #endif

    private let repoURL = URL(string: "https://github.com/Wiredframe/paper-comic-reader")!
    private let issuesURL = URL(string: "https://github.com/Wiredframe/paper-comic-reader/issues")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Double Page (Landscape)", isOn: $reader.doublePage)
                    Toggle("Page Shadow", isOn: $reader.pageShadow)
                    Toggle("Tap to Navigate", isOn: $reader.tapToNavigate)
                    Toggle("Live Text", isOn: $reader.liveText)
                    Toggle("Fast Animations", isOn: $reader.fastAnimations)
                } header: {
                    Text("Reader")
                } footer: {
                    Text("Double Page shows two pages side by side in landscape (cover alone, then pairs). Page Shadow rests the page on its background with a soft shadow, wherever the page doesn't reach the screen edge; a double page casts one shadow around the pair, never down the middle. Tap to Navigate lets you tap the left/right edges to move through the page half a screen at a time and turn pages; you can still swipe to turn pages. Live Text lets you select text on a page by pressing and holding.")
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
                    LabeledContent("Storage", value: storageText)
                    Button("Clear Cache") {
                        Storage.clearCaches()
                        ImageCache.clear()
                        storageText = storageDescription
                    }
                }

                Section {
                    if let folderName {
                        LabeledContent("Folder", value: folderName)
                        if let scan {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Scanning \(scan.done) of \(scan.total)…")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        } else {
                            Button { startScan() } label: {
                                Label("Scan for New Comics", systemImage: "arrow.clockwise")
                            }
                            Button { showFolderPicker = true } label: {
                                Label("Change Folder…", systemImage: "folder")
                            }
                            Button(role: .destructive) { removeFolder() } label: {
                                Label("Remove Folder", systemImage: "folder.badge.minus")
                            }
                        }
                    } else {
                        Button { showFolderPicker = true } label: {
                            Label("Choose Comic Folder…", systemImage: "folder.badge.plus")
                        }
                    }
                } header: {
                    Text("Comic Folder")
                } footer: {
                    Text("Import every comic in a folder on a file server or iCloud Drive — anything the Files app can reach. Covers and details come in now; each comic downloads when you open it, and its download can be removed again to save space while the entry stays. Scan again to pick up new comics. A file server has to be reachable (on the right network) when you open or download a comic.")
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
            #if DEBUG
            // Screenshot deep-link: SCREENSHOT_SETTINGS=paper pushes the Paper Effect detail on
            // launch, so its live preview + sliders can be captured without a tap.
            .navigationDestination(isPresented: $showPaperForShot) {
                PaperSettingsView(settings: paper)
            }
            .onAppear { if ScreenshotSupport.settingsScreen == "paper" { showPaperForShot = true } }
            #endif
            .task { storageText = storageDescription }
            .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
                handleFolderChosen(result)
            }
        }
    }

    // MARK: Comic folder

    private func handleFolderChosen(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        do { try LibrarySource.setFolder(url) } catch { return }
        folderName = LibrarySource.displayName
        startScan()
    }

    private func removeFolder() {
        LibrarySource.clear()
        folderName = nil
    }

    /// Scans the folder for comics not yet imported. Existing entries are matched by relative path,
    /// so a rescan only brings in what's new. Progress drives the inline row; the storage figure is
    /// refreshed at the end because the scan writes a cover per new comic.
    private func startScan() {
        guard scan == nil else { return }
        let existing = Set(books.compactMap { $0.sourceRelativePath })
        scan = (0, 0)
        Task {
            _ = try? await Importer.scanFolder(existing: existing, into: context) { done, total in
                scan = (done, total)
            }
            scan = nil
            storageText = storageDescription
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
