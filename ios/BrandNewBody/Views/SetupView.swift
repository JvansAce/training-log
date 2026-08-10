import SwiftUI
import UniformTypeIdentifiers

/// A native `Form`, deliberately — this is the one screen in the app that is
/// unambiguously a settings screen, and a settings screen with grouped rows,
/// section footers and a destructive-role delete button IS what "looks
/// native" means on iOS. Every other page in this app carries its own
/// visual identity (the card panels, the charts); this one borrows the
/// system's, on purpose, the same way Settings.app does inside every
/// third-party app that links out to it.
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
        Form {
            iCloudSection
            whoopSection
            todayLayoutSection
            backupSection
            youSection
            startDateSection
            dangerZoneSection
        }
        .navigationTitle("Setup")
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

    private var iCloudSection: some View {
        Section {
            LabeledContent("Status", value: store.cloudStatus == .syncing ? "Syncing" : "Local only")
        } header: {
            Text("iCloud")
        } footer: {
            switch store.cloudStatus {
            case .syncing:
                Text("""
                    Mirrored to your private iCloud database. Every device signed into the same Apple \
                    Account reads and writes the same records, and the whole thing is included in your \
                    iCloud backup. Entries merge rather than overwrite — a set logged on your phone and a \
                    weigh-in typed on your iPad both survive, because each is its own record. Expect a few \
                    seconds, not instant, and it catches up on its own after a spell with no signal.
                    """)
            case .localOnly(let reason):
                Text("""
                    Not syncing. Everything still works and is saved on this device, but it isn't mirrored \
                    to iCloud or in your iCloud backup — export a file occasionally until this is fixed. \
                    Reason given: \(reason). The usual causes are no Apple Account signed in, iCloud Drive \
                    switched off for this app, or a build without the iCloud capability.
                    """)
            }
        }
    }

    // MARK: WHOOP

    private var whoopSection: some View {
        Section {
            switch whoop.status {
            case .checking:
                LabeledContent("Status", value: "Checking…")
            case .notConnected:
                LabeledContent("Status", value: "Not connected")
                if WhoopConfig.isConfigured {
                    Button("Connect WHOOP") { whoop.connect() }
                }
            case .connected:
                LabeledContent("Status", value: "Connected")
                if let asOf = whoop.today?.asOf {
                    LabeledContent("Last read", value: asOf.formatted(date: .omitted, time: .shortened))
                }
                Button("Refresh now") {
                    Task {
                        await whoop.fetchToday(dayKey: state.today)
                        if let reading = whoop.today?.recovery {
                            store.applyWhoopReading(reading, on: state.today)
                        }
                    }
                }
                Button("Disconnect", role: .destructive) { whoop.disconnect() }
            }
        } header: {
            Text("WHOOP")
        } footer: {
            switch whoop.status {
            case .checking:
                Text("Checking connection status.")
            case .notConnected(let reason):
                if !WhoopConfig.isConfigured {
                    Text("""
                        WhoopConfig.swift still has its placeholder values — see ios/README.md for what to \
                        fill in before this will do anything.
                        """)
                } else {
                    Text("Connect WHOOP to see today's recovery, strain and sleep on the Today page — including a flag on days recovery is low.\(reason != nil ? " " + reason! : "")")
                }
            case .connected:
                Text(whoop.today?.recovery.recovery == nil
                    ? "Connected — no scored recovery yet today."
                    : "Recovery, strain, sleep, HRV and resting heart rate are read automatically each time you open the app.")
            }
        }
    }

    // MARK: Today layout

    private var todayLayoutSection: some View {
        Section {
            NavigationLink("Reorder Today's sections") {
                TodaySectionOrderView()
            }
        } header: {
            Text("Today")
        } footer: {
            Text("""
                Move Vitals, the session, Fuel and Mobility into whatever order you actually use — \
                mobility first if that's your habit, fuel last if you never check it.
                """)
        }
    }

    // MARK: Backup

    private var backupSection: some View {
        Section {
            Button("Export file") {
                if let data = try? store.exportData() {
                    exportDocument = BackupDocument(data: data)
                    showExporter = true
                } else {
                    message = "Could not build the backup file."
                }
            }
            Button("Import file") { showImporter = true }
            ShareLink("Weigh-ins CSV", item: store.weightsCSV())
            ShareLink("Lifts CSV", item: store.liftsCSV())
        } header: {
            Text("Backup")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("""
                    iCloud carries the log between your own devices. This is for everything else — moving \
                    to another phone, keeping a copy outside Apple's estate, or undoing a bad afternoon \
                    with the delete button, which no amount of syncing protects you from. JSON is the one \
                    to keep for restoring — importing replaces everything rather than merging. CSV is for \
                    a spreadsheet and can't be imported back.
                    """)
                if let message {
                    Text(message).foregroundStyle(.red)
                }
            }
        }
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

    private var youSection: some View {
        Section {
            ValidatedRow(label: "Height (cm)", value: state.heightCm.map(String.init) ?? "",
                        keyboard: .numberPad) { text in
                guard let value = Int(text), value >= Build.minHeight, value <= Build.maxHeight else { return false }
                store.setHeight(value)
                return true
            }
            ValidatedRow(label: "Born", value: state.birthYear.map(String.init) ?? "",
                        keyboard: .numberPad) { text in
                guard let year = Int(text), let today = DateKit.date(state.today) else { return false }
                let thisYear = Calendar.current.component(.year, from: today)
                guard year >= thisYear - Build.maxAge, year <= thisYear - Build.minAge else { return false }
                store.setBirthYear(year)
                return true
            }
            ValidatedRow(label: "Barbell (kg)", value: Lifts.fmt(state.barKg)) { text in
                guard let kg = Double(text.replacingOccurrences(of: ",", with: ".")), kg > 0, kg <= 50 else { return false }
                store.setBarKg(kg)
                return true
            }
        } header: {
            Text("You")
        } footer: {
            Text("""
                Height and year of birth drive the target band and waist on Progress, and the calorie \
                target — calculated from your current weight rather than fixed, so it keeps up as you \
                gain. Year of birth rather than age, so it doesn't go stale on your birthday. Barbell \
                weight is what the plate maths assumes.
                """)
        }
    }

    // MARK: Start date

    private var startDateSection: some View {
        Section {
            DatePicker("First training day", selection: $startDate, in: ...Date(), displayedComponents: .date)
                .onChange(of: startDate) { _, new in store.setStartDate(DateKit.key(new)) }
        } header: {
            Text("Start date")
        } footer: {
            Text("""
                Currently week \(state.weeksIn + 1). Set this to your real first training day — the \
                add-ins unlock at week \(Plan.addInWeek).
                """)
        }
    }

    // MARK: Danger zone

    private var dangerZoneSection: some View {
        Section {
            Button("Delete all data", role: .destructive) { confirmDelete = true }
        } header: {
            Text("Danger Zone")
        } footer: {
            Text("""
                Deletes every weigh-in, session tick and logged set — and because the log is mirrored to \
                iCloud, it deletes them from your other devices too, as soon as they next sync. No undo.
                """)
        }
    }
}

