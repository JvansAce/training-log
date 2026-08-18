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

struct HevyWorkout: Decodable {
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
struct HevyExerciseTemplate: Decodable, Identifiable, Equatable {
    let id: String
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
