import Foundation
import simd
import SwiftUI
import Vision

/// Phase of a rep — drives the HUD and scoring transitions.
enum RepPhase {
    case standing, descending, atBottom, ascending

    var label: String {
        switch self {
        case .standing:   return "Standing"
        case .descending: return "Descending"
        case .atBottom:   return "At Bottom"
        case .ascending:  return "Ascending"
        }
    }
}

/// Lift we're currently coaching.
enum Lift: String, CaseIterable {
    case squat = "Squat"
    case deadlift = "Deadlift / RDL"
    case overheadPress = "Overhead Press"
}

struct LiveCue {
    let text: String
    let color: Color
}

/// Outcome of a completed rep — used to update the running score.
struct RepReport {
    let depthMeters: Float       // hip below knee (negative = above) at bottom
    let maxLeanDeg: Float        // peak forward torso lean
    let maxKneeValgusDeg: Float  // peak knee inward collapse
    let scoreDeduction: Int
    let cue: String?
}

/// 3D rules engine. Stateful — tracks phase and per-rep peaks. Reset() between
/// sets. Consumes Vision's 3D observations in meters.
final class BiomechEngine {
    private(set) var phase: RepPhase = .standing
    private(set) var reps: Int = 0
    private(set) var score: Int = 100

    private var lift: Lift = .squat

    // 3D phase tracking: hip Y in meters (Vision: y is vertical up)
    private var hipBaselineY: Float?
    private var prevHipY: Float?

    // Per-rep peaks
    private var minHipYThisRep: Float = .infinity
    private var maxLeanThisRep: Float = 0
    private var maxValgusThisRep: Float = 0

    var lastReport: RepReport?

    func setLift(_ lift: Lift) {
        self.lift = lift
    }

    func reset() {
        phase = .standing
        reps = 0
        score = 100
        hipBaselineY = nil
        prevHipY = nil
        resetRepPeaks()
        lastReport = nil
    }

    private func resetRepPeaks() {
        minHipYThisRep = .infinity
        maxLeanThisRep = 0
        maxValgusThisRep = 0
    }

    /// Run rules over one 3D observation. Returns a live cue to display.
    /// May transition `phase` and increment `reps`/`score` on completion.
    func evaluate(_ obs: PoseObservation) -> LiveCue? {
        let lm = obs.landmarks3D
        guard
            let lHip = lm[.leftHip],
            let rHip = lm[.rightHip],
            let lKnee = lm[.leftKnee],
            let rKnee = lm[.rightKnee],
            let lAnkle = lm[.leftAnkle],
            let rAnkle = lm[.rightAnkle],
            let lShoulder = lm[.leftShoulder],
            let rShoulder = lm[.rightShoulder]
        else {
            return nil
        }

        let hip = (lHip + rHip) * 0.5
        let knee = (lKnee + rKnee) * 0.5
        let shoulder = (lShoulder + rShoulder) * 0.5

        let leanDeg = forwardTorsoLeanDegrees(shoulder: shoulder, hip: hip)
        let valgusDeg = max(
            kneeValgusDegrees(hip: lHip, knee: lKnee, ankle: lAnkle),
            kneeValgusDegrees(hip: rHip, knee: rKnee, ankle: rAnkle)
        )

        if leanDeg > maxLeanThisRep { maxLeanThisRep = leanDeg }
        if valgusDeg > maxValgusThisRep { maxValgusThisRep = valgusDeg }

        // Phase machine driven off hip vertical position.
        let hipY = hip.y
        if hipBaselineY == nil { hipBaselineY = hipY }
        let baseline = hipBaselineY!
        let drop = baseline - hipY  // positive when hip drops (y is up)
        let prev = prevHipY ?? hipY
        let velocity = hipY - prev  // positive = rising, negative = dropping
        prevHipY = hipY

        if hipY < minHipYThisRep { minHipYThisRep = hipY }

        let hipBelowKnee = hip.y < knee.y // y is up; lower hip => smaller y

        // Update phase
        switch phase {
        case .standing:
            if drop > 0.06 && velocity < -0.01 {
                phase = .descending
            }
        case .descending:
            if abs(velocity) < 0.005 && drop > 0.08 {
                phase = .atBottom
            } else if velocity > 0.01 {
                phase = .ascending
            }
        case .atBottom:
            if velocity > 0.01 {
                phase = .ascending
            }
        case .ascending:
            if drop < 0.03 {
                completeRep(kneeY: knee.y)
            }
        }

        // Slowly track baseline up to absorb small camera shifts.
        hipBaselineY = baseline * 0.985 + hipY * 0.015

        // Build a live cue based on phase + measurements.
        return phaseCue(phase: phase, hipBelowKnee: hipBelowKnee, leanDeg: leanDeg, valgusDeg: valgusDeg)
    }

