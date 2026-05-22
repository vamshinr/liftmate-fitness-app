import 'dart:math' as math;

import 'pose3d_service.dart';

/// Real-world biomech measurements derived from Vision's 3D landmarks.
/// Everything here works in meters and degrees — no pixel ratios — so the
/// thresholds map cleanly onto coaching intuition.
class Biomech3D {
  /// Vertical distance (in meters) between hip and knee, signed. Negative
  /// values mean the hip is below the knee — i.e. proper squat depth.
  static double? hipBelowKneeMeters(Pose3DResult result) {
    final lHip = result.landmarks3D[VisionJoints.leftHip];
    final rHip = result.landmarks3D[VisionJoints.rightHip];
    final lKnee = result.landmarks3D[VisionJoints.leftKnee];
    final rKnee = result.landmarks3D[VisionJoints.rightKnee];
    if (lHip == null || rHip == null || lKnee == null || rKnee == null) {
      return null;
    }
    final hipY = (lHip.y + rHip.y) / 2;
    final kneeY = (lKnee.y + rKnee.y) / 2;
    return hipY - kneeY;
  }

  /// Forward torso lean, in degrees from vertical. 0° = upright,
  /// 90° = horizontal. Measured in the sagittal plane (y-z).
  static double? torsoLeanDegrees(Pose3DResult result) {
    final lSh = result.landmarks3D[VisionJoints.leftShoulder];
    final rSh = result.landmarks3D[VisionJoints.rightShoulder];
    final lHip = result.landmarks3D[VisionJoints.leftHip];
    final rHip = result.landmarks3D[VisionJoints.rightHip];
    if (lSh == null || rSh == null || lHip == null || rHip == null) {
      return null;
    }
    final shY = (lSh.y + rSh.y) / 2;
    final shZ = (lSh.z + rSh.z) / 2;
    final hipY = (lHip.y + rHip.y) / 2;
    final hipZ = (lHip.z + rHip.z) / 2;
    final dy = shY - hipY;
    final dz = shZ - hipZ;
    if (dy.abs() < 1e-4) return 90;
    return (math.atan2(dz.abs(), dy.abs()) * 180 / math.pi).abs();
  }

  /// Knee valgus angle (degrees): how far each knee deviates from the
  /// hip→ankle line in the frontal plane (x-y). Returns the larger of the
  /// two sides — that's the one you'd cue.
  static double? maxKneeValgusDegrees(Pose3DResult result) {
    double? left = _valgusOneSide(
      result.landmarks3D[VisionJoints.leftHip],
      result.landmarks3D[VisionJoints.leftKnee],
      result.landmarks3D[VisionJoints.leftAnkle],
    );
    double? right = _valgusOneSide(
      result.landmarks3D[VisionJoints.rightHip],
      result.landmarks3D[VisionJoints.rightKnee],
      result.landmarks3D[VisionJoints.rightAnkle],
    );
    if (left == null && right == null) return null;
    return math.max(left ?? 0, right ?? 0);
  }

  static double? _valgusOneSide(
    Pose3DLandmark? hip,
    Pose3DLandmark? knee,
    Pose3DLandmark? ankle,
  ) {
    if (hip == null || knee == null || ankle == null) return null;
    // Project to frontal plane (x-y), measure angle between hip→ankle line
    // and hip→knee line.
    final lineX = ankle.x - hip.x;
    final lineY = ankle.y - hip.y;
    final kneeX = knee.x - hip.x;
    final kneeY = knee.y - hip.y;
    final lineLen = math.sqrt(lineX * lineX + lineY * lineY);
    final kneeLen = math.sqrt(kneeX * kneeX + kneeY * kneeY);
    if (lineLen < 1e-4 || kneeLen < 1e-4) return 0;
    final dot = lineX * kneeX + lineY * kneeY;
    final cross = lineX * kneeY - lineY * kneeX;
    final ang = math.atan2(cross.abs(), dot) * 180 / math.pi;
    return ang.abs();
  }

  /// Hip lateral shift (meters): absolute difference in x between left and
  /// right hip positions, normalized by their average y span. Useful for
  /// flagging unilateral collapse on the ascent.
  static double? hipLateralShiftMeters(Pose3DResult result) {
    final lHip = result.landmarks3D[VisionJoints.leftHip];
    final rHip = result.landmarks3D[VisionJoints.rightHip];
    if (lHip == null || rHip == null) return null;
    return (lHip.x - rHip.x).abs();
  }
}

