import Foundation
import Observation

/// Reads Hevy's REST API on-device, the same shape as `WhoopClient` minus
/// the OAuth dance: Hevy Pro issues one static API key directly from its own
/// settings page, so there's no exchange/refresh round-trip to build —
/// just a key, kept in the Keychain the same way WHOOP's tokens are.
@Observable
@MainActor
final class HevyClient {

    enum Status: Equatable {
        case notConnected
        case connected
    }

    private(set) var status: Status = .notConnected

    private let keychain = KeychainStore(service: "de.playace.brandnewbody.hevy")
    private enum Account {
        static let apiKey = "apiKey"
    }

    init() {
        status = keychain.get(account: Account.apiKey) != nil ? .connected : .notConnected
    }

    func connect(apiKey: String) {
        keychain.set(apiKey, account: Account.apiKey)
        status = .connected
    }

    func disconnect() {
        keychain.delete(account: Account.apiKey)
        status = .notConnected
    }

    private static let apiBase = URL(string: "https://api.hevyapp.com/v1")!

    // MARK: - Workouts

    /// Every workout newer than `lastSeenID`, oldest first — so importing
    /// writes history in the order it actually happened. Hevy returns pages
    /// newest-first, so this walks forward through pages collecting
    /// everything until it either hits `lastSeenID` or runs out, then
    /// reverses once at the end.
    ///
    /// Capped at 20 pages regardless of whether `lastSeenID` is set — a
    /// first connect only needs recent sessions to start building lift
    /// history from here forward, and if `lastSeenID` refers to a workout
    /// since deleted in Hevy, it will never be found either, which would
    /// otherwise mean paging through the account's *entire* history on
    /// every single foreground.
    func fetchNewWorkouts(since lastSeenID: String?) async -> [HevyWorkout] {
        var collected: [HevyWorkout] = []
        var page = 1
        while true {
            guard let result = await fetchWorkoutsPage(page) else { break }
            for workout in result.workouts {
                if workout.id == lastSeenID { return collected.reversed() }
                collected.append(workout)
            }
            if result.workouts.isEmpty || page >= result.pageCount { break }
            page += 1
            if page > 20 { break }
        }
        return collected.reversed()
    }

