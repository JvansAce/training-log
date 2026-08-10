import Foundation

/// Whether a WHOOP timestamp belongs to a given local calendar day.
///
/// WHOOP's `?limit=1` endpoints return the single most recent record ever,
/// with no date filter — before today's has scored, that is yesterday's, and
/// without this check it would be shown as if it were today's, including
/// driving the "recovery is red" advice off a stale number.
///
/// "Today" has to be the device's local calendar day, not UTC, for the same
/// reason the web app's Worker took its caller's date as a parameter rather
/// than computing one: for anyone east of Greenwich, the small hours of the
/// morning are still "yesterday" in UTC, and a real reading would otherwise
/// be filtered out as stale.
public enum WhoopDay {
    public static func isSameDay(_ timestamp: String?, as dayKey: String) -> Bool {
        guard let timestamp, let date = parse(timestamp) else { return false }
        return DateKit.key(date) == dayKey
    }

    /// WHOOP sends ISO 8601 with fractional seconds (`…10:15:00.000Z`); a
    /// bare `ISO8601DateFormatter` rejects those unless the option is set, so
    /// both are tried rather than assuming one shape.
    static func parse(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: s) { return date }
        return ISO8601DateFormatter().date(from: s)
    }
}
