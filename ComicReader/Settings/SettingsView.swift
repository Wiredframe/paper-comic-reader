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
    @Environment(PaperSettings.self) private var paper
    @Environment(ReaderSettings.self) private var reader
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
    // ONE file importer for the whole screen, aimed by `pickerTarget`.
    //
    // Not two. Two `.fileImporter` modifiers leave only one of them working, and attaching the
    // second to a row inside the Form doesn't help: a row shares the Form's presentation context
    // rather than making a new one, so the outer one keeps winning and the other button silently
    // does nothing. Which button is broken then depends on the order the modifiers are applied,
    // which is a coin toss nobody should be spending debugging time on.
    @State private var pickerTarget = PickerTarget.comicFolder
    @State private var isPickerPresented = false
    @State private var scan: (done: Int, total: Int)?
    @State private var refresh: (done: Int, total: Int)?
    @State private var showRemoveFolderConfirm = false

    // Library backup. `backupFile` holds a finished export until it's shared; `backupProgress` is
    // non-nil while one is being written or read, driving the determinate row.
    @State private var backupFile: BackupFile?
    @State private var backupProgress: BackupProgress?
    @State private var backupMessage: String?
    #if DEBUG
    @State private var showPaperForShot = false   // screenshot deep-link to the Paper Effect detail
    #endif

    private let repoURL = URL(string: "https://github.com/Wiredframe/paper-comic-reader")!
    private let issuesURL = URL(string: "https://github.com/Wiredframe/paper-comic-reader/issues")!

    var body: some View {
        @Bindable var paper = paper
        @Bindable var reader = reader
        return NavigationStack {
            ScrollViewReader { proxy in
            Form {
                Section {
                    Toggle("Double Page (Landscape)", isOn: $reader.doublePage)
                    Toggle("Page Gap", isOn: $reader.pageGap)
                        .disabled(!reader.doublePage)
                    Toggle("Page Shadow", isOn: $reader.pageShadow)
                    Toggle("Tap to Navigate", isOn: $reader.tapToNavigate)
                    Toggle("Live Text", isOn: $reader.liveText)
                    Toggle("Fast Animations", isOn: $reader.fastAnimations)
                } header: {
                    Text("Reader")
                } footer: {
                    Text("Double Page shows two pages side by side in landscape (cover alone, then pairs). Page Gap leaves a thin line of the background between those two pages so they read as two sheets instead of one wide one; a page with no facing page is unaffected. Page Shadow rests the page on its background with a soft shadow, wherever the page doesn't reach the screen edge; without a gap a double page casts one shadow around the pair rather than down the middle, and with one each page casts its own. Tap to Navigate lets you tap the left/right edges to move through the page half a screen at a time and turn pages; you can still swipe to turn pages. Live Text lets you select text on a page by pressing and holding.")
                }

                Section {
                    // Its own view so dragging the slider re-renders just this row, not the whole
                    // Settings Form (which holds the library @Query). Under @Observable only the
                    // view that READS `doubleTapZoom` — the live "%" label here — is invalidated.
                    ZoomSettingRow(reader: reader)
                    Toggle("Align to Screen Edges", isOn: $reader.alignToEdges)
                } header: {
                    Text("Zoom")
                } footer: {
                    Text("How wide a single page fills the screen, for the default view and the double-tap zoom. Lower it if fit-width feels too wide or too zoomed-in; the page then shows more of its height. Align to Screen Edges decides where the spare width goes when you zoom into one page of a double page: off, that page sits centred with an even gap either side; on, the left page rests against the left edge and the right page against the right, so the spare width shows more of the facing page instead. At 100% there is no spare width, so it changes nothing.")
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
                        } else if let refresh {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Reading metadata \(refresh.done) of \(refresh.total)…")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        } else {
                            Button { startScan() } label: {
                                Label("Scan for New Comics", systemImage: "arrow.clockwise")
                            }
                            Button { startMetadataRefresh() } label: {
                                Label("Re-read Metadata", systemImage: "arrow.triangle.2.circlepath")
                            }
                            Button { present(.comicFolder) } label: {
                                Label("Change Folder…", systemImage: "folder")
                            }
                            Button(role: .destructive) { showRemoveFolderConfirm = true } label: {
                                Label("Remove Folder", systemImage: "folder.badge.minus")
                            }
                        }
                    } else {
                        Button { present(.comicFolder) } label: {
                            Label("Choose Comic Folder…", systemImage: "folder.badge.plus")
                        }
                    }
                } header: {
                    Text("Comic Folder")
                } footer: {
                    Text("Import every comic in a folder on a file server or iCloud Drive, anything the Files app can reach. Covers and details come in now; each comic downloads when you open it, and its download can be removed again to save space while the entry stays. Scan again to pick up new comics, or re-read metadata to refresh titles and details from each comic's ComicInfo without touching your bookmarks or reading progress. A file server has to be reachable (on the right network) when you open, download, or re-read a comic.")
                }
                .id("comicFolder")   // screenshot scroll anchor (SCREENSHOT_SETTINGS=folder)

                Section {
                    if let backupProgress {
                        HStack(spacing: 10) {
                            ProgressView(value: Double(backupProgress.done),
                                         total: Double(max(backupProgress.total, 1)))
                                .frame(maxWidth: 120)
                            Text(backupProgress.label)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    } else {
                        // Two steps rather than one: building the file walks every cover, thumbnail
                        // and archive, so it can't happen inside a tap. A native ShareLink anchored
                        // to its own row is also what makes the share popover behave on iPad.
                        //
                        // The Export row stays put once a backup is ready, rather than being
                        // replaced by the share: otherwise there is no way back to making a fresh
                        // one without leaving Settings, and a backup that silently ages is worse
                        // than one extra row.
                        if let backupFile {
                            ShareLink(item: backupFile.url) {
                                Label("Share Backup", systemImage: "square.and.arrow.up")
                            }
                        }
                        Button { startBackupExport() } label: {
                            Label(backupFile == nil ? "Export Library…" : "Export Again…",
                                  systemImage: backupFile == nil ? "square.and.arrow.up" : "arrow.clockwise")
                        }
                        Button { present(.libraryBackup) } label: {
                            Label("Import Library…", systemImage: "square.and.arrow.down")
                        }
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Export writes your whole library to a single file: every comic's details, reading progress, bookmarks, favorites and covers, plus the CBZ files of comics you imported by hand, since those have no other source. Comics that come from your comic folder travel as references and fetch themselves on the other device, so a large folder library still exports as a small file.\n\nImporting adds comics that are missing and overwrites the reading progress of ones already here with what the backup holds. Bookmarks are only ever added, never removed, so restoring an older backup can't cost you one.")
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
            // Screenshot scene control (SCREENSHOT_SETTINGS): deep-link the Paper Effect detail,
            // or scroll the Comic Folder section into view — captured without a tap or scroll.
            .navigationDestination(isPresented: $showPaperForShot) {
                PaperSettingsView(settings: paper)
            }
            .onAppear { applyScreenshotScene(proxy) }
            #endif
            .task { storageText = storageDescription }
            .fileImporter(isPresented: $isPickerPresented,
                          allowedContentTypes: pickerTarget.contentTypes) { result in
                switch pickerTarget {
                case .comicFolder:  handleFolderChosen(result)
                case .libraryBackup: handleBackupChosen(result)
                }
            }
            .confirmationDialog("Remove this comic folder?",
                                isPresented: $showRemoveFolderConfirm,
                                titleVisibility: .visible) {
                Button("Remove Folder", role: .destructive) { removeFolder() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This unlinks the folder from this device. Your imported comics, covers, reading progress, and bookmarks stay. Comics that live only in the folder and aren't downloaded can't be opened until you choose the folder again.")
            }
            .alert("Library Backup", isPresented: backupAlertBinding) {
                Button("OK") { backupMessage = nil }
            } message: {
                if let backupMessage { Text(backupMessage) }
            }
            }
        }
    }

    #if DEBUG
    /// Settings-tab screenshot scenes (SCREENSHOT_SETTINGS): push the Paper Effect detail, or
    /// scroll the Comic Folder section to the top. The scroll waits a runloop tick so the Form
    /// has laid out its rows first.
    private func applyScreenshotScene(_ proxy: ScrollViewProxy) {
        switch ScreenshotSupport.settingsScreen {
        case "paper":  showPaperForShot = true
        case "folder": DispatchQueue.main.async { proxy.scrollTo("comicFolder", anchor: .top) }
        default:       break
        }
    }
    #endif

    // MARK: The file picker

    /// Aims the single importer and then presents it, one runloop turn apart.
    ///
    /// The two steps are the point. `allowedContentTypes` is read from `pickerTarget`, so flipping
    /// both in the same update would race: SwiftUI could build the importer with the OLD target's
    /// types and then present it, offering folders when a backup file was wanted. Setting the target
    /// first lets the body rebuild with the right types, and the presentation follows.
    private func present(_ target: PickerTarget) {
        pickerTarget = target
        DispatchQueue.main.async { isPickerPresented = true }
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
        guard scan == nil, refresh == nil else { return }
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

    /// Re-reads ComicInfo metadata for every comic, refreshing titles and details in place.
    /// Folder-backed comics are read from the library folder (so an edited ComicInfo.xml is
    /// picked up); nothing is deleted and bookmarks and reading progress stay. See
    /// `Importer.refreshMetadata`.
    private func startMetadataRefresh() {
        guard scan == nil, refresh == nil else { return }
        refresh = (0, 0)
        Task {
            _ = await Importer.refreshMetadata(for: books, into: context) { done, total in
                refresh = (done, total)
            }
            refresh = nil
        }
    }

    // MARK: Library backup

    /// Builds the backup file. The document is captured here (SwiftData models can't leave the main
    /// actor); the packaging runs off it, because it copies every archive the library owns.
    private func startBackupExport() {
        guard backupProgress == nil else { return }
        let backup = LibraryBackupStore.capture(from: books)
        backupFile = nil
        backupProgress = BackupProgress(done: 0, total: 1, verb: "Exporting")
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<URL, Error> in
                do {
                    // Already throttled to once per percent by `write`, so this can hop straight to
                    // the main actor without flooding it.
                    let url = try LibraryBackupArchive.write(backup) { done, total in
                        Task { @MainActor in
                            backupProgress = BackupProgress(done: done, total: total,
                                                            verb: "Exporting")
                        }
                    }
                    return .success(url)
                } catch {
                    return .failure(error)
                }
            }.value
            backupProgress = nil
            switch result {
            case .success(let url):
                backupFile = BackupFile(url: url)
            case .failure(let error):
                backupMessage = message(for: error)
            }
        }
    }

    /// Unpacks off the main actor, then applies on it. The unpacked handle owns a temp directory, so
    /// it is discarded in every path out of here.
    private func handleBackupChosen(_ result: Result<URL, Error>) {
        guard case .success(let url) = result, backupProgress == nil else { return }
        backupProgress = BackupProgress(done: 0, total: 1, verb: "Importing")
        Task {
            let opened = await Task.detached(priority: .userInitiated) {
                Result { try LibraryBackupArchive.read(at: url) }
            }.value
            switch opened {
            case .failure(let error):
                backupProgress = nil
                backupMessage = message(for: error)
            case .success(let unpacked):
                // The bytes move off the main actor, the models are written on it. A backup carrying
                // a few hundred megabytes of comics would otherwise freeze the app for the length of
                // the copy, because SwiftData has to be written from here.
                await Task.detached(priority: .userInitiated) {
                    LibraryBackupStore.installFiles(from: unpacked)
                }.value
                let report = LibraryBackupStore.restore(unpacked, into: context)
                await Task.detached(priority: .utility) { unpacked.discard() }.value
                backupProgress = nil
                backupMessage = describe(report, from: unpacked.backup)
                storageText = storageDescription
            }
        }
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? LibraryBackupArchive.BackupError.unreadable.localizedDescription
    }

    /// Plain sentences rather than a row of counts. A restore is something the reader asked for
    /// once, and what they want back is what it did.
    private func describe(_ report: LibraryBackupStore.Report, from backup: LibraryBackup) -> String {
        let source = "Backup from \(backup.deviceName), \(backup.createdAt.formatted(date: .abbreviated, time: .shortened))."
        guard !report.isEmpty else {
            return "\(source) Everything in it was already here."
        }
        var parts: [String] = []
        if report.comicsAdded > 0 { parts.append("added \(comics(report.comicsAdded))") }
        if report.comicsUpdated > 0 { parts.append("updated \(comics(report.comicsUpdated))") }
        if report.bookmarksAdded > 0 {
            let n = report.bookmarksAdded
            parts.append("restored \(n) bookmark\(n == 1 ? "" : "s")")
        }
        var sentence = "\(source) Imported: " + parts.joined(separator: ", ") + "."
        if report.comicsWithoutArchive > 0 {
            let n = report.comicsWithoutArchive
            sentence += " \(comics(n)) came back without \(n == 1 ? "its file" : "their files") and can't be opened until you import \(n == 1 ? "it" : "them") again."
        }
        return sentence
    }

    private func comics(_ n: Int) -> String { "\(n) comic\(n == 1 ? "" : "s")" }

    private var backupAlertBinding: Binding<Bool> {
        Binding(get: { backupMessage != nil }, set: { if !$0 { backupMessage = nil } })
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

/// What the screen's one file importer is currently for. See `SettingsView.present(_:)` for why
/// there is only one.
private enum PickerTarget {
    case comicFolder
    case libraryBackup

    var contentTypes: [UTType] {
        switch self {
        case .comicFolder:   return [.folder]
        case .libraryBackup: return [.zip]
        }
    }
}

/// A finished export, waiting to be shared. `ShareLink` needs its item up front and this one
/// doesn't exist until the packaging has run, so the row swaps from a button to a share once it does.
private struct BackupFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// Determinate progress for an export or import. Determinate rather than a spinner because a
/// backup carrying archives takes long enough that "is it stuck?" becomes a real question.
private struct BackupProgress {
    var done: Int
    var total: Int
    var verb: String

    var label: String { "\(verb) \(done) of \(total)…" }
}

/// The Fit-Width Zoom row (label + live "%" + slider), split out of `SettingsView` so a drag
/// re-renders only this row. Because it — and not the parent Form — reads `doubleTapZoom`, the
/// fine-grained @Observable tracking keeps the surrounding Settings sections (and the library
/// @Query behind them) out of the slider's per-tick update.
private struct ZoomSettingRow: View {
    @Bindable var reader: ReaderSettings

    var body: some View {
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
    }
}
