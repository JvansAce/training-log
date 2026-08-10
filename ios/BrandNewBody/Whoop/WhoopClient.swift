import Foundation
import AuthenticationServices
import Observation
import UIKit

/// Recovery, strain, sleep and today's detected workouts, read straight from
/// WHOOP's API on-device.
///
/// The split with the server is deliberate and narrow: `/api/whoop/exchange`
/// and `/api/whoop/refresh` are the only two calls that need
/// `WHOOP_CLIENT_SECRET`, so they're the only two calls that touch the
/// server at all. Every data read — recovery, cycle, sleep, workout — goes
/// device-to-WHOOP directly with the access token, the same way the web
/// app's Worker did it server-side; the difference is that no health data
/// passes through anything this project runs, only the tokens do, and only
/// at connect and refresh time.
@Observable
@MainActor
final class WhoopClient {

    enum Status: Equatable {
        case checking
        case notConnected(reason: String?)
        case connected
    }

    private(set) var status: Status = .checking
    private(set) var today: WhoopSnapshot?

    private let keychain = KeychainStore(service: "de.playace.brandnewbody.whoop")
    private let presentationContextProvider = PresentationContextProvider()
    private var session: ASWebAuthenticationSession?
    private var pendingVerifier: String?
    private var pendingState: String?

    private enum Account {
        static let accessToken = "accessToken"
        static let refreshToken = "refreshToken"
        static let expiresAt = "expiresAt"
    }

    init() {
        status = keychain.get(account: Account.refreshToken) != nil
            ? .connected
            : .notConnected(reason: nil)
    }

    // MARK: - Connect

    func connect() {
        guard WhoopConfig.isConfigured else {
            status = .notConnected(reason: "WhoopConfig.swift still has its placeholder values — see ios/README.md")
            return
        }
        let pkce = PKCE.generate()
        let state = UUID().uuidString
        pendingVerifier = pkce.verifier
        pendingState = state

        var components = URLComponents(string: "https://api.prod.whoop.com/oauth/oauth2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: WhoopConfig.clientID),
            .init(name: "redirect_uri", value: WhoopConfig.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: WhoopConfig.scopes),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]

        let session = ASWebAuthenticationSession(
            url: components.url!,
            callbackURLScheme: WhoopConfig.redirectScheme
        ) { [weak self] callbackURL, error in
            Task { @MainActor in self?.handleCallback(callbackURL, error: error) }
        }
        // Sharing Safari's session lets someone already signed into WHOOP
        // skip re-entering credentials. The default; named explicitly
        // because it's a real behaviour choice, not an accident.
        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = presentationContextProvider
        self.session = session
        session.start()
    }

    private func handleCallback(_ url: URL?, error: Error?) {
        defer { pendingVerifier = nil; pendingState = nil }
        guard let url, error == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == pendingState,
              let verifier = pendingVerifier
        else {
            // Covers a genuine cancel (Error is ASWebAuthenticationSessionError
            // .canceledLogin) and a response that failed the state check —
            // deliberately the same message for both, since telling a state
            // mismatch apart from a cancel to the person tapping the button
            // would explain an attack that never actually happened to them.
            status = .notConnected(reason: nil)
            return
        }
        Task { await exchangeCode(code, verifier: verifier) }
    }

    private func exchangeCode(_ code: String, verifier: String) async {
        guard let base = WhoopConfig.workerBaseURL else { return }
        var request = URLRequest(url: base.appendingPathComponent("api/whoop/exchange"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let appToken = WhoopConfig.appToken { request.setValue(appToken, forHTTPHeaderField: "x-app-token") }
        request.httpBody = try? JSONEncoder().encode([
            "code": code, "redirect_uri": WhoopConfig.redirectURI, "code_verifier": verifier,
        ])

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.isSuccess == true,
              let tokens = try? JSONDecoder().decode(TokenResponse.self, from: data)
        else {
            status = .notConnected(reason: "the connection could not be completed — check that the Worker is deployed and its two WHOOP endpoints bypass Access")
            return
        }
        store(tokens)
        status = .connected
    }

    // MARK: - Disconnect

    func disconnect() {
        keychain.delete(account: Account.accessToken)
        keychain.delete(account: Account.refreshToken)
        keychain.delete(account: Account.expiresAt)
        today = nil
        status = .notConnected(reason: nil)
    }

    // MARK: - Tokens

    private func store(_ tokens: TokenResponse) {
        keychain.set(tokens.accessToken, account: Account.accessToken)
        keychain.set(tokens.refreshToken, account: Account.refreshToken)
        // A minute early, not exactly at the stated expiry, so a slow request
        // never straddles the boundary and gets rejected mid-flight.
        let expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn) - 60)
        keychain.set(String(expiresAt.timeIntervalSince1970), account: Account.expiresAt)
    }

