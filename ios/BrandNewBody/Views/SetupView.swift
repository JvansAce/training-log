import SwiftUI
import UniformTypeIdentifiers

struct SetupView: View {
    @Environment(AppStore.self) private var store
    @Environment(WhoopClient.self) private var whoop

    @State private var exportDocument: BackupDocument? = nil
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var confirmDelete = false
    @State private var message: String? = nil
    @State private var startDate = Date()

    private var state: LogState { store.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            iCloudPanel
            whoopPanel
            backupPanel
            youPanel
            startDatePanel
            dangerZone
        }
        .onAppear {
            startDate = DateKit.date(state.startDate) ?? Date()
        }
        .fileExporter(isPresented: $showExporter,
                      document: exportDocument,
                      contentType: .json,
                      defaultFilename: "brand-new-body-\(state.today)") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .alert("Delete all data?", isPresented: $confirmDelete) {
            Button("Delete everything", role: .destructive) { store.deleteAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("""
                Every weigh-in, session tick and logged set, on this device and on every other device \
                signed into the same iCloud account. There is no undo. Export first if that matters.
                """)
        }
    }

    // MARK: iCloud

    private var iCloudPanel: some View {
        Panel(title: "iCloud", tag: store.cloudStatus == .syncing ? "syncing" : "local only") {
            switch store.cloudStatus {
            case .syncing:
                Note("""
                    Your log lives on this device and is mirrored to your private iCloud database. Every \
                    device signed into the same Apple Account reads and writes the same records, and the \
                    whole thing is included in your iCloud backup. Nothing is sent anywhere else — there \
                    is no server in this app and no account to create.
                    """)
                Note("""
                    Entries merge rather than overwrite, because each day, each lift and each practice is \
                    its own record: a set logged on your phone in the garage and a weigh-in typed on the \
                    iPad upstairs touch different records and both survive. Deletions propagate properly \
                    too. It syncs in the background — expect a few seconds, not instant, and it catches up \
                    on its own after a spell with no signal.
                    """)
            case .localOnly(let reason):
                Note("""
                    This copy is not syncing. Everything still works and is saved on this device, but it is \
                    not being mirrored to iCloud and is not in your iCloud backup — so export a file \
                    occasionally until it is fixed.
                    """)
                Note("Reason given: \(reason)", dimmed: true)
                Note("""
                    The usual causes are no Apple Account signed in on the device, iCloud Drive switched \
                    off for this app in Settings, or a build without the iCloud capability.
                    """)
            }
        }
    }

    // MARK: WHOOP

    private var whoopPanel: some View {
        Panel(title: "WHOOP", tag: whoopTag) {
            switch whoop.status {
            case .checking:
                Note("Checking connection status.")
            case .notConnected(let reason):
                if !WhoopConfig.isConfigured {
                    Note("""
                        WhoopConfig.swift still has its placeholder values — see ios/README.md for what to \
                        fill in before this will do anything.
                        """, dimmed: true)
                } else {
                    Note("""
                        Connect WHOOP to see today's recovery, strain and sleep on the Today page — \
                        including a flag on days recovery is low.\(reason != nil ? " " + reason! : "")
                        """)
                    ActionButton(title: "Connect WHOOP", prominent: true) { whoop.connect() }
                }
            case .connected:
                if let asOf = whoop.today?.asOf {
                    Note("Last read: \(asOf.formatted(date: .omitted, time: .shortened)).")
                } else {
                    Note("Connected — no scored recovery yet today.")
                }
                HStack {
                    ActionButton(title: "Refresh now") {
                        Task {
                            await whoop.fetchToday(dayKey: state.today)
                            if let reading = whoop.today?.recovery {
                                store.applyWhoopReading(reading, on: state.today)
                            }
                        }
                    }
                    ActionButton(title: "Disconnect", destructive: true) { whoop.disconnect() }
                }
            }
        }
    }

    private var whoopTag: String {
        switch whoop.status {
        case .checking: return "checking…"
        case .notConnected: return "not connected"
        case .connected: return "connected"
        }
    }

    // MARK: Backup

