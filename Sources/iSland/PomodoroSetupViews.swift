import SwiftUI

/// The pomodoro's rhythm, set by you: focus, short break, long break, and how many focus periods before the long one.
struct PomodoroSetupCard: View {
    @ObservedObject var focus: FocusTimer
    let onStart: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: IslandLayout.mirrorSpacing) {
            VStack(spacing: IslandLayout.folderRowSpacing) {
                row(L10n.t("Focus"), minutes: focus.plan.focus, range: 5...120, step: 5) { focus.plan.focus = $0 }
                row(L10n.t("Short break"), minutes: focus.plan.shortBreak, range: 1...30, step: 1) { focus.plan.shortBreak = $0 }
                row(L10n.t("Long break"), minutes: focus.plan.longBreak, range: 5...60, step: 5) { focus.plan.longBreak = $0 }
                stepper(L10n.t("Long break every"), text: L10n.rounds(focus.plan.rounds), value: focus.plan.rounds, range: 2...8, step: 1) {
                    focus.plan.rounds = $0
                }
            }
            HStack(spacing: 10) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold))
                        Text(L10n.t("Back"))
                    }
                }
                .buttonStyle(SubtleButtonStyle())
                Spacer()
                Button(L10n.t("Start"), action: onStart)
                    .buttonStyle(CapsuleButtonStyle(fill: Color(red: 1, green: 0.38, blue: 0.32).opacity(0.9), foreground: Color.white))
            }
            .frame(height: IslandLayout.mirrorButtonHeight)
        }
        .padding(.horizontal, IslandLayout.sidePadding)
    }

    private func row(_ label: String, minutes: Int, range: ClosedRange<Int>, step: Int, set: @escaping (Int) -> Void) -> some View {
        stepper(label, text: "\(minutes) min", value: minutes, range: range, step: step, set: set)
    }

    private func stepper(_ label: String, text: String, value: Int, range: ClosedRange<Int>, step: Int,
                         set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.9))
            Spacer(minLength: 4)
            stepButton("minus", enabled: value > range.lowerBound) { set(max(range.lowerBound, value - step)) }
            Text(text).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(Color.white)
                .frame(width: 72)
            stepButton("plus", enabled: value < range.upperBound) { set(min(range.upperBound, value + step)) }
        }
        .padding(.horizontal, 12)
        .frame(height: IslandLayout.folderRowHeight)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(IconButtonStyle())
        .opacity(enabled ? 1 : 0.3)
        .disabled(!enabled)
    }
}
