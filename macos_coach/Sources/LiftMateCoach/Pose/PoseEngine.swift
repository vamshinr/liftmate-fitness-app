import AVFoundation
import CoreGraphics
import Foundation
import simd
import Vision

/// Per-frame pose result: 2D for the skeleton overlay, 3D for biomech.
/// 3D positions are in meters relative to the camera (Vision's convention).
struct PoseObservation {
    /// 2D normalized points (x in 0..1 across the image width, y in 0..1 across
    /// the height). y is top-down (UIKit / CoreGraphics convention).
    let landmarks2D: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let confidences2D: [VNHumanBodyPoseObservation.JointName: Float]

    /// 3D positions in meters from the root, x right, y up, z forward.
    let landmarks3D: [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>]
    let imageSize: CGSize
    let timestamp: Date

    var hasPerson: Bool {
        !landmarks2D.isEmpty
    }

    var meanConfidence: Float {
        guard !confidences2D.isEmpty else { return 0 }
        let total = confidences2D.values.reduce(0, +)
        return total / Float(confidences2D.count)
    }
}

/// Runs Vision 2D + 3D pose detection on incoming sample buffers.
/// Uses a background queue so the camera delegate stays unblocked.
final class PoseEngine {
    private let request2D: VNDetectHumanBodyPoseRequest = {
        let r = VNDetectHumanBodyPoseRequest()
        r.revision = VNDetectHumanBodyPoseRequestRevision1
        return r
    }()

    private let request3D: VNDetectHumanBodyPose3DRequest = {
        let r = VNDetectHumanBodyPose3DRequest()
        return r
    }()

    private let queue = DispatchQueue(label: "coach.pose.engine", qos: .userInitiated)
    private var busy = false

    var onObservation: ((PoseObservation) -> Void)?

    func process(sampleBuffer: CMSampleBuffer, mirror: Bool) {
        if busy { return }
        busy = true
        queue.async { [weak self] in
            defer { self?.busy = false }
            self?.runOnce(sampleBuffer: sampleBuffer, mirror: mirror)
        }
    }

    private func runOnce(sampleBuffer: CMSampleBuffer, mirror: Bool) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let handler = VNImageRequestHandler(
            cmSampleBuffer: sampleBuffer,
            orientation: .up,
            options: [:]
        )

        do {
            try handler.perform([request2D, request3D])
        } catch {
            // Vision can throw on bad frames — drop them silently.
            return
        }

        var lm2D: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        var conf2D: [VNHumanBodyPoseObservation.JointName: Float] = [:]
        if let obs = request2D.results?.first {
            for joint in PoseEngine.joints2D {
                if let pt = try? obs.recognizedPoint(joint), pt.confidence > 0.15 {
                    // Vision returns normalized coords with origin bottom-left.
                    // Convert to top-down to match the camera preview's coord
                    // system.
                    var x = CGFloat(pt.location.x)
                    let y = 1.0 - CGFloat(pt.location.y)
                    if mirror { x = 1.0 - x }
                    lm2D[joint] = CGPoint(x: x, y: y)
                    conf2D[joint] = Float(pt.confidence)
                }
            }
        }

        var lm3D: [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>] = [:]
        if let obs = request3D.results?.first {
            for joint in PoseEngine.joints3D {
                if let pt = try? obs.recognizedPoint(joint) {
                    // pt.position is a simd_float4x4 — the translation column
                    // is the joint's position in meters relative to root.
                    let col = pt.position.columns.3
                    var v = SIMD3<Float>(col.x, col.y, col.z)
                    if mirror { v.x = -v.x }
                    lm3D[joint] = v
                }
            }
        }

        let observation = PoseObservation(
            landmarks2D: lm2D,
            confidences2D: conf2D,
            landmarks3D: lm3D,
            imageSize: CGSize(width: width, height: height),
            timestamp: Date()
        )
        DispatchQueue.main.async { [weak self] in
            self?.onObservation?(observation)
        }
    }

    static let joints2D: [VNHumanBodyPoseObservation.JointName] = [
        .nose, .neck,
        .leftShoulder, .rightShoulder,
        .leftElbow, .rightElbow,
        .leftWrist, .rightWrist,
        .leftHip, .rightHip,
        .leftKnee, .rightKnee,
        .leftAnkle, .rightAnkle,
        .root
    ]

    /// 3D joints we actively use for biomech.
    static let joints3D: [VNHumanBodyPose3DObservation.JointName] = [
        .leftShoulder, .rightShoulder,
        .leftHip, .rightHip,
        .leftKnee, .rightKnee,
        .leftAnkle, .rightAnkle,
        .leftWrist, .rightWrist,
        .root, .spine
    ]
}

/// Skeleton bones drawn between paired 2D landmarks.
let skeletonBones: [(VNHumanBodyPoseObservation.JointName,
                     VNHumanBodyPoseObservation.JointName)] = [
    (.leftShoulder, .rightShoulder),
    (.leftShoulder, .leftHip),
    (.rightShoulder, .rightHip),
    (.leftHip, .rightHip),
    (.leftShoulder, .leftElbow),
    (.leftElbow, .leftWrist),
    (.rightShoulder, .rightElbow),
    (.rightElbow, .rightWrist),
    (.leftHip, .leftKnee),
    (.leftKnee, .leftAnkle),
    (.rightHip, .rightKnee),
    (.rightKnee, .rightAnkle),
    (.neck, .nose)
]
