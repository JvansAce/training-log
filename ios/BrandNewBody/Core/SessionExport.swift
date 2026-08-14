import Foundation

/// A plain-text summary of one day's logged lifting, for pasting somewhere
/// else.
///
/// WHOOP has no public write endpoint for strength work — the v2 API this app
/// reads recovery and sleep from is read-only for activities — so the only
/// route from this log into a WHOOP entry is the clipboard and a person. That
/// makes the output's job specific: unambiguous enough to retype from, compact
/// enough to paste into a notes field without editing it first.
///
/// Ordered by the session itself rather than by whatever order the store hands
/// back, so a paste reads like the workout that happened. Lifts with nothing
/// logged are omitted entirely — an exercise you skipped is not the same as one
/// you did for no sets, and an entry padded with blank lines is worse than a
/// short one.
public enum SessionExport {

    /// nil when the day has nothing logged worth exporting, so callers can
    /// simply not offer the button rather than hand over an empty string.
    public static func text(_ state: LogState, on date: String) -> String? {
        // `effectiveDow` rather than the date's own calendar weekday, so a
        // swapped day exports the plan actually followed that day.
        let day = Plan.day(state.effectiveDow(on: date))

        var lines: [String] = []
        var totalSets = 0
        var totalLoad = 0

        for item in day.items {
            guard let id = item.liftID, id != "pyramid",
                  let record = state.liftHistory(id).first(where: { $0.date == date }),
                  !record.sets.isEmpty
            else { continue }
            // The same name the checklist shows, so an assisted lift exports as
            // assisted rather than as whatever the plan calls it in the
            // abstract, and the same set formatting, so "BW −25 kg × 8" means
            // here exactly what it means on screen.
            lines.append("\(item.displayName(state)) — \(Lifts.describe(record))")
            totalSets += record.sets.count
            if let kg = Lifts.volume(record).kg { totalLoad += kg }
        }

        // Read from the logged record rather than the live cap, so a session
        // exported weeks later reports the rounds actually done that day.
        // Appended after the loop, which puts it last — where it sits on
        // Saturday's own checklist.
        if let pyramid = state.pyramidLog[date] {
            let totals = Pyramid.totals(cap: pyramid.cap)
            var line = "Holland pyramid — rounds 1–\(pyramid.cap)"
            if let vest = pyramid.vestKg { line += ", vest \(Lifts.fmt(vest)) kg" }
            line += " — " + totals.parts.map { "\($0.reps) \($0.name)" }.joined(separator: " · ")
            line += " (\(totals.total) reps)"
            lines.append(line)
        }

        guard !lines.isEmpty else { return nil }

        // ISO date rather than "11 Aug": this is going into a log, where
        // unambiguous beats friendly.
        var out = ["\(day.title) — \(date)"]
        out.append(contentsOf: lines)

        if totalSets > 0 {
            var footer = "\(totalSets) set\(totalSets == 1 ? "" : "s")"
            // Bodyweight and assisted work carries no external load, so a
            // session made only of those reports its sets and stays quiet about
            // volume rather than claiming 0 kg.
            if totalLoad > 0 { footer += " · \(totalLoad) kg total volume" }
            out.append(footer)
        }

        return out.joined(separator: "\n")
    }
}
