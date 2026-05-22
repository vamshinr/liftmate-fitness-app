import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// 2D landmark in normalized image coords (top-left origin, 0..1 range).
class Pose2DLandmark {
  final double x;
  final double y;
  final double confidence;
  const Pose2DLandmark(this.x, this.y, this.confidence);
}

/// 3D landmark in meters, root-centered. y is up, x is right, z is forward.
class Pose3DLandmark {
  final double x;
  final double y;
  final double z;
  const Pose3DLandmark(this.x, this.y, this.z);
}

/// Per-frame pose detection output.
class Pose3DResult {
  final Map<String, Pose2DLandmark> landmarks2D;
  final Map<String, Pose3DLandmark> landmarks3D;
  const Pose3DResult({
    required this.landmarks2D,
    required this.landmarks3D,
  });

  bool get hasPerson => landmarks2D.isNotEmpty;

  /// Average likelihood across the 2D landmarks. Used as a framing signal.
  double get meanConfidence {
    if (landmarks2D.isEmpty) return 0;
    final sum = landmarks2D.values.fold<double>(0, (s, l) => s + l.confidence);
    return sum / landmarks2D.length;
  }
}

/// Capability descriptor returned by `isAvailable()`.
class Pose3DCapabilities {
  final bool has2D;
  final bool has3D;
  const Pose3DCapabilities({required this.has2D, required this.has3D});
  bool get isPlatformReady => has2D;
}

/// Bridge to the native Vision-based pose detector on iOS.
///
/// On iOS the native side runs `VNDetectHumanBodyPoseRequest` (2D) and,
/// when iOS ≥ 17, also `VNDetectHumanBodyPose3DRequest` (real meters).
/// On Android the channel doesn't exist; consumers should fall back to
/// ML Kit via the existing PoseService.
class Pose3DService {
  static const _channel = MethodChannel('app.liftmate/pose3d');

  static Pose3DCapabilities? _cachedCaps;

  /// Returns null on non-iOS platforms.
  static Future<Pose3DCapabilities?> capabilities() async {
    if (!Platform.isIOS) return null;
    final cached = _cachedCaps;
    if (cached != null) return cached;
    try {
      final map = await _channel
          .invokeMapMethod<String, dynamic>('isAvailable');
      final caps = Pose3DCapabilities(
        has2D: (map?['has2D'] as bool?) ?? false,
        has3D: (map?['has3D'] as bool?) ?? false,
      );
      _cachedCaps = caps;
      return caps;
    } catch (_) {
      return null;
    }
  }

  /// Run detection on a single BGRA frame. The bytes/size/stride match
  /// what Flutter's `camera` plugin emits for iOS BGRA streams.
  ///
  /// Returns null if the platform channel is unavailable (Android, missing
  /// plugin) or if the call throws. Returns an empty `Pose3DResult` if a
  /// frame is processed but no person is detected.
  static Future<Pose3DResult?> detect({
    required Uint8List bytes,
    required int width,
    required int height,
    required int bytesPerRow,
    required int rotationDegrees,
    required bool mirror,
  }) async {
    if (!Platform.isIOS) return null;
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('detect', {
        'bytes': bytes,
        'width': width,
        'height': height,
        'bytesPerRow': bytesPerRow,
        'rotation': rotationDegrees,
        'mirror': mirror,
      });
      if (map == null) return null;
      final lm2D = <String, Pose2DLandmark>{};
      final raw2D = map['landmarks2D'] as Map?;
      if (raw2D != null) {
        raw2D.forEach((k, v) {
          final m = v as Map;
          lm2D[k as String] = Pose2DLandmark(
            (m['x'] as num).toDouble(),
            (m['y'] as num).toDouble(),
            (m['c'] as num).toDouble(),
          );
        });
      }
      final lm3D = <String, Pose3DLandmark>{};
      final raw3D = map['landmarks3D'] as Map?;
      if (raw3D != null) {
        raw3D.forEach((k, v) {
          final m = v as Map;
          lm3D[k as String] = Pose3DLandmark(
            (m['x'] as num).toDouble(),
            (m['y'] as num).toDouble(),
            (m['z'] as num).toDouble(),
          );
        });
      }
      return Pose3DResult(landmarks2D: lm2D, landmarks3D: lm3D);
    } catch (_) {
      return null;
    }
  }
}

/// Apple Vision body-pose joint names — keep in sync with Pose3DPlugin.swift.
/// Lowercase JSON-friendly. Use these as keys when reading [Pose3DResult].
class VisionJoints {
  // 2D + 3D shared
  static const leftShoulder = 'left_shoulder_joint';
  static const rightShoulder = 'right_shoulder_joint';
  static const leftHip = 'left_hip_joint';
  static const rightHip = 'right_hip_joint';
  static const leftKnee = 'left_knee_joint';
  static const rightKnee = 'right_knee_joint';
  static const leftAnkle = 'left_ankle_joint';
  static const rightAnkle = 'right_ankle_joint';
  static const leftWrist = 'left_wrist_joint';
  static const rightWrist = 'right_wrist_joint';
  static const root = 'root';
  static const spine = 'spine_7_joint';
  // 2D only
  static const leftElbow = 'left_elbow_joint';
  static const rightElbow = 'right_elbow_joint';
  static const nose = 'head_joint';
  static const neck = 'neck_1_joint';
}