    private func refreshAccessToken() async -> String? {
        guard let refreshToken = keychain.get(account: Account.refreshToken),
              let base = WhoopConfig.workerBaseURL else { return nil }
        var request = URLRequest(url: base.appendingPathComponent("api/whoop/refresh"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let appToken = WhoopConfig.appToken { request.setValue(appToken, forHTTPHeaderField: "x-app-token") }
        request.httpBody = try? JSONEncoder().encode(["refresh_token": refreshToken])

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.isSuccess == true,
              let tokens = try? JSONDecoder().decode(TokenResponse.self, from: data)
        else {
            // A dead refresh token — WHOOP rotates it on every use, so this is
            // what a stale or already-consumed one looks like. Not
            // retryable; the fix is reconnecting, same as the web app.
            disconnect()
            status = .notConnected(reason: "reconnect")
            return nil
        }
        store(tokens)
        return tokens.accessToken
    }

    private func validAccessToken() async -> String? {
        guard let expiresAtRaw = keychain.get(account: Account.expiresAt),
              let expiresAt = TimeInterval(expiresAtRaw) else { return nil }
        if Date().timeIntervalSince1970 < expiresAt, let token = keychain.get(account: Account.accessToken) {
            return token
        }
        return await refreshAccessToken()
    }

    // MARK: - Data

    private static let apiBase = URL(string: "https://api.prod.whoop.com/developer/v2")!

    /// Fetches everything for `dayKey` and updates `today`. Safe to call from
    /// the scene-phase handler on every foreground — WHOOP's own values
    /// update at most a few times a day, so there's nothing to lose by
    /// asking again, and something to lose by not: this is the only way a
    /// reading taken while the app was closed ever arrives.
    func fetchToday(dayKey: String = DateKit.todayKey) async {
        guard let token = await validAccessToken() else {
            // A dead refresh already routed through `refreshAccessToken` and
            // set `.notConnected(reason: "reconnect")` there. This covers the
            // remaining case — nothing was ever connected — without
            // overwriting that more specific reason.
            if keychain.get(account: Account.refreshToken) == nil { status = .notConnected(reason: nil) }
            return
        }
        status = .connected

        async let recovery = get(RecoveryResponse.self, path: "/recovery?limit=1", token: token)
        async let cycle = get(CycleResponse.self, path: "/cycle?limit=1", token: token)
        async let sleep = get(SleepResponse.self, path: "/activity/sleep?limit=1", token: token)
        async let workouts = get(WorkoutResponse.self, path: "/activity/workout?limit=10", token: token)
        let (rec, cyc, slp, wk) = await (recovery, cycle, sleep, workouts)

        let recoveryRecord = RecoveryRecord(
            recovery: (rec?.records.first).flatMap { WhoopDay.isSameDay($0.createdAt, as: dayKey) ? $0.score?.recoveryScore : nil },
            strain: (cyc?.records.first).flatMap { WhoopDay.isSameDay($0.start ?? $0.createdAt, as: dayKey) ? $0.score?.strain : nil },
            sleepPct: (slp?.records.first).flatMap { WhoopDay.isSameDay($0.start ?? $0.createdAt, as: dayKey) ? $0.score?.sleepPerformancePct : nil },
            hrvMs: (rec?.records.first).flatMap { WhoopDay.isSameDay($0.createdAt, as: dayKey) ? $0.score?.hrvRmssdMilli : nil },
            restingHR: (rec?.records.first).flatMap { WhoopDay.isSameDay($0.createdAt, as: dayKey) ? $0.score?.restingHeartRate : nil }
        )

        // Ignore very short activities — WHOOP records plenty of incidental
        // ones, and "you trained today" should mean an actual session.
        let detected = (wk?.records ?? [])
            .filter { WhoopDay.isSameDay($0.start ?? $0.createdAt, as: dayKey) }
            .map { record in
                DetectedWorkout(
                    // Synthesized rather than read from WHOOP's own id: these
                    // are shown once and never persisted, so nothing needs a
                    // stable identity across fetches — only a unique one for
                    // this SwiftUI pass. Not decoding WHOOP's id at all avoids
                    // a real risk for no benefit: if it ever arrives as a JSON
                    // number rather than a string, a typed `let id: String?`
                    // would fail the whole response's decode, not just this
                    // field, over a value this feature doesn't use.
                    id: UUID().uuidString,
                    sport: record.sportName,
                    minutes: minutes(from: record),
                    strain: record.score?.strain
                )
            }
            .filter { ($0.minutes ?? 10) >= 10 }

        today = WhoopSnapshot(recovery: recoveryRecord, workouts: detected, asOf: Date())
    }

    private func minutes(from record: WorkoutResponse.Record) -> Int? {
        guard let start = record.start.flatMap(WhoopDay.parse),
              let end = record.end.flatMap(WhoopDay.parse) else { return nil }
        return Int((end.timeIntervalSince(start) / 60).rounded())
    }

    private func get<T: Decodable>(_ type: T.Type, path: String, token: String) async -> T? {
        // Built as a plain string rather than through `appendingPathComponent`,
        // which would percent-encode `path`'s own leading `?limit=1` into the
        // path itself instead of leaving it as a query string.
        guard let url = URL(string: "\(Self.apiBase.absoluteString)\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.isSuccess == true
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Presentation

/// A separate object rather than making `WhoopClient` itself conform:
/// `ASWebAuthenticationPresentationContextProviding` is an Objective-C
/// protocol needing an `NSObject`-derived conformer, and there is no reason
/// to tangle that requirement into the `@Observable` model the rest of the
/// app reads.
private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

private extension HTTPURLResponse {
    var isSuccess: Bool { (200...299).contains(statusCode) }
}

// MARK: - Server responses

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

// MARK: - WHOOP API responses

private struct RecoveryResponse: Decodable {
    struct Record: Decodable {
        struct Score: Decodable {
            let recoveryScore: Int?
            let hrvRmssdMilli: Double?
            let restingHeartRate: Int?
            enum CodingKeys: String, CodingKey {
                case recoveryScore = "recovery_score"
                case hrvRmssdMilli = "hrv_rmssd_milli"
                case restingHeartRate = "resting_heart_rate"
            }
        }
        let createdAt: String?
        let score: Score?
        enum CodingKeys: String, CodingKey {
            case createdAt = "created_at"
            case score
        }
    }
    let records: [Record]
}

private struct CycleResponse: Decodable {
    struct Record: Decodable {
        struct Score: Decodable { let strain: Double? }
        let createdAt: String?
        let start: String?
        let score: Score?
        enum CodingKeys: String, CodingKey {
            case createdAt = "created_at"
            case start, score
        }
    }
    let records: [Record]
}

private struct SleepResponse: Decodable {
    struct Record: Decodable {
        struct Score: Decodable {
            let sleepPerformancePct: Int?
            enum CodingKeys: String, CodingKey {
                case sleepPerformancePct = "sleep_performance_percentage"
            }
        }
        let createdAt: String?
        let start: String?
        let score: Score?
        enum CodingKeys: String, CodingKey {
            case createdAt = "created_at"
            case start, score
        }
    }
    let records: [Record]
}

private struct WorkoutResponse: Decodable {
    struct Record: Decodable {
        struct Score: Decodable {
            let strain: Double?
        }
        let createdAt: String?
        let start: String?
        let end: String?
        let sportName: String?
        let score: Score?
        enum CodingKeys: String, CodingKey {
            case createdAt = "created_at"
            case start, end
            case sportName = "sport_name"
            case score
        }
    }
    let records: [Record]
}

// MARK: - What the UI reads

struct WhoopSnapshot: Equatable {
    var recovery: RecoveryRecord
    var workouts: [DetectedWorkout]
    var asOf: Date
}

struct DetectedWorkout: Identifiable, Equatable {
    var id: String
    var sport: String?
    var minutes: Int?
    var strain: Double?
}
