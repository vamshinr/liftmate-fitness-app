import AVFoundation
import CoreGraphics
import Foundation
import SwiftUI
import Vision

/// Top-level state for the live coach view. Owns the camera, pose engine,
/// rules engine, and voice — exposes observable properties to the SwiftUI
/// layer.
@MainActor
final class CoachViewModel: ObservableObject {
    // Camera + pose pipeline
    let camera = CameraService()
    private let pose = PoseEngine()
    private let rules = BiomechEngine()
    private let voice = VoiceCoach()

    // Published UI state
    @Published var lift: Lift = .squat
    @Published var phase: RepPhase = .standing
    @Published var reps: Int = 0
    @Published var score: Int = 100
    @Published var fps: Int = 0
    @Published var voiceOn: Bool = true
    @Published var statusMessage: String = "Initializing camera…"
    @Published var framingMessage: String = ""
    @Published var liveCue: String = ""
    @Published var liveCueColor: Color = .green
    @Published var skeletonLandmarks2D: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    @Published var imageSize: CGSize = .zero
    @Published var isMirrored: Bool = false
    @Published var availableCameraCount: Int = 1
    @Published var isRunning: Bool = false

    // FPS rolling window
    private var detectTimestamps: [Date] = []

    // Last spoken cue dedup is in VoiceCoach.
    private var lastSpokenCue: String = ""

    var session: AVCaptureSession { camera.session }

    func start() async {
        availableCameraCount = camera.availableDevices().count
        camera.onSampleBuffer = { [weak self] buffer, position in
            self?.pose.process(
                sampleBuffer: buffer,
                mirror: position == .front
            )
        }
        pose.onObservation = { [weak self] obs in
            self?.handle(observation: obs)
        }
        do {
            try await camera.start(preferredPosition: .front)
            isRunning = true
            statusMessage = "Step into frame to begin."
        } catch {
            statusMessage = "Camera permission denied — grant access in Settings."
        }
        rules.setLift(lift)
    }

    func stop() {
        camera.stop()
        voice.stop()
        isRunning = false
    }

    func toggleVoice() {
        voiceOn.toggle()
        voice.isMuted = !voiceOn
    }

    func flipCamera() {
        camera.flipCamera()
    }

    func cycleLift() {
        // For now we only really tune squat; deadlift/OHP use the same rules
        // but the cue language adapts via the rules engine eventually.
        let all = Lift.allCases
        let idx = all.firstIndex(of: lift) ?? 0
        lift = all[(idx + 1) % all.count]
        rules.setLift(lift)
        resetSet()
    }

    func resetSet() {
        rules.reset()
        phase = .standing
        reps = 0
        score = 100
        statusMessage = "Ready when you are."
        liveCue = ""
        framingMessage = ""
    }

    private func handle(observation obs: PoseObservation) {
        // FPS
        let now = Date()
        detectTimestamps.append(now)
        detectTimestamps.removeAll(where: { now.timeIntervalSince($0) > 1.0 })
        fps = detectTimestamps.count

        skeletonLandmarks2D = obs.landmarks2D
        imageSize = obs.imageSize
        isMirrored = (camera.currentDevice?.position == .front)

        // Framing first.
        framingMessage = evaluateFraming(obs)
        if !framingMessage.isEmpty {
            liveCue = ""
            statusMessage = framingMessage
            return
        }

        // Rules → live cue + phase + score update.
        let cue = rules.evaluate(obs)
        phase = rules.phase
        reps = rules.reps
        score = rules.score

        if let cue {
            liveCue = cue.text
            liveCueColor = cue.color
            // Only speak corrective cues (color != green) to avoid being chatty.
            if cue.color == .red || cue.color == .orange {
                speak(cue.text)
            }
        }
        if let report = rules.lastReport, let repCue = report.cue {
            speak(repCue)
            statusMessage = "Rep \(reps): \(repCue)"
            rules.lastReport = nil
        } else if rules.lastReport != nil {
            speak("Clean rep \(reps).")
            statusMessage = "Clean rep \(reps)."
            rules.lastReport = nil
        } else {
            switch phase {
            case .standing:   statusMessage = "Ready when you are."
            case .descending: statusMessage = "Descending — control it."
            case .atBottom:   statusMessage = "At bottom — drive up."
            case .ascending:  statusMessage = "Ascending — squeeze."
            }
        }
    }

    private func speak(_ text: String) {
        voice.say(text)
        lastSpokenCue = text
    }

    private func evaluateFraming(_ obs: PoseObservation) -> String {
        let req: [VNHumanBodyPoseObservation.JointName] = [
            .leftShoulder, .rightShoulder,
            .leftHip, .rightHip,
            .leftKnee, .rightKnee,
            .leftAnkle, .rightAnkle
        ]
        var seen = 0
        for j in req where obs.landmarks2D[j] != nil { seen += 1 }
        if seen < Int(Double(req.count) * 0.75) {
            return "Step into frame"
        }
        if obs.meanConfidence < 0.35 {
            return "More light, please"
        }
        // Side-on check — shoulders should be mostly stacked when viewed from the side.
        if let ls = obs.landmarks2D[.leftShoulder], let rs = obs.landmarks2D[.rightShoulder] {
            let dx = abs(ls.x - rs.x)
            if dx > 0.18 { return "Stand side-on, full body" }
        }
        return ""
    }
}
