import Flutter
import Foundation
import UIKit
import Vision

/// Bridges Flutter's camera image stream to Apple's Vision body-pose APIs.
/// Returns 2D landmarks (for the on-screen skeleton overlay) and, on
/// iOS 17+, real-world 3D landmarks in meters (for biomechanics).
///
/// Channel name: `app.liftmate/pose3d`
///
/// Methods:
///  - `isAvailable() -> {has2D: Bool, has3D: Bool}` — call once at startup.
///  - `detect(bytes, width, height, bytesPerRow, rotation, mirror) ->
///     {landmarks2D: {...}, landmarks3D: {...}}`
@objc public class Pose3DPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "app.liftmate/pose3d",
            binaryMessenger: registrar.messenger()
        )
        let instance = Pose3DPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    private let queue = DispatchQueue(label: "app.liftmate.pose3d", qos: .userInitiated)
    private var busy = false

    // MARK: - FlutterPlugin

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable":
            var has3D = false
            if #available(iOS 17.0, *) { has3D = true }
            result(["has2D": true, "has3D": has3D])
        case "detect":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "ARGS", message: "Missing args", details: nil))
                return
            }
            // If a detection is already in flight, drop this frame.
            if busy { result(nil); return }
            busy = true
            queue.async { [weak self] in
                defer {
                    DispatchQueue.main.async { self?.busy = false }
                }
                let response = self?.runDetection(args: args)
                DispatchQueue.main.async { result(response) }
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Detection

    private func runDetection(args: [String: Any]) -> [String: Any]? {
        guard
            let typedData = args["bytes"] as? FlutterStandardTypedData,
            let width = args["width"] as? Int,
            let height = args["height"] as? Int,
            let bytesPerRow = args["bytesPerRow"] as? Int
        else { return nil }
        let bytes = typedData.data
        let mirror = (args["mirror"] as? Bool) ?? false
        let rotationDeg = (args["rotation"] as? Int) ?? 0

        guard let pixelBuffer = makeBGRAPixelBuffer(
            data: bytes,
            width: width,
            height: height,
            srcBytesPerRow: bytesPerRow
        ) else { return nil }

        let orientation = orientation(forRotationDegrees: rotationDeg, mirror: mirror)
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )

        let request2D = VNDetectHumanBodyPoseRequest()
        request2D.revision = VNDetectHumanBodyPoseRequestRevision1

        var requests: [VNRequest] = [request2D]
        var request3D: Any? = nil
        if #available(iOS 17.0, *) {
            let r3D = VNDetectHumanBodyPose3DRequest()
            request3D = r3D
            requests.append(r3D)
        }

        do {
            try handler.perform(requests)
        } catch {
            return nil
        }

        var output: [String: Any] = [:]

        if let obs = request2D.results?.first {
            output["landmarks2D"] = encode2D(observation: obs, mirror: mirror)
        }
        if #available(iOS 17.0, *), let r3D = request3D as? VNDetectHumanBodyPose3DRequest,
           let obs = r3D.results?.first {
            output["landmarks3D"] = encode3D(observation: obs, mirror: mirror)
        }
        return output
    }

    // MARK: - Encoders

    private func encode2D(
        observation: VNHumanBodyPoseObservation,
        mirror: Bool
    ) -> [String: [String: Double]] {
        var out: [String: [String: Double]] = [:]
        for joint in Self.joints2D {
            guard let point = try? observation.recognizedPoint(joint),
                  point.confidence > 0.15 else { continue }
            // Vision: bottom-left origin, normalized 0..1. We re-frame to
            // top-down because every other UI library on the planet does.
            var x = Double(point.location.x)
            let y = 1.0 - Double(point.location.y)
            if mirror { x = 1.0 - x }
            out[joint.rawValue.rawValue] = [
                "x": x,
                "y": y,
                "c": Double(point.confidence)
            ]
        }
        return out
    }

    @available(iOS 17.0, *)
    private func encode3D(
        observation: VNHumanBodyPose3DObservation,
        mirror: Bool
    ) -> [String: [String: Double]] {
        var out: [String: [String: Double]] = [:]
        for joint in Self.joints3D {
            guard let point = try? observation.recognizedPoint(joint) else { continue }
            // The translation column of the 4x4 model matrix gives the joint's
            // 3D position in meters relative to the root.
            let col = point.position.columns.3
            var x = Double(col.x)
            let yVal = Double(col.y)
            let zVal = Double(col.z)
            if mirror { x = -x }
            out[joint.rawValue.rawValue] = [
                "x": x,
                "y": yVal,
                "z": zVal
            ]
        }
        return out
    }

    // MARK: - Helpers

    private func makeBGRAPixelBuffer(
        data: Data,
        width: Int,
        height: Int,
        srcBytesPerRow: Int
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:]]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pb = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let dest = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let destBytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        data.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            guard let srcPtr = src.baseAddress else { return }
            if destBytesPerRow == srcBytesPerRow {
                memcpy(dest, srcPtr, data.count)
            } else {
                // Source stride doesn't match the buffer's. Copy row-by-row.
                let rowBytes = min(srcBytesPerRow, destBytesPerRow)
                for y in 0..<height {
                    let srcRow = srcPtr.advanced(by: y * srcBytesPerRow)
                    let destRow = dest.advanced(by: y * destBytesPerRow)
                    memcpy(destRow, srcRow, rowBytes)
                }
            }
        }
        return pb
    }

    private func orientation(
        forRotationDegrees deg: Int,
        mirror: Bool
    ) -> CGImagePropertyOrientation {
        switch (deg, mirror) {
        case (0, false): return .up
        case (90, false): return .right
        case (180, false): return .down
        case (270, false): return .left
        case (0, true): return .upMirrored
        case (90, true): return .rightMirrored
        case (180, true): return .downMirrored
        case (270, true): return .leftMirrored
        default: return .up
        }
    }

    // MARK: - Joint sets

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

    @available(iOS 17.0, *)
    static var joints3D: [VNHumanBodyPose3DObservation.JointName] {
        return [
            .leftShoulder, .rightShoulder,
            .leftHip, .rightHip,
            .leftKnee, .rightKnee,
            .leftAnkle, .rightAnkle,
            .leftWrist, .rightWrist,
            .root, .spine
        ]
    }
}