    private func fetchWorkoutsPage(_ page: Int, pageSize: Int = 10) async -> HevyWorkoutsPage? {
        guard let key = keychain.get(account: Account.apiKey),
              var components = URLComponents(url: Self.apiBase.appendingPathComponent("workouts"),
                                              resolvingAgainstBaseURL: false)
        else { return nil }
        components.queryItems = [.init(name: "page", value: String(page)),
                                  .init(name: "pageSize", value: String(pageSize))]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "api-key")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.isSuccess == true
        else { return nil }
        return try? JSONDecoder().decode(HevyWorkoutsPage.self, from: data)
    }

    // MARK: - Exercise templates

    /// The full catalog, paged through once — a "match my exercises" pass
    /// is a one-time setup action, not something that re-fetches a few
    /// hundred entries per keystroke of a search box.
    ///
    /// Unlike `/v1/workouts`, this endpoint's exact response shape hasn't
    /// been confirmed against a live account — only inferred from the same
    /// api-key/pagination convention `/v1/workouts` uses (confirmed
    /// directly from a real response). A shape mismatch here fails soft —
    /// an empty catalog, not a crash — and the mapping UI has a manual
    /// "paste the template ID yourself" fallback for exactly that case.
    func fetchAllExerciseTemplates() async -> [HevyExerciseTemplate] {
        guard keychain.get(account: Account.apiKey) != nil else { return [] }
        var all: [HevyExerciseTemplate] = []
        var page = 1
        while page <= 50 {   // hard stop — bounds a few hundred entries at pageSize 100
            guard let result = await fetchExerciseTemplatesPage(page) else { break }
            all.append(contentsOf: result.exerciseTemplates)
            if result.exerciseTemplates.isEmpty || page >= result.pageCount { break }
            page += 1
        }
        return all
    }

    private func fetchExerciseTemplatesPage(_ page: Int) async -> HevyExerciseTemplatesPage? {
        guard let key = keychain.get(account: Account.apiKey),
              var components = URLComponents(url: Self.apiBase.appendingPathComponent("exercise_templates"),
                                              resolvingAgainstBaseURL: false)
        else { return nil }
        components.queryItems = [.init(name: "page", value: String(page)),
                                  .init(name: "pageSize", value: "100")]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "api-key")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.isSuccess == true
        else { return nil }
        return try? JSONDecoder().decode(HevyExerciseTemplatesPage.self, from: data)
    }

    // MARK: - Body measurements

    /// Every measurement entry newer than `lastSeenDate` — same shape as
    /// `fetchNewWorkouts`, but keyed by the date itself rather than an
    /// opaque id, since that's what `GET .../{date}` already implies this
    /// resource is addressed by.
    ///
    /// Response shape is inferred, the same caveat as exercise templates:
    /// `/v1/body_measurements` hasn't been confirmed against a live
    /// response. A mismatch here just means nothing imports — weight and
    /// waist can still be typed in on Today exactly as before.
    func fetchNewBodyMeasurements(since lastSeenDate: String?) async -> [HevyBodyMeasurement] {
        var collected: [HevyBodyMeasurement] = []
        var page = 1
        while true {
            guard let result = await fetchBodyMeasurementsPage(page) else { break }
            for entry in result.measurements {
                if let lastSeenDate, entry.date <= lastSeenDate { return collected.reversed() }
                collected.append(entry)
            }
            if result.measurements.isEmpty || page >= result.pageCount { break }
            page += 1
            if page > 20 { break }
        }
        return collected.reversed()
    }

    private func fetchBodyMeasurementsPage(_ page: Int) async -> HevyBodyMeasurementsPage? {
        guard let key = keychain.get(account: Account.apiKey),
              var components = URLComponents(url: Self.apiBase.appendingPathComponent("body_measurements"),
                                              resolvingAgainstBaseURL: false)
        else { return nil }
        components.queryItems = [.init(name: "page", value: String(page)),
                                  .init(name: "pageSize", value: "10")]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "api-key")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.isSuccess == true
        else { return nil }
        return try? JSONDecoder().decode(HevyBodyMeasurementsPage.self, from: data)
    }

    // MARK: - Routines and folders

    /// An existing folder with this title, if the account already has one —
    /// checked before creating, so a POST that actually succeeded at Hevy
    /// but whose response never made it back to this device (dropped
    /// connection, say) doesn't leave the next retry creating a second
    /// folder with the same name. `createRoutine`/`updateRoutine` don't get
    /// the same safety net for every push — the id `pushRoutines` already
    /// persists after a first success covers the common case, and re-
    /// checking by title before every single routine would cost a full
    /// account routine listing on every push for a failure mode this rare.
    func findOrCreateRoutineFolder(title: String) async -> String? {
        if let existing = await fetchRoutineFolders().first(where: { $0.title == title }) {
            return String(existing.id)
        }
        return await createRoutineFolder(title: title)
    }

    /// An existing routine with this exact title, if the account already
    /// has one — the one extra check `pushRoutines` makes before creating a
    /// brand new routine (not before updating one it already has an id
    /// for), for the same reason as `findOrCreateRoutineFolder`.
    func findExistingRoutine(title: String) async -> String? {
        await fetchRoutines().first(where: { $0.title == title })?.id
    }

    private func fetchRoutineFolders() async -> [HevyRoutineFolderSummary] {
        guard keychain.get(account: Account.apiKey) != nil else { return [] }
        var all: [HevyRoutineFolderSummary] = []
        var page = 1
        while page <= 20 {
            guard let result = await fetchRoutineFoldersPage(page) else { break }
            all.append(contentsOf: result.routineFolders)
            if result.routineFolders.isEmpty || page >= result.pageCount { break }
            page += 1
        }
        return all
    }

    private func fetchRoutineFoldersPage(_ page: Int) async -> HevyRoutineFoldersPage? {
        guard let key = keychain.get(account: Account.apiKey),
              var components = URLComponents(url: Self.apiBase.appendingPathComponent("routine_folders"),
                                              resolvingAgainstBaseURL: false)
        else { return nil }
        components.queryItems = [.init(name: "page", value: String(page)), .init(name: "pageSize", value: "10")]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "api-key")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.isSuccess == true
        else { return nil }
        return try? JSONDecoder().decode(HevyRoutineFoldersPage.self, from: data)
    }

    private func fetchRoutines() async -> [HevyRoutineSummary] {
        guard keychain.get(account: Account.apiKey) != nil else { return [] }
        var all: [HevyRoutineSummary] = []
        var page = 1
        while page <= 20 {
            guard let result = await fetchRoutinesPage(page) else { break }
            all.append(contentsOf: result.routines)
            if result.routines.isEmpty || page >= result.pageCount { break }
            page += 1
        }
        return all
    }

    private func fetchRoutinesPage(_ page: Int) async -> HevyRoutinesPage? {
        guard let key = keychain.get(account: Account.apiKey),
              var components = URLComponents(url: Self.apiBase.appendingPathComponent("routines"),
                                              resolvingAgainstBaseURL: false)
        else { return nil }
        components.queryItems = [.init(name: "page", value: String(page)), .init(name: "pageSize", value: "10")]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "api-key")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.isSuccess == true
        else { return nil }
        return try? JSONDecoder().decode(HevyRoutinesPage.self, from: data)
    }

    /// Creates one routine folder and returns its id — meant to be called
    /// once, with the id then kept in Setup (`hevyRoutineFolderID`) rather
    /// than re-created on every push.
    ///
    /// Confirmed against a live account: the request is wrapped in
    /// `{"routine_folder": {...}}` and so is the response. `createRoutine`
    /// and `updateRoutine` remain unconfirmed — a wrong guess there fails
    /// as an HTTP error or a decode failure, either way creating nothing
    /// rather than writing something malformed.
    private func createRoutineFolder(title: String) async -> String? {
        guard let key = keychain.get(account: Account.apiKey) else { return nil }
        var request = URLRequest(url: Self.apiBase.appendingPathComponent("routine_folders"))
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONEncoder().encode(HevyRoutineFolderCreateBody(routineFolder: .init(title: title)))
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.isSuccess == true,
              let created = try? JSONDecoder().decode(HevyRoutineFolderResponse.self, from: data)
        else { return nil }
        return String(created.routineFolder.id)
    }

    /// Returns the created routine's id, or `nil` on any failure — see the
    /// caveat on `createRoutineFolder`.
    func createRoutine(_ input: HevyRoutineInput) async -> String? {
        guard let key = keychain.get(account: Account.apiKey) else { return nil }
        var request = URLRequest(url: Self.apiBase.appendingPathComponent("routines"))
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONEncoder().encode(HevyRoutineWriteBody(routine: input))
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.isSuccess == true,
              let created = try? JSONDecoder().decode(HevyRoutineResponse.self, from: data)
        else { return nil }
        return created.routine.id
    }

    /// Replaces an existing routine's content in place — used once a push
    /// already has an id stored for that weekday, so re-pushing the plan
    /// updates it rather than creating a duplicate.
    func updateRoutine(id: String, _ input: HevyRoutineInput) async -> Bool {
        guard let key = keychain.get(account: Account.apiKey) else { return false }
        var request = URLRequest(url: Self.apiBase.appendingPathComponent("routines/\(id)"))
        request.httpMethod = "PUT"
        request.setValue(key, forHTTPHeaderField: "api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONEncoder().encode(HevyRoutineWriteBody(routine: input))
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.isSuccess == true
    }
}

