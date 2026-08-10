import Foundation

/// Fill these in before Connect WHOOP will do anything. Two things only you
/// can provide, and the app is disabled until they're real values rather than
/// silently pointing nowhere.
///
/// This app never holds `WHOOP_CLIENT_SECRET` — that stays on the Cloudflare
/// Pages project exactly as it already does for the web app, which is the
/// whole reason `/api/whoop/exchange` and `/api/whoop/refresh` exist: trading
/// an authorization code (or a refresh token) for an access token needs the
/// secret, and the secret must never ship inside a binary someone could
/// extract it from.
public enum WhoopConfig {

    /// Where that Cloudflare Pages project is deployed — e.g.
    /// `https://training.yourdomain.de` or `https://your-project.pages.dev`.
    /// Its `/api/whoop/exchange` and `/api/whoop/refresh` paths must be
    /// carved out of Cloudflare Access (see ios/README.md), or every call
    /// here gets Access's login page back instead of JSON.
    public static let workerBaseURL = URL(string: "https://REPLACE-ME.pages.dev")

    /// Same value as `WHOOP_CLIENT_ID` on that Pages project. Not a secret —
    /// it appears directly in the authorize URL below, which is public by
    /// construction; anyone watching network traffic sees it regardless.
    public static let clientID = "REPLACE-ME"

    /// Matches `authorize.js`'s `SCOPES` — `offline` is what grants a refresh
    /// token at all, so dropping it here would mean reconnecting every hour.
    public static let scopes = "offline read:recovery read:cycles read:sleep read:profile read:workout"

    /// Registered as an *additional* redirect URI on the WHOOP developer
    /// dashboard, alongside the web app's `https://…/api/whoop/callback` —
    /// most dashboards accept more than one per app; if yours doesn't, this
    /// needs its own WHOOP developer app and its own client ID/secret pair.
    /// Must match what's registered exactly, including case, or WHOOP's
    /// server rejects the exchange with a generic `invalid_grant`.
    public static let redirectURI = "de.playace.brandnewbody.whoop://callback"

    /// The scheme half of `redirectURI` — also has to be registered, in
    /// `Info.plist` under `CFBundleURLTypes`. `WhoopConfigTests` checks the
    /// two stay in agreement rather than trusting that by hand.
    public static let redirectScheme = "de.playace.brandnewbody.whoop"

    /// Optional. Set the same string here and as `WHOOP_APP_TOKEN` on the
    /// Pages project to require a shared header on every call to the two
    /// endpoints above. This is a deterrent, not a security boundary — a
    /// constant baked into the app binary can be extracted by anyone who
    /// tries — but it's a cheap one, and worth having if this app is ever
    /// used by more than a handful of people. Leave nil and the endpoints
    /// work with no extra setup, carrying only the residual risk documented
    /// in `exchange.js`.
    public static let appToken: String? = nil

    public static var isConfigured: Bool {
        guard let workerBaseURL else { return false }
        return workerBaseURL.absoluteString != "https://REPLACE-ME.pages.dev" && clientID != "REPLACE-ME"
    }
}
