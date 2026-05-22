import SwiftUI

/// Compact monospace HUD bar with lift / reps / score / fps / voice toggle.
/// Mirrors the look of the reference squat-coach demo.
struct HUDBar: View {
    let lift: Lift
    let phase: String
    let reps: Int
    let score: Int
    let fps: Int
    let voiceOn: Bool
    let onToggleVoice: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                chip(text: lift.rawValue.uppercased(), color: .lime)
                sep
                chip(text: "Reps \(reps)", color: .white)
                sep
                chip(text: "Score \(score)", color: scoreColor)
                sep
                chip(text: "\(fps) fps", color: fps >= 20 ? .white.opacity(0.7) : .orange)
                sep
                Button(action: onToggleVoice) {
                    chip(
                        text: "Voice \(voiceOn ? "ON" : "OFF")",
                        color: voiceOn ? .cyan : .white.opacity(0.5)
                    )
                }
                .buttonStyle(.plain)
            }
            Text("Phase: \(phase)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.lime)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.lime.opacity(0.4), lineWidth: 1)
                )
        )
    }

    private var sep: some View {
        Text("|")
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.white.opacity(0.25))
    }

    private func chip(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
    }

    private var scoreColor: Color {
        if score >= 80 { return .lime }
        if score >= 60 { return .orange }
        return .red
    }
}

extension Color {
    static let lime = Color(red: 0.81, green: 0.99, blue: 0.19)
}