private extension HTTPURLResponse {
    var isSuccess: Bool { (200...299).contains(statusCode) }
}

// MARK: - Wire format

/// Field names and shape confirmed directly against a real `GET
/// /v1/workouts` response — not guessed. Extra fields Hevy sends
/// (`description`, `notes`, `superset_id`, `distance_meters`, `rpe`, …)
/// are simply never listed here; `Decodable` ignores keys a type doesn't
/// ask for.
struct HevyWorkoutsPage: Decodable {
    let page: Int
    let pageCount: Int
    let workouts: [HevyWorkout]
    enum CodingKeys: String, CodingKey {
        case page
        case pageCount = "page_count"
        case workouts
    }
}

public struct HevyWorkout: Decodable {
    let id: String
    let title: String
    /// ISO 8601 with a numeric UTC offset, e.g. `2026-06-12T14:39:18+00:00`.
    let startTime: String
    let exercises: [HevyExercise]
    enum CodingKeys: String, CodingKey {
        case id, title
        case startTime = "start_time"
        case exercises
    }
}

struct HevyExercise: Decodable {
    let title: String
    let exerciseTemplateID: String
    let sets: [HevySet]
    enum CodingKeys: String, CodingKey {
        case title
        case exerciseTemplateID = "exercise_template_id"
        case sets
    }
}

