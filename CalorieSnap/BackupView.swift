import SwiftUI
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────────────────────
// Backup & Restore — saves everything the app stores (meals, weights, finance,
// stocks, calendar, to-dos, wishes, fridge, recipes…) into one file you can keep
// in OneDrive, iCloud Drive or any other folder in the Files app.
//
// • Back up now: pick where to save the file.
// • Automatic backup: pick a folder once; a fresh backup is saved there each day
//   (the last 14 daily files are kept, plus "KellyLife-Latest-Backup.plist").
// • Restore: pick a backup file to put everything back.
//
// Apple Health and Oura data aren't included because they come back from those
// apps by themselves. Main app target only.
// ─────────────────────────────────────────────────────────────────────────────

enum KellyBackup {
    static let groupID = "group.com.kelly.kellylife"
    static let latestFileName = "KellyLife-Latest-Backup.plist"
    private static let folderBookmarkKey = "backup.folderBookmark"
    private static let fileBookmarkKey = "backup.fileBookmark"      // OneDrive: one file updated daily
    private static let lastAutoBackupKey = "backup.lastAutoBackup"
    private static let lastBackupKey = "backup.lastBackup"
    private static let lastBackupPlaceKey = "backup.lastBackupPlace"
    private static let keepDays = 14

    /// Keys never copied into or out of a backup (sign-in state, backup settings, system keys).
    private static func shouldSkip(_ key: String) -> Bool {
        let prefixes = ["Apple", "NS", "com.apple", "AK", "PK", "WebKit", "INNext", "backup.", "oura.tokenExpiry"]
        return prefixes.contains { key.hasPrefix($0) }
    }

    private static func appDomain() -> [String: Any] {
        guard let id = Bundle.main.bundleIdentifier,
              let domain = UserDefaults.standard.persistentDomain(forName: id) else { return [:] }
        return domain.filter { !shouldSkip($0.key) }
    }

    private static func groupDomain() -> [String: Any] {
        let all = UserDefaults.standard.persistentDomain(forName: groupID)
            ?? UserDefaults(suiteName: groupID)?.dictionaryRepresentation()
            ?? [:]
        return all.filter { !shouldSkip($0.key) }
    }

    // MARK: Make / restore

    static func makeBackupData() throws -> Data {
        let root: [String: Any] = [
            "app": "Kelly Life",
            "version": 1,
            "createdAt": Date(),
            "standard": appDomain(),
            "group": groupDomain(),
        ]
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    struct Summary {
        let createdAt: Date?
        let itemCount: Int
    }

    static func summary(of data: Data) -> Summary? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              root["app"] as? String == "Kelly Life" else { return nil }
        let count = (root["standard"] as? [String: Any])?.count ?? 0
        return Summary(createdAt: root["createdAt"] as? Date, itemCount: count)
    }

    /// Writes every saved value back. Returns how many items were restored.
    @discardableResult
    static func restore(from data: Data) throws -> Int {
        guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              root["app"] as? String == "Kelly Life" else {
            throw BackupError.notABackup
        }
        var restored = 0
        if let standard = root["standard"] as? [String: Any] {
            for (key, value) in standard where !shouldSkip(key) {
                UserDefaults.standard.set(value, forKey: key); restored += 1
            }
        }
        if let group = root["group"] as? [String: Any], let defaults = UserDefaults(suiteName: groupID) {
            for (key, value) in group where !shouldSkip(key) {
                defaults.set(value, forKey: key); restored += 1
            }
        }
        return restored
    }

    enum BackupError: LocalizedError {
        case notABackup, noFolder, folderUnavailable
        var errorDescription: String? {
            switch self {
            case .notABackup: return "That file isn't a Kelly Life backup."
            case .noFolder: return "Choose a backup folder first."
            case .folderUnavailable: return "The backup folder or file can't be opened. Choose it again (OneDrive may need you to open and unlock its app first)."
            }
        }
    }

    static func fileName(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "KellyLife-Backup-\(f.string(from: date)).plist"
    }

    // MARK: Automatic backup folder

    static var hasFolder: Bool { UserDefaults.standard.data(forKey: folderBookmarkKey) != nil }
    static var hasFile: Bool { UserDefaults.standard.data(forKey: fileBookmarkKey) != nil }
    /// True when automatic backup is on (to a folder or to a linked file).
    static var hasTarget: Bool { hasFolder || hasFile }
    static var lastAutoBackup: Date? { UserDefaults.standard.object(forKey: lastAutoBackupKey) as? Date }

    /// Any backup — manual or automatic.
    static var lastBackup: Date? { UserDefaults.standard.object(forKey: lastBackupKey) as? Date }
    static var lastBackupPlace: String? { UserDefaults.standard.string(forKey: lastBackupPlaceKey) }

    static func recordBackup(place: String) {
        UserDefaults.standard.set(Date(), forKey: lastBackupKey)
        UserDefaults.standard.set(place, forKey: lastBackupPlaceKey)
    }

