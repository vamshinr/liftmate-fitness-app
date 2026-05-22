import AVFoundation
import CoreImage
import Foundation

/// AVFoundation capture session that streams CMSampleBuffers to a delegate.
/// On macOS, we use the default front camera; if more than one camera is
/// connected (Continuity Camera or USB cam) the user can flip via the UI.
final class CameraService: NSObject {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "coach.camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var currentInput: AVCaptureDeviceInput?
    private(set) var currentDevice: AVCaptureDevice?

    var onSampleBuffer: ((CMSampleBuffer, AVCaptureDevice.Position) -> Void)?

    /// Returns the list of cameras available on the system.
    func availableDevices() -> [AVCaptureDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices
    }

    func start(preferredPosition: AVCaptureDevice.Position = .front) async throws {
        try await requestCameraAccess()
        sessionQueue.async { [self] in
            session.beginConfiguration()
            session.sessionPreset = .high
            attach(device: pickDevice(position: preferredPosition))
            if !session.outputs.contains(videoOutput) {
                videoOutput.alwaysDiscardsLateVideoFrames = true
                videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String:
                        kCVPixelFormatType_32BGRA
                ]
                videoOutput.setSampleBufferDelegate(
                    self,
                    queue: DispatchQueue(label: "coach.camera.frames")
                )
                if session.canAddOutput(videoOutput) {
                    session.addOutput(videoOutput)
                }
            }
            session.commitConfiguration()
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func flipCamera() {
        sessionQueue.async { [self] in
            let devices = availableDevices()
            guard devices.count > 1, let current = currentDevice else { return }
            let next = devices.first { $0.uniqueID != current.uniqueID } ?? current
            session.beginConfiguration()
            attach(device: next)
            session.commitConfiguration()
        }
    }

    private func attach(device: AVCaptureDevice?) {
        guard let device else { return }
        if let existing = currentInput {
            session.removeInput(existing)
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                currentInput = input
                currentDevice = device
            }
        } catch {
            print("[Camera] attach failed: \(error)")
        }
    }

    private func pickDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let devices = availableDevices()
        if let match = devices.first(where: { $0.position == position }) {
            return match
        }
        return devices.first
    }

    private func requestCameraAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { throw CameraError.permissionDenied }
        case .denied, .restricted:
            throw CameraError.permissionDenied
        @unknown default:
            throw CameraError.permissionDenied
        }
    }
}

enum CameraError: Error {
    case permissionDenied
    case noCameraAvailable
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let position = currentDevice?.position ?? .unspecified
        onSampleBuffer?(sampleBuffer, position)
    }
}
