import SwiftUI

/// Big centered text for framing prompts ("Step into frame", "Stand side-on,
/// full body", "More light, please").
struct CenteredOverlay: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.55))
            )
            .shadow(color: .black, radius: 6)
    }
}

/// Single-line live cue chip shown above the status footer.
struct CueChip: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.7), lineWidth: 1)
                )
        )
    }
}

/// Terminal-style status line above the controls.
struct StatusFooter: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.lime)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.55))
            )
    }
}

/// Bottom controls: flip camera, switch lift, reset set, end set.
struct Controls: View {
    let voiceOn: Bool
    let canFlip: Bool
    let isRunning: Bool
    let onFlip: () -> Void
    let onPickLift: () -> Void
    let onResetSet: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            roundButton(icon: "arrow.triangle.2.circlepath.camera", enabled: canFlip, action: onFlip)
            roundButton(icon: "figure.strengthtraining.traditional", enabled: true, action: onPickLift)
            Spacer()
            Button(action: onResetSet) {
                Label("Reset set", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12).fill(Color.lime)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func roundButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(enabled ? Color.lime : .white.opacity(0.3))
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .overlay(
                            Circle()
                                .stroke(Color.lime.opacity(enabled ? 0.6 : 0.2), lineWidth: 2)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