/// A Form row that behaves like a native `LabeledContent`, except the value
/// is editable in place: type, and it commits when the field loses focus or
/// on Return. Invalid input reverts to the last good value rather than
/// leaving the field in a state that silently never saved — which a plain
/// `TextField` bound straight to a validated property would otherwise do.
private struct ValidatedRow: View {
    var label: String
    var value: String
    var keyboard: UIKeyboardType = .decimalPad
    var onCommit: (String) -> Bool

    @State private var text: String
    @FocusState private var focused: Bool

    init(label: String, value: String, keyboard: UIKeyboardType = .decimalPad,
         onCommit: @escaping (String) -> Bool) {
        self.label = label
        self.value = value
        self.keyboard = keyboard
        self.onCommit = onCommit
        _text = State(initialValue: value)
    }

    var body: some View {
        LabeledContent(label) {
            TextField(label, text: $text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(commit)
        }
        .onChange(of: focused) { wasFocused, isFocused in
            if wasFocused && !isFocused { commit() }
        }
        // The stored value changing elsewhere (a fresh sync, a restore from
        // backup) has to overwrite whatever's showing — but only while the
        // field isn't actively being edited, or a CloudKit merge landing
        // mid-keystroke would erase what someone is in the middle of typing.
        .onChange(of: value) { _, new in if !focused { text = new } }
    }

    private func commit() {
        guard text != value else { return }
        if !onCommit(text) { text = value }
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
