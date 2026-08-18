import SwiftUI

/// One row per lift in the plan, each pointed at an exercise in the user's
/// own Hevy catalog — by `exercise_template_id`, never by name, so this
/// keeps working even if either side gets renamed later. "Auto-match" is a
/// starting guess (`HevySearchTerms`), not a final answer: every row stays
/// tappable to pick something else, which is the whole reason this is its
/// own screen and not a table that just gets built silently.
struct HevyMappingView: View {
    var mapping: [String: String]
    var onSave: ([String: String]) -> Void

    @Environment(HevyClient.self) private var hevy
    @Environment(\.dismiss) private var dismiss

    @State private var localMapping: [String: String]
    @State private var catalog: [HevyExerciseTemplate] = []
    @State private var loadingCatalog = true
    @State private var editingLiftID: String?

    init(mapping: [String: String], onSave: @escaping ([String: String]) -> Void) {
        self.mapping = mapping
        self.onSave = onSave
        _localMapping = State(initialValue: mapping)
    }

    var body: some View {
        NavigationStack {
            List {
                if loadingCatalog {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading your Hevy catalog…")
                    }
                } else if catalog.isEmpty {
                    Text("""
                        Couldn't read the catalog — check the connection in Setup. You can still tap a \
                        row below and enter an exercise id by hand if you already know it.
                        """)
                    .foregroundStyle(.secondary)
                } else {
                    Section {
                        Button("Auto-match everything still unmatched") { autoMatchUnmatched() }
                    }
                }
                Section {
                    ForEach(Plan.liftIDs, id: \.self) { liftID in
                        Button {
                            editingLiftID = liftID
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Plan.liftNames[liftID] ?? liftID)
                                        .foregroundStyle(.primary)
                                    Text(matchedTitle(for: liftID) ?? "Not matched")
                                        .font(.footnote)
                                        .foregroundStyle(matchedTitle(for: liftID) == nil ? Color.red : .secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Matched: \(localMapping.count) of \(Plan.liftIDs.count).")
                }
            }
            .navigationTitle("Match exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onSave(localMapping)
                        dismiss()
                    }
                }
            }
        }
        .task {
            catalog = await hevy.fetchAllExerciseTemplates()
            loadingCatalog = false
        }
        .sheet(isPresented: Binding(get: { editingLiftID != nil }, set: { if !$0 { editingLiftID = nil } })) {
            if let liftID = editingLiftID {
                HevyExercisePicker(
                    liftName: Plan.liftNames[liftID] ?? liftID,
                    catalog: catalog,
                    initialQuery: HevySearchTerms.byLiftID[liftID] ?? "",
                    manualID: localMapping[liftID]
                ) { templateID in
                    localMapping[liftID] = templateID
                    editingLiftID = nil
                }
            }
        }
    }

    private func matchedTitle(for liftID: String) -> String? {
        guard let id = localMapping[liftID] else { return nil }
        return catalog.first { $0.id == id }?.title ?? id
    }

    private func autoMatchUnmatched() {
        for (liftID, term) in HevySearchTerms.byLiftID where localMapping[liftID] == nil {
            if let match = HevySearchTerms.bestMatch(for: term, in: catalog) {
                localMapping[liftID] = match.id
            }
        }
    }
}

/// The search-and-pick sheet for one lift. A plain text field over the
/// already-fetched catalog — filtering a few hundred titles locally is
/// instant, and it means picking a different exercise never needs another
/// network round trip.
private struct HevyExercisePicker: View {
    var liftName: String
    var catalog: [HevyExerciseTemplate]
    var initialQuery: String
    var manualID: String?
    var onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var manualEntry: String

    init(liftName: String, catalog: [HevyExerciseTemplate], initialQuery: String,
         manualID: String?, onPick: @escaping (String) -> Void) {
        self.liftName = liftName
        self.catalog = catalog
        self.initialQuery = initialQuery
        self.manualID = manualID
        self.onPick = onPick
        // Whatever this lift is already pointed at, so reopening the sheet
        // to double-check or nudge it doesn't start from a blank field.
        _manualEntry = State(initialValue: manualID ?? "")
    }

    private var results: [HevyExerciseTemplate] {
        guard !query.isEmpty else { return Array(catalog.prefix(30)) }
        return HevySearchTerms.matches(for: query, in: catalog)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(results) { template in
                        Button(template.title) { onPick(template.id) }
                            .foregroundStyle(.primary)
                    }
                    if catalog.isEmpty {
                        Text("Catalog is empty or couldn't be read.").foregroundStyle(.secondary)
                    } else if results.isEmpty {
                        Text("No matches for \"\(query)\".").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Search results")
                }
                Section {
                    TextField("Paste a Hevy exercise id directly", text: $manualEntry)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Use this id") {
                        let id = manualEntry.trimmingCharacters(in: .whitespaces)
                        guard !id.isEmpty else { return }
                        onPick(id)
                    }
                } header: {
                    Text("Or enter an id by hand")
                } footer: {
                    Text("For the rare case the search above can't find it — the id from Hevy's own exercise detail, if you already have it.")
                }
            }
            .searchable(text: $query, prompt: "Search \(liftName)")
            .navigationTitle(liftName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { query = initialQuery }
        }
    }
}