    private var backupPanel: some View {
        Panel(title: "Backup", tag: "a copy you own") {
            Note("""
                iCloud carries the log between your own devices. This is for everything else — moving to \
                another phone, keeping a copy outside Apple's estate, or undoing a bad afternoon with the \
                delete button, which no amount of syncing protects you from.
                """)
            HStack {
                ActionButton(title: "Export file", prominent: true) {
                    if let data = try? store.exportData() {
                        exportDocument = BackupDocument(data: data)
                        showExporter = true
                    } else {
                        message = "Could not build the backup file."
                    }
                }
                ActionButton(title: "Import file") { showImporter = true }
            }
            Note("""
                JSON is the one to keep for restoring, and importing replaces everything rather than \
                merging. CSV is for poking at the numbers in a spreadsheet — it cannot be imported back.
                """)
            HStack {
                ShareLink(item: store.weightsCSV()) { csvLabel("Weigh-ins CSV") }
                ShareLink(item: store.liftsCSV()) { csvLabel("Lifts CSV") }
            }
            if let message {
                Note(message, dimmed: true)
            }
        }
    }

    private func csvLabel(_ title: String) -> some View {
        Text(title)
            .font(Theme.body(13, weight: .semibold))
            .foregroundStyle(Theme.bone)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Theme.raise, in: RoundedRectangle(cornerRadius: 9))
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            // A file returned by the picker lives outside the app's sandbox
            // until this is granted, and reading without it fails with a
            // permissions error that reads like a corrupt file.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try store.importData(Data(contentsOf: url))
            message = "Backup restored."
        } catch {
            message = "That file could not be read as a Brand New Body backup."
        }
    }

    // MARK: You

    private var youPanel: some View {
        Panel(title: "You", tag: tagForYou) {
            Note("""
                Height turns a bodyweight into something you can judge — it drives the target band and \
                waist on Progress. Both together drive the calorie target, which is then calculated from \
                your current weight rather than fixed, so it keeps up as you gain instead of quietly \
                becoming a smaller surplus.
                """)
            HeightField(current: state.heightCm) { store.setHeight($0) }
            EntryField(placeholder: "year you were born",
                       buttonTitle: state.birthYear == nil ? "Set year" : "Update",
                       prominent: state.birthYear == nil,
                       keyboard: .numberPad) { text in
                guard let year = Int(text), let today = DateKit.date(state.today) else { return false }
                let thisYear = Calendar.current.component(.year, from: today)
                guard year >= thisYear - Build.maxAge, year <= thisYear - Build.minAge else { return false }
                store.setBirthYear(year)
                return true
            }
            Note("Set once. Year of birth rather than age so it doesn't go stale on your birthday.")
            EntryField(placeholder: "barbell weight, kg (default 20)",
                       buttonTitle: "Set bar", prominent: false) { text in
                guard let kg = Double(text.replacingOccurrences(of: ",", with: ".")),
                      kg > 0, kg <= 50 else { return false }
                store.setBarKg(kg)
                return true
            }
            Note("The bar the plate maths assumes. \(Lifts.fmt(state.barKg)) kg at the moment.")
        }
    }

    private var tagForYou: String {
        var parts: [String] = []
        if let cm = state.heightCm { parts.append("\(cm) cm") }
        if let age = Fuel.age(state) { parts.append("\(age)y") }
        return parts.isEmpty ? "not set" : parts.joined(separator: " · ")
    }

    // MARK: Start date

    private var startDatePanel: some View {
        Panel(title: "Start date", tag: "week counter") {
            Note("""
                Currently week \(state.weeksIn + 1). Set this to your real first training day — the add-ins \
                unlock at week \(Plan.addInWeek).
                """)
            DatePicker("First training day", selection: $startDate, in: ...Date(),
                       displayedComponents: .date)
                .font(Theme.body(13))
                .foregroundStyle(Theme.bone)
            ActionButton(title: "Save") { store.setStartDate(DateKit.key(startDate)) }
        }
    }

    // MARK: Danger zone

    private var dangerZone: some View {
        Panel(title: "Danger zone", tag: "no undo") {
            Note("""
                Deletes every weigh-in, session tick and logged set — and because the log is mirrored to \
                iCloud, it deletes them from your other devices too, as soon as they next sync.
                """)
            ActionButton(title: "Delete all data", prominent: true, destructive: true) {
                confirmDelete = true
            }
        }
    }
}

/// The exported backup, wrapped for `fileExporter`.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