struct HevySet: Decodable {
    /// Seen: `"normal"`. Hevy's own app also has warm-up/failure/drop-set
    /// types — this app only imports working sets, see `HevyImport`.
    let type: String
    /// `0` and `null` both mean bodyweight, the same convention `LiftSet`
    /// already uses.
    let weightKg: Double?
    let reps: Int?
    enum CodingKeys: String, CodingKey {
        case type
        case weightKg = "weight_kg"
        case reps
    }
}

/// Inferred shape — see the doc comment on `fetchAllExerciseTemplates`.
public struct HevyExerciseTemplate: Decodable, Identifiable, Equatable {
    public let id: String
    let title: String
}

struct HevyExerciseTemplatesPage: Decodable {
    let page: Int
    let pageCount: Int
    let exerciseTemplates: [HevyExerciseTemplate]
    enum CodingKeys: String, CodingKey {
        case page
        case pageCount = "page_count"
        case exerciseTemplates = "exercise_templates"
    }
}

/// Inferred shape — see the caveat on `fetchNewBodyMeasurements`. Only
/// `date`, `weight_kg` and `waist_cm` are read; whatever other measurements
/// Hevy tracks (body fat %, other circumferences, …) are ignored the same
/// way `Decodable` already ignores fields this app has no use for elsewhere.
public struct HevyBodyMeasurement: Decodable {
    let date: String
    let weightKg: Double?
    let waistCm: Double?
    enum CodingKeys: String, CodingKey {
        case date
        case weightKg = "weight_kg"
        case waistCm = "waist_cm"
    }
}

struct HevyBodyMeasurementsPage: Decodable {
    let page: Int
    let pageCount: Int
    let measurements: [HevyBodyMeasurement]
    enum CodingKeys: String, CodingKey {
        case page
        case pageCount = "page_count"
        case measurements = "body_measurements"
    }
}

// MARK: - Routine wire format (least confident — see createRoutineFolder)

struct HevyRoutineSetInput: Encodable {
    var type = "normal"
    var repRange: RepRange?
    struct RepRange: Encodable { var start: Int; var end: Int }
    enum CodingKeys: String, CodingKey {
        case type
        case repRange = "rep_range"
    }
}

struct HevyRoutineExerciseInput: Encodable {
    var exerciseTemplateID: String
    var sets: [HevyRoutineSetInput]
    var restSeconds: Int?
    enum CodingKeys: String, CodingKey {
        case exerciseTemplateID = "exercise_template_id"
        case sets
        case restSeconds = "rest_seconds"
    }
}

public struct HevyRoutineInput: Encodable {
    var title: String
    var folderID: Int?
    var exercises: [HevyRoutineExerciseInput]
    enum CodingKeys: String, CodingKey {
        case title
        case folderID = "folder_id"
        case exercises
    }
}

struct HevyRoutineWriteBody: Encodable {
    var routine: HevyRoutineInput
}

struct HevyRoutineResponse: Decodable {
    /// Routine ids are strings (UUIDs), unlike routine *folder* ids, which
    /// are JSON numbers — confirmed against Hevy's own OpenAPI spec.
    /// Decoding this as `Int` (an earlier guess, by analogy with the
    /// folder id) silently failed every single create call.
    struct Inner: Decodable { let id: String }
    let routine: Inner
}

struct HevyRoutineFolderCreateBody: Encodable {
    struct Inner: Encodable { var title: String }
    var routineFolder: Inner
    enum CodingKeys: String, CodingKey { case routineFolder = "routine_folder" }
}

struct HevyRoutineFolderResponse: Decodable {
    struct Inner: Decodable { let id: Int }
    let routineFolder: Inner
    enum CodingKeys: String, CodingKey { case routineFolder = "routine_folder" }
}

struct HevyRoutineFolderSummary: Decodable {
    let id: Int
    let title: String
}

struct HevyRoutineFoldersPage: Decodable {
    let page: Int
    let pageCount: Int
    let routineFolders: [HevyRoutineFolderSummary]
    enum CodingKeys: String, CodingKey {
        case page
        case pageCount = "page_count"
        case routineFolders = "routine_folders"
    }
}

struct HevyRoutineSummary: Decodable {
    let id: String
    let title: String
}

struct HevyRoutinesPage: Decodable {
    let page: Int
    let pageCount: Int
    let routines: [HevyRoutineSummary]
    enum CodingKeys: String, CodingKey {
        case page
        case pageCount = "page_count"
        case routines
    }
}