    private func completeRep(kneeY: Float) {
        reps += 1
        // Depth: hip Y at bottom relative to knee Y. Negative means hip went
        // below knee. Lower is better for a squat.
        let depthMeters = minHipYThisRep - kneeY
        var deduction = 0
        var cue: String? = nil
        if depthMeters > 0 { // hip didn't reach knee
            deduction += 15
            cue = "Go deeper — hip above knee."
        }
        if maxLeanThisRep > 35 {
            deduction += 12
            cue = cue ?? "Chest up — less forward lean."
        }
        if maxValgusThisRep > 14 {
            deduction += 10
            cue = cue ?? "Knees out — track over toes."
        }
        if deduction == 0 {
            score = min(100, score + 2)
        } else {
            score = max(0, score - deduction)
        }
        lastReport = RepReport(
            depthMeters: depthMeters,
            maxLeanDeg: maxLeanThisRep,
            maxKneeValgusDeg: maxValgusThisRep,
            scoreDeduction: deduction,
            cue: cue
        )
        resetRepPeaks()
    }

    private func phaseCue(
        phase: RepPhase,
        hipBelowKnee: Bool,
        leanDeg: Float,
        valgusDeg: Float
    ) -> LiveCue? {
        switch phase {
        case .standing:
            return LiveCue(text: "Ready when you are.", color: .white)
        case .descending:
            if leanDeg > 35 {
                return LiveCue(text: "Chest up — stop folding.", color: .red)
            }
            if valgusDeg > 14 {
                return LiveCue(text: "Knees out — track over toes.", color: .red)
            }
            return LiveCue(text: "Down — control the eccentric.", color: .white)
        case .atBottom:
            if !hipBelowKnee {
                return LiveCue(text: "Go deeper — hip below knee.", color: .orange)
            }
            if leanDeg > 30 {
                return LiveCue(text: "Brace hard, chest proud.", color: .red)
            }
            return LiveCue(text: "Solid depth — drive up.", color: .green)
        case .ascending:
            if valgusDeg > 12 {
                return LiveCue(text: "Spread the floor with your feet.", color: .orange)
            }
            return LiveCue(text: "Stand tall, squeeze glutes.", color: .green)
        }
    }
}

// MARK: - 3D geometry helpers

/// Angle of the torso (shoulder-hip line) from vertical, in degrees.
func forwardTorsoLeanDegrees(shoulder: SIMD3<Float>, hip: SIMD3<Float>) -> Float {
    let vec = shoulder - hip
    // Lean in the sagittal plane = angle from vertical (y axis) projected onto y/z.
    let v = SIMD2<Float>(vec.z, vec.y)
    let lengthSq = simd_length_squared(v)
    if lengthSq < 1e-6 { return 0 }
    let angleRad = atan2(abs(v.x), v.y)
    return abs(angleRad) * 180.0 / .pi
}

/// Knee valgus: how far the knee deviates inward of the hip→ankle line,
/// expressed as an angle in degrees. Positive = inward (valgus).
func kneeValgusDegrees(
    hip: SIMD3<Float>,
    knee: SIMD3<Float>,
    ankle: SIMD3<Float>
) -> Float {
    // Project onto the frontal plane (x-y). Compute the signed angle of
    // knee from the hip→ankle line on the medial side.
    let line = SIMD2<Float>(ankle.x, ankle.y) - SIMD2<Float>(hip.x, hip.y)
    let toKnee = SIMD2<Float>(knee.x, knee.y) - SIMD2<Float>(hip.x, hip.y)
    let lineLen = simd_length(line)
    let kneeLen = simd_length(toKnee)
    if lineLen < 1e-6 || kneeLen < 1e-6 { return 0 }
    let cross = line.x * toKnee.y - line.y * toKnee.x
    let dot = simd_dot(line, toKnee)
    let angleRad = atan2(abs(cross), dot)
    return Float(angleRad) * 180.0 / .pi
}
