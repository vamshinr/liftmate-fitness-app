import SwiftUI

/// Vertical score bar — fills from the bottom; color shifts with the score.
struct ScoreBar: View {
    let score: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
                RoundedRectangle(cornerRadius: 5)
                    .fill(color)
                    .padding(2)
                    .frame(height: max(2, geo.size.height * heightFraction))
            }
        }
    }

    private var heightFraction: CGFloat {
        max(0.02, min(1.0, CGFloat(score) / 100.0))
    }

    private var color: Color {
        if score >= 80 { return .lime }
        if score >= 60 { return .orange }
        return .red
    }
}
