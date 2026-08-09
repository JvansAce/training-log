import Foundation

/// Day keys are `yyyy-MM-dd` in the device's own time zone — the same thing
/// `toLocaleDateString('en-CA')` produced in the web app.
///
/// Deliberately not UTC and deliberately not a shared `DateFormatter`. A
/// weigh-in typed at 23:00 in Berlin belongs to the day the person just
/// lived, and a cached formatter holds the time zone it was built with, so a
/// phone that lands in another country keeps filing entries under the old
/// one. Building the string from `Calendar.current` reads the live zone every
/// time and is thread-safe into the bargain.
public enum DateKit {

    /// `2026-08-09` for the day `date` falls on locally.
    public static func key(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Local midnight for a `yyyy-MM-dd` key, or nil if it isn't one.
    public static func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d)
        else { return nil }
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        return Calendar.current.date(from: c)
    }

    public static var todayKey: String { key(Date()) }

    /// Local midnight of the day `date` falls on.
    public static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    /// JavaScript's `getDay()`: 0 = Sunday … 6 = Saturday. The plan tables are
    /// keyed by it, so the port keeps the same numbering rather than
    /// translating at every call site.
    public static func dow(_ date: Date) -> Int {
        (Calendar.current.component(.weekday, from: date) - 1)
    }

    public static func dow(key: String) -> Int? {
        date(key).map(dow)
    }

    public static func adding(_ days: Int, to date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// Day arithmetic on keys, via `Calendar` rather than millisecond maths, so
    /// an hour lost or gained to daylight saving inside a run can't skip or
    /// repeat a day.
    public static func adding(_ days: Int, to key: String) -> String {
        guard let d = date(key) else { return key }
        return DateKit.key(adding(days, to: d))
    }

    /// Whole days from `a` to `b`, negative if `b` is earlier. Measured between
    /// midnights, which is what makes it DST-proof.
    public static func days(from a: Date, to b: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day ?? 0
    }

    public static func days(from a: String, to b: String) -> Int? {
        guard let x = date(a), let y = date(b) else { return nil }
        return days(from: x, to: y)
    }

    /// Monday-start, matching `ORDER` and how the plan itself is written —
    /// not the locale's first weekday, which would put the week boundary on
    /// Sunday for a US device and quietly change what a "green week" means.
    public static func weekStart(_ date: Date) -> Date {
        let day = startOfDay(date)
        return adding(-((dow(day) + 6) % 7), to: day)
    }

    /// Inclusive run of day keys. Callers cap the span themselves.
    public static func range(from: String, to: String) -> [String] {
        guard let start = date(from), let end = date(to), start <= end else { return [] }
        var out: [String] = []
        var cursor = start
        while cursor <= end {
            out.append(key(cursor))
            cursor = adding(1, to: cursor)
        }
        return out
    }

    /// `9 Aug` — the short form the weekly-review header uses.
    public static func shortLabel(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }
}