    /// Name of the folder or linked file used for automatic backup.
    static var targetName: String? {
        if hasFile { return resolve(fileBookmarkKey)?.lastPathComponent }
        return resolve(folderBookmarkKey)?.lastPathComponent
    }

    static func setFolder(_ url: URL) throws {
        try saveBookmark(for: url, key: folderBookmarkKey)
        UserDefaults.standard.removeObject(forKey: fileBookmarkKey)
    }

    /// Links an existing backup file (e.g. one saved to OneDrive with "Back up now").
    /// Automatic backup then overwrites this file each day. OneDrive keeps older versions.
    static func setFile(_ url: URL) throws {
        try saveBookmark(for: url, key: fileBookmarkKey)
        UserDefaults.standard.removeObject(forKey: folderBookmarkKey)
    }

    static func clearTarget() {
        UserDefaults.standard.removeObject(forKey: folderBookmarkKey)
        UserDefaults.standard.removeObject(forKey: fileBookmarkKey)
        UserDefaults.standard.removeObject(forKey: lastAutoBackupKey)
    }

    private static func saveBookmark(for url: URL, key: String) throws {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: key)
    }

    private static func resolve(_ key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: key)
        }
        return url
    }

    /// Backs up to whichever target is set (linked file or folder).
    static func backupToTarget() throws {
        if hasFile { try backupToFile() } else { try backupToFolder() }
    }

    /// Overwrites the linked backup file in place.
    static func backupToFile() throws {
        guard let file = resolve(fileBookmarkKey) else { throw BackupError.folderUnavailable }
        let ok = file.startAccessingSecurityScopedResource()
        defer { if ok { file.stopAccessingSecurityScopedResource() } }

        let data = try makeBackupData()
        var writeError: Error?
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordError) { url in
            do { try data.write(to: url) } catch { writeError = error }
        }
        if let e = coordError ?? writeError { throw e }
        UserDefaults.standard.set(Date(), forKey: lastAutoBackupKey)
        recordBackup(place: file.lastPathComponent)
    }

    /// Saves today's backup into the chosen folder now.
    static func backupToFolder() throws {
        guard hasFolder else { throw BackupError.noFolder }
        guard let folder = resolve(folderBookmarkKey) else { throw BackupError.folderUnavailable }
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }

        let data = try makeBackupData()
        var writeError: Error?
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: folder, options: [], error: &coordError) { dir in
            do {
                try data.write(to: dir.appendingPathComponent(latestFileName), options: .atomic)
                try data.write(to: dir.appendingPathComponent(fileName()), options: .atomic)
                pruneOldBackups(in: dir)
            } catch {
                writeError = error
            }
        }
        if let e = coordError ?? writeError { throw e }
        UserDefaults.standard.set(Date(), forKey: lastAutoBackupKey)
        recordBackup(place: folder.lastPathComponent)
    }

    /// Call when the app opens or goes to the background: backs up once a day if a folder is set.
    static func autoBackupIfNeeded() {
        guard hasTarget else { return }
        if let last = lastAutoBackup, Calendar.current.isDateInToday(last) { return }
        try? backupToTarget()
    }

    private static func pruneOldBackups(in dir: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        let dated = files
            .filter { $0.lastPathComponent.hasPrefix("KellyLife-Backup-") && $0.pathExtension == "plist" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }      // newest first (yyyy-MM-dd sorts)
        for old in dated.dropFirst(keepDays) { try? fm.removeItem(at: old) }
    }
}

// MARK: - File wrapper for the "Save to Files" sheet

struct KellyBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.propertyList] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Screen

struct BackupView: View {
    @State private var exportDoc: KellyBackupDocument?
    @State private var showExporter = false
    private enum PickerMode { case folder, linkFile, restore }
    @State private var pickerMode: PickerMode = .folder
    @State private var showPicker = false
    @State private var pendingRestore: Data?
    @State private var pendingSummary: KellyBackup.Summary?
    @State private var message: String?
    @State private var isError = false
    @State private var showRestartNotice = false
    @State private var refresh = 0          // re-reads folder status after changes

