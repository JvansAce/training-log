import Foundation

/// A small, deliberately narrow accommodation for a specific medial-meniscus
/// issue — not a general "go easy" mode. It swaps exactly two exercises for
/// knee-friendlier versions when turned on, and touches nothing else in the
/// week.
///
/// Narrow on purpose: a real test at a real load (40 kg) showed the main
/// squat/trap-bar pattern itself is fine — it's specifically deep unilateral
/// flexion under a rotational bias (the Bulgarian split squat) and a
/// plyometric landing (box jumps) that aren't. Swapping out the whole lower
/// body because one exercise is a problem would both under-train the knee
/// that's actually fine and hide the one signal — that a real loaded squat
/// doesn't hurt — worth building back around.
public enum Knee {

    /// Original exercise key → its knee-care replacement key. Both sides of
    /// every pair are real, permanent entries in `Plan.schedule` with their
    /// own liftID — this table only decides which one is currently shown,
    /// never which one exists. Toggling the mode off and back on again does
    /// not touch either side's logged history.
    static let substitutions: [String: String] = [
        "we-bss": "we-legpress",
        "sa-boxjump": "sa-hipthrust",
    ]

    /// `items` filtered down to whichever side of each pair matches the
    /// mode. Anything that isn't part of a pair passes through untouched,
    /// in its original position — the replacement's slot sits immediately
    /// after the original's in `Plan.schedule` for exactly this reason, so
    /// filtering one out leaves the other exactly where it belongs.
    public static func adjustedItems(_ items: [Exercise], kneeCareMode: Bool) -> [Exercise] {
        let replacementKeys = Set(substitutions.values)
        return items.filter { item in
            if substitutions[item.key] != nil { return !kneeCareMode }
            if replacementKeys.contains(item.key) { return kneeCareMode }
            return true
        }
    }
}
