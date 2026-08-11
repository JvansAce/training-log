import SwiftUI
import UIKit
import Observation
import UserNotifications

/// Wall-clock, not a decrementing counter.
///
/// iOS suspends timers in a backgrounded app — which is exactly what a locked
/// phone during a 2:30 rest is — so a counter that subtracts one per tick
/// drifts behind or stops entirely. Deriving the remainder from a target
/// timestamp means that however long the app was frozen, the number is right
/// the instant it comes back.
@Observable
@MainActor
final class RestTimer {
    private(set) var total: Int = 0
    private(set) var endsAt: Date?
    private var autoStopTask: Task<Void, Never>?

    private static let notificationID = "rest-timer-done"
    /// How long the bar keeps showing "rest done" before clearing itself —
    /// long enough to notice without having to tap Stop, short enough that
    /// it doesn't just sit there redrawing forever once rest is actually
    /// over.
    static let doneGrace: TimeInterval = 6

    var isRunning: Bool { total > 0 }

    func remaining(at now: Date = Date()) -> Int {
        guard let endsAt else { return 0 }
        return max(0, Int(endsAt.timeIntervalSince(now).rounded(.up)))
    }

    func fraction(at now: Date = Date()) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(remaining(at: now)) / Double(total)))
    }

    func start(seconds: Int) {
        total = seconds
        let end = Date().addingTimeInterval(TimeInterval(seconds))
        endsAt = end
        scheduleNotification(at: end)
        scheduleAutoStop(at: end)
    }

    func add(seconds: Int) {
        guard let current = endsAt else { return }
        total += seconds
        let end = current.addingTimeInterval(TimeInterval(seconds))
        endsAt = end
        scheduleNotification(at: end)
        scheduleAutoStop(at: end)
    }

    func stop() {
        total = 0
        endsAt = nil
        autoStopTask?.cancel()
        autoStopTask = nil
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    static func format(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Local notification

    /// The bar's own haptic only fires while the app is foregrounded with
    /// the bar on screen — which a locked phone mid-rest, the entire reason
    /// this timer exists, is neither. A local notification is the only way
    /// "rest is over" actually reaches you if the phone's been put down.
    /// Authorization is requested here, at the point a timer is first
    /// started, rather than on launch — if it's denied, this silently does
    /// nothing further and the in-app haptic still covers the foreground
    /// case, same as before this existed.
    private func scheduleNotification(at date: Date) {
        let center = UNUserNotificationCenter.current()
        // Captured as plain locals rather than read from `Self` inside the
        // completion below — that closure doesn't run on the main actor,
        // and a local copy sidesteps any question of isolation on a static
        // member of a `@MainActor` type.
        let identifier = Self.notificationID
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let seconds = max(1, date.timeIntervalSinceNow)
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Rest done"
            content.body = "Back to it."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    /// Clears the timer itself a grace period after it reaches zero, so the
    /// bar's `TimelineView` isn't redrawing twice a second indefinitely and
    /// the "rest done" bar doesn't just sit there until someone remembers to
    /// dismiss it. Re-scheduled on every `start`/`add` against the current
    /// `endsAt`, so extending a rest with "+30s" — including during the
    /// grace window, after it already hit zero once — pushes this back
    /// rather than stopping a rest that's actually still running.
    private func scheduleAutoStop(at end: Date) {
        autoStopTask?.cancel()
        let delayMs = Int((max(0, end.timeIntervalSinceNow) + Self.doneGrace) * 1000)
        autoStopTask = Task {
            try? await Task.sleep(for: .milliseconds(delayMs))
            guard !Task.isCancelled else { return }
            stop()
        }
    }
}

/// The floating countdown. Lives above the tab bar rather than inside a page,
/// so switching to Progress mid-rest doesn't throw the timer away.
struct RestTimerBar: View {
    @Environment(RestTimer.self) private var timer
    @State private var announced = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let left = timer.remaining(at: context.date)
            VStack(spacing: 0) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(left > 0 ? Theme.red : Theme.green)
                        .frame(width: geo.size.width * timer.fraction(at: context.date))
                }
                .frame(height: 3)

                HStack(spacing: 10) {
                    Text(RestTimer.format(left))
                        .font(Theme.mono(19, weight: .bold))
                        .foregroundStyle(left > 0 ? Theme.bone : Theme.green)
                        .monospacedDigit()
                    Text(left > 0 ? "rest" : "rest done")
                        .font(Theme.mono(9.5))
                        .tracking(1.2)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    ActionButton(title: "+30s") { timer.add(seconds: 30) }
                    ActionButton(title: "Stop") { timer.stop() }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(Theme.raise)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            .onChange(of: left) { _, new in
                // Fires once as it crosses zero, not on every tick after.
                guard new == 0, !announced else { return }
                announced = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            .onChange(of: timer.endsAt) { _, _ in announced = false }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