    var body: some View {
        Form {
            Section {
                let _ = refresh
                LabeledContent("Last backup") {
                    if let last = KellyBackup.lastBackup {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(last.formatted(.relative(presentation: .named))).fontWeight(.semibold)
                            if let place = KellyBackup.lastBackupPlace {
                                Text("in \(place)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Never").foregroundStyle(.red)
                    }
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(isError ? .red : .green)
                }
            }

            Section {
                Button {
                    do {
                        exportDoc = KellyBackupDocument(data: try KellyBackup.makeBackupData())
                        showExporter = true
                    } catch { show(error) }
                } label: {
                    Label("Back up now", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Save a backup")
            } footer: {
                Text("In the save screen, tap Browse, choose OneDrive (or iCloud Drive) under Locations, pick a folder, and tap Save.")
            }

            Section {
                let _ = refresh
                if KellyBackup.hasTarget {
                    LabeledContent(KellyBackup.hasFile ? "File" : "Folder", value: KellyBackup.targetName ?? "Unavailable")
                    Button {
                        do { try KellyBackup.backupToTarget(); message = "Backed up to \(KellyBackup.targetName ?? "your backup")."; isError = false }
                        catch { show(error) }
                        refresh += 1
                    } label: {
                        Label("Back up there now", systemImage: "arrow.clockwise.icloud")
                    }
                    Button("Change where to back up") { KellyBackup.clearTarget(); refresh += 1 }
                    Button("Turn off automatic backup", role: .destructive) {
                        KellyBackup.clearTarget(); refresh += 1
                    }
                } else {
                    Button {
                        pickerMode = .linkFile; showPicker = true
                    } label: {
                        Label("OneDrive: use a backup file", systemImage: "doc.badge.clock")
                    }
                    Button {
                        pickerMode = .folder; showPicker = true
                    } label: {
                        Label("iCloud Drive: choose a folder", systemImage: "folder.badge.plus")
                    }
                }
            } header: {
                Text("Automatic daily backup")
            } footer: {
                Text(KellyBackup.hasTarget
                     ? "Each day you open the app, it backs up automatically."
                     : "OneDrive doesn't let apps keep a folder, so first save a backup there with Back up now, then pick that file here. The app updates it every day, and OneDrive keeps older versions (in OneDrive, open the file's menu → Version history). With iCloud Drive you can pick a folder instead; the app keeps 14 daily files there.")
            }

            Section {
                Button {
                    pickerMode = .restore; showPicker = true
                } label: {
                    Label("Restore from a backup", systemImage: "clock.arrow.circlepath")
                }
            } header: {
                Text("Restore")
            } footer: {
                Text("Restoring replaces what's on this iPhone with the backup. Pick \"\(KellyBackup.latestFileName)\" for the newest automatic backup.")
            }

            Section("What's included") {
                Label("Meals, calories, weight logs and profile", systemImage: "fork.knife")
                Label("Finance, budgets, stocks and CDs", systemImage: "dollarsign.circle")
                Label("Calendar, countdowns, to-dos, wishes and achievements", systemImage: "calendar")
                Label("Fridge items and saved recipes with photos", systemImage: "refrigerator")
                Text("Apple Health and Oura data aren't included because they reload from those apps. After restoring on a new install, reconnect Oura from the Energy page.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

        }
        .navigationTitle("Backup & Restore")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $showExporter, document: exportDoc, contentType: .propertyList,
                      defaultFilename: KellyBackup.fileName()) { result in
            switch result {
            case .success(let url):
                let folder = url.deletingLastPathComponent().lastPathComponent
                KellyBackup.recordBackup(place: folder)
                message = "Saved \(url.lastPathComponent) in \(folder)."; isError = false
                refresh += 1
            case .failure(let error): show(error)
            }
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: pickerMode == .folder ? [.folder] : [.propertyList, .data]
        ) { result in
            switch pickerMode {
            case .folder:
                do {
                    try KellyBackup.setFolder(try result.get())
                    try KellyBackup.backupToFolder()
                    message = "Automatic backup is on. First backup saved."; isError = false
                } catch { show(error) }
                refresh += 1
            case .linkFile:
                do {
                    let url = try result.get()
                    let ok = url.startAccessingSecurityScopedResource()
                    let data = try? Data(contentsOf: url)
                    if ok { url.stopAccessingSecurityScopedResource() }
                    guard let data, KellyBackup.summary(of: data) != nil else { throw KellyBackup.BackupError.notABackup }
                    try KellyBackup.setFile(url)
                    try KellyBackup.backupToFile()
                    message = "Automatic backup is on. \(url.lastPathComponent) was just updated."; isError = false
                } catch { show(error) }
                refresh += 1
            case .restore:
                do {
                    let url = try result.get()
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    guard let summary = KellyBackup.summary(of: data) else { throw KellyBackup.BackupError.notABackup }
                    pendingSummary = summary
                    pendingRestore = data
                } catch { show(error) }
            }
        }
        .confirmationDialog(
            "Replace this iPhone's data with the backup?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                guard let data = pendingRestore else { return }
                do {
                    let n = try KellyBackup.restore(from: data)
                    message = "Restored \(n) items."; isError = false
                    showRestartNotice = true
                } catch { show(error) }
                pendingRestore = nil
            }
        } message: {
            if let s = pendingSummary, let d = s.createdAt {
                Text("Backup from \(d.formatted(date: .abbreviated, time: .shortened)).")
            }
        }
        .alert("Restore complete", isPresented: $showRestartNotice) {
            // Close right away so nothing still in memory can overwrite the restored data.
            Button("Close app") { exit(0) }
        } message: {
            Text("Kelly Life will close now. Open it again to see your restored data.")
        }
    }

    private func show(_ error: Error) {
        message = error.localizedDescription
        isError = true
    }
}
