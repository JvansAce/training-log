import SwiftUI
import UIKit
import Observation

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
        endsAt = Date().addingTimeInterval(TimeInterval(seconds))
    }

    func add(seconds: Int) {
        guard let current = endsAt else { return }
        total += seconds
        endsAt = current.addingTimeInterval(TimeInterval(seconds))
    }

    func stop() {
        total = 0
        endsAt = nil
    }

    static func format(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
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
