import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:image/image.dart' as img;

import '../models/pose_data.dart';

class PoseService {
  static final PoseDetector _detector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.single,
      model: PoseDetectionModel.base,
    ),
  );

  // ML Kit PoseLandmarkType enum indices
  static const int _nose = 0;
  static const int _leftShoulder = 11;
  static const int _rightShoulder = 12;
  static const int _leftElbow = 13;
  static const int _rightElbow = 14;
  static const int _leftWrist = 15;
  static const int _rightWrist = 16;
  static const int _leftHip = 23;
  static const int _rightHip = 24;
  static const int _leftKnee = 25;
  static const int _rightKnee = 26;
  static const int _leftAnkle = 27;
  static const int _rightAnkle = 28;

  // ---- Public API ----

  static Future<PoseFrame> detect(Uint8List jpegBytes) async {
    final decoded = img.decodeJpg(jpegBytes);
    final width = decoded?.width ?? 0;
    final height = decoded?.height ?? 0;

    final tmp = await File(
      '${Directory.systemTemp.path}/lm_${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(99999)}.jpg',
    ).writeAsBytes(jpegBytes);

    try {
      final inputImage = InputImage.fromFilePath(tmp.path);
      final poses = await _detector.processImage(inputImage);
      if (poses.isEmpty) {
        return PoseFrame(
          imageBytes: jpegBytes,
          imageWidth: width,
          imageHeight: height,
          landmarks: const {},
          avgLikelihood: 0,
          hasPerson: false,
        );
      }
      final landmarks = <int, Landmark>{};
      double total = 0;
      int n = 0;
      poses.first.landmarks.forEach((type, lm) {
        landmarks[type.index] = Landmark(
          x: lm.x,
          y: lm.y,
          z: lm.z,
          likelihood: lm.likelihood,
        );
        total += lm.likelihood;
        n += 1;
      });
      return PoseFrame(
        imageBytes: jpegBytes,
        imageWidth: width,
        imageHeight: height,
        landmarks: landmarks,
        avgLikelihood: n > 0 ? total / n : 0,
        hasPerson: true,
      );
    } finally {
      // ignore: empty_catches
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }

  static Future<List<PoseFrame>> detectAll(List<Uint8List> frames) async {
    final out = <PoseFrame>[];
    for (final b in frames) {
      out.add(await detect(b));
    }
    return out;
  }

  static QualityReport assessQuality(
    List<PoseFrame> frames,
    String expectedAngle,
  ) {
    if (frames.isEmpty) {
      return const QualityReport(
        usable: false,
        blurScore: 0,
        brightnessScore: 0,
        framingScore: 0,
        angleScore: 0,
        subjectVisibilityScore: 0,
        issues: ['no_frames'],
        userMessage: 'No frames captured. Try again.',
      );
    }
    // Representative frame for image-pixel checks: middle frame
    final mid = frames[frames.length ~/ 2];

    final blurVar = _laplacianVariance(mid.imageBytes);
    final blurScore = ((blurVar / 200.0) * 100).clamp(0, 100).toInt();

    final brightness = _averageBrightness(mid.imageBytes);
    final brightnessScore = _scoreBand(
      brightness,
      idealMin: 0.25,
      idealMax: 0.75,
      hardMin: 0.05,
      hardMax: 0.95,
    );

    final avgVis = frames.map((f) => f.avgLikelihood).reduce((a, b) => a + b) /
        frames.length;
    final visScore = (avgVis * 100).clamp(0, 100).toInt();

    final framingScores = frames.map(_framingScore).toList();
    final framingScore =
        framingScores.reduce((a, b) => a + b) ~/ framingScores.length;

    final angleScore = _angleMatches(frames, expectedAngle);

    final issues = <String>[];
    if (blurScore < 50) issues.add('blur');
    if (brightnessScore < 50) issues.add('lighting');
    if (visScore < 55) issues.add('subject_not_visible');
    if (framingScore < 55) issues.add('framing');
    if (angleScore < 55) issues.add('angle');

    // We require subject visible AND framing OK to even try. Other issues are
    // soft warnings that lower confidence but don't block.
    final usable = visScore >= 55 && framingScore >= 55 && blurScore >= 30;

    final messages = <String, String>{
      'blur': 'photos look blurry — hold the camera steadier',
      'lighting': 'lighting is off — find a brighter, more even spot',
      'subject_not_visible':
          "we couldn't see your whole body clearly — step into frame",
      'framing': 'parts of your body were out of frame — step back',
      'angle': 'camera angle is off — check the setup diagram',
    };
    final userMessage = issues.isEmpty
        ? 'Frames look good.'
        : 'Quick retake — ${issues.map((i) => messages[i] ?? i).join('; ')}.';

    return QualityReport(
      usable: usable,
      blurScore: blurScore,
      brightnessScore: brightnessScore,
      framingScore: framingScore,
      angleScore: angleScore,
      subjectVisibilityScore: visScore,
      issues: issues,
      userMessage: userMessage,
    );
  }

  static BiomechSummary computeBiomech(List<PoseFrame> frames, String lift) {
    final visible = frames.where((f) => f.hasPerson).toList();
    if (visible.isEmpty) {
      return BiomechSummary(
        lift: lift,
        metrics: const {},
        faults: const [],
        sideUsed: 'unknown',
      );
    }
    final side = _dominantSide(visible);
    final metrics = <String, double>{};
    final faults = <FaultScore>[];
    final key = lift.toLowerCase();

    if (key == 'squat') {
      _computeSquat(visible, side, metrics, faults);
    } else if (key.startsWith('deadlift') || key.contains('rdl')) {
      _computeDeadlift(visible, side, metrics, faults);
    } else if (key.startsWith('bench')) {
      _computeBench(visible, side, metrics, faults);
    } else if (key.startsWith('overhead') || key == 'ohp') {
      _computeOhp(visible, side, metrics, faults);
    } else if (key == 'row') {
      _computeRow(visible, side, metrics, faults);
    } else if (key.contains('pulldown')) {
      _computeLatPulldown(visible, metrics, faults);
    } else if (key.contains('push')) {
      _computePushUp(visible, side, metrics, faults);
    } else if (key.contains('lunge') || key.contains('split')) {
      _computeLunge(visible, side, metrics, faults);
    }

    return BiomechSummary(
      lift: lift,
      metrics: metrics,
      faults: faults,
      sideUsed: side,
    );
  }

  // ---- Image-pixel quality helpers ----

  static double _laplacianVariance(Uint8List jpegBytes) {
    final decoded = img.decodeJpg(jpegBytes);
    if (decoded == null) return 0;
    final small = img.copyResize(decoded, width: 320);
    final gray = img.grayscale(small);
    double sum = 0, sumSq = 0;
    int n = 0;
    for (int y = 1; y < gray.height - 1; y++) {
      for (int x = 1; x < gray.width - 1; x++) {
        final c = gray.getPixel(x, y).r.toDouble();
        final l = gray.getPixel(x - 1, y).r.toDouble();
        final r = gray.getPixel(x + 1, y).r.toDouble();
        final u = gray.getPixel(x, y - 1).r.toDouble();
        final d = gray.getPixel(x, y + 1).r.toDouble();
        final lap = 4 * c - l - r - u - d;
        sum += lap;
        sumSq += lap * lap;
        n += 1;
      }
    }
    if (n == 0) return 0;
    final mean = sum / n;
    return (sumSq / n) - (mean * mean);
  }

  static double _averageBrightness(Uint8List jpegBytes) {
    final decoded = img.decodeJpg(jpegBytes);
    if (decoded == null) return 0.5;
    final small = img.copyResize(decoded, width: 64);
    double sum = 0;
    int n = 0;
    for (int y = 0; y < small.height; y++) {
      for (int x = 0; x < small.width; x++) {
        final p = small.getPixel(x, y);
        sum += (p.r + p.g + p.b) / 3.0;
        n += 1;
      }
    }
    return (sum / n) / 255.0;
  }

  static int _scoreBand(
    double value, {
    required double idealMin,
    required double idealMax,
    required double hardMin,
    required double hardMax,
  }) {
    if (value < hardMin || value > hardMax) return 0;
    if (value >= idealMin && value <= idealMax) return 100;
    if (value < idealMin) {
      return (100 * (value - hardMin) / (idealMin - hardMin)).clamp(0, 100).toInt();
    }
    return (100 * (hardMax - value) / (hardMax - idealMax)).clamp(0, 100).toInt();
  }

  static int _framingScore(PoseFrame f) {
    if (!f.hasPerson || f.imageWidth == 0 || f.imageHeight == 0) return 0;
    const keys = [
      _nose,
      _leftShoulder,
      _rightShoulder,
      _leftHip,
      _rightHip,
      _leftAnkle,
      _rightAnkle,
    ];
    int inFrame = 0;
    int total = 0;
    for (final k in keys) {
      final l = f.landmarks[k];
      if (l == null) continue;
      total += 1;
      final nx = l.x / f.imageWidth;
      final ny = l.y / f.imageHeight;
      if (nx > 0.02 &&
          nx < 0.98 &&
          ny > 0.02 &&
          ny < 0.98 &&
          l.likelihood > 0.4) {
        inFrame += 1;
      }
    }
    return total == 0 ? 0 : (inFrame * 100 ~/ total);
  }

  static int _angleMatches(List<PoseFrame> frames, String expectedAngle) {
    final f = frames.firstWhere((f) => f.hasPerson, orElse: () => frames.first);
    if (!f.hasPerson || f.imageWidth == 0) return 0;
    final ls = f.landmarks[_leftShoulder];
    final rs = f.landmarks[_rightShoulder];
    if (ls == null || rs == null) return 0;
    final shoulderXDelta = (ls.x - rs.x).abs() / f.imageWidth;

    switch (expectedAngle) {
      case 'side':
        // Stacked from camera POV = small x delta
        if (shoulderXDelta <= 0.08) return 100;
        if (shoulderXDelta >= 0.30) return 20;
        return (100 - ((shoulderXDelta - 0.08) / 0.22) * 80).round();
      case 'front':
        if (shoulderXDelta >= 0.18) return 100;
        if (shoulderXDelta <= 0.05) return 20;
        return (((shoulderXDelta - 0.05) / 0.13) * 80 + 20).round();
      default:
        return 80;
    }
  }

  // ---- Biomech helpers ----

  static String _dominantSide(List<PoseFrame> frames) {
    double left = 0, right = 0;
    for (final f in frames) {
      for (final i in [_leftHip, _leftKnee, _leftAnkle, _leftShoulder]) {
        left += f.landmarks[i]?.likelihood ?? 0;
      }
      for (final i in [_rightHip, _rightKnee, _rightAnkle, _rightShoulder]) {
        right += f.landmarks[i]?.likelihood ?? 0;
      }
    }
    return left >= right ? 'left' : 'right';
  }

  static double _angleDeg(double ax, double ay, double bx, double by) {
    final dx = ax - bx;
    final dy = by - ay; // image y grows downward — flip
    return math.atan2(dx, dy).abs() * 180 / math.pi;
  }

  static double _jointAngleDeg(
    Landmark a,
    Landmark b,
    Landmark c,
  ) {
    final v1x = a.x - b.x;
    final v1y = a.y - b.y;
    final v2x = c.x - b.x;
    final v2y = c.y - b.y;
    final dot = v1x * v2x + v1y * v2y;
    final m1 = math.sqrt(v1x * v1x + v1y * v1y);
    final m2 = math.sqrt(v2x * v2x + v2y * v2y);
    if (m1 == 0 || m2 == 0) return 0;
    final cosA = (dot / (m1 * m2)).clamp(-1.0, 1.0);
    return math.acos(cosA) * 180 / math.pi;
  }

  static double _torsoHeight(PoseFrame f, int shoulderIdx, int hipIdx) {
    final s = f.landmarks[shoulderIdx];
    final h = f.landmarks[hipIdx];
    if (s == null || h == null) return 1;
    final v = (s.y - h.y).abs();
    return v < 1 ? 1 : v;
  }

  // ---- Per-lift biomech ----

  static void _computeSquat(
    List<PoseFrame> frames,
    String side,
    Map<String, double> metrics,
    List<FaultScore> faults,
  ) {
    final sIdx = side == 'left' ? _leftShoulder : _rightShoulder;
    final hIdx = side == 'left' ? _leftHip : _rightHip;
    final kIdx = side == 'left' ? _leftKnee : _rightKnee;
    final aIdx = side == 'left' ? _leftAnkle : _rightAnkle;

    PoseFrame? bottom;
    PoseFrame? top;
    double maxHipY = double.negativeInfinity;
    double minHipY = double.infinity;
    for (final f in frames) {
      final h = f.landmarks[hIdx];
      if (h == null) continue;
      if (h.y > maxHipY) {
        maxHipY = h.y;
        bottom = f;
      }
      if (h.y < minHipY) {
        minHipY = h.y;
        top = f;
      }
    }
    if (bottom == null || top == null) return;

    final bH = bottom.landmarks[hIdx]!;
    final bK = bottom.landmarks[kIdx];
    final bS = bottom.landmarks[sIdx];
    final bA = bottom.landmarks[aIdx];
    final torso = _torsoHeight(bottom, sIdx, hIdx);

    // Depth
    if (bK != null) {
      final delta = bH.y - bK.y; // positive = hip below knee in screen coords
      final depthScore = delta >= 0
          ? 100
          : (100 + (delta / torso) * 250).clamp(0, 100).round();
      metrics['depth_delta_norm'] = delta / torso;
      faults.add(FaultScore(
        key: 'depth',
        name: 'Squat depth',
        score: depthScore,
        evidence: delta >= 0
            ? 'Hip below knee at bottom'
            : 'Hip ${(-delta / torso * 100).toStringAsFixed(0)}% above knee at bottom',
      ));
    }

    // Forward lean at bottom
    if (bS != null) {
      final lean = _angleDeg(bS.x, bS.y, bH.x, bH.y);
      metrics['forward_lean_deg'] = lean;
      final leanScore = lean <= 30
          ? 100
          : (100 - (lean - 30) * 3).clamp(0, 100).round();
      faults.add(FaultScore(
        key: 'torso_angle',
        name: 'Torso angle',
        score: leanScore,
        evidence:
            'Torso leans ${lean.toStringAsFixed(0)}° from vertical at bottom',
      ));
    }

    // Knee angle at bottom
    if (bK != null && bA != null) {
      final kneeAngle = _jointAngleDeg(bH, bK, bA);
      metrics['knee_angle_bottom_deg'] = kneeAngle;
    }

    // Heel stability
    final topA = top.landmarks[aIdx];
    if (bA != null && topA != null) {
      final shift = (bA.y - topA.y).abs() / torso;
      metrics['heel_shift_norm'] = shift;
      final heelScore = shift < 0.05
          ? 100
          : (100 - (shift - 0.05) * 800).clamp(0, 100).round();
      faults.add(FaultScore(
        key: 'heel_stability',
        name: 'Heel pressure',
        score: heelScore,
        evidence: shift < 0.05
            ? 'Heels appear planted'
            : 'Ankle position drifted ${(shift * 100).toStringAsFixed(0)}% — possible heel lift',
      ));
    }

    // Spine angle stability across frames
    final angles = <double>[];
    for (final f in frames) {
      final s = f.landmarks[sIdx];
      final h = f.landmarks[hIdx];
      if (s == null || h == null) continue;
      angles.add(_angleDeg(s.x, s.y, h.x, h.y));
    }
    if (angles.length >= 3) {
      final mean = angles.reduce((a, b) => a + b) / angles.length;
      final variance = angles
              .map((a) => (a - mean) * (a - mean))
              .reduce((a, b) => a + b) /
          angles.length;
      final stdev = math.sqrt(variance);
      metrics['spine_angle_stdev_deg'] = stdev;
    }

    // ROM
    metrics['hip_range_norm'] = (maxHipY - minHipY) / torso;
  }

  static void _computeDeadlift(
    List<PoseFrame> frames,
    String side,
    Map<String, double> metrics,
    List<FaultScore> faults,
  ) {
    final sIdx = side == 'left' ? _leftShoulder : _rightShoulder;
    final hIdx = side == 'left' ? _leftHip : _rightHip;
    final kIdx = side == 'left' ? _leftKnee : _rightKnee;
    final wIdx = side == 'left' ? _leftWrist : _rightWrist;

    // Bottom = lowest wrist (bar at ground / hinge bottom)
    PoseFrame? bottom;
    PoseFrame? top;
    double maxWy = double.negativeInfinity;
    double minWy = double.infinity;
    for (final f in frames) {
      final w = f.landmarks[wIdx];
      if (w == null) continue;
      if (w.y > maxWy) {
        maxWy = w.y;
        bottom = f;
      }
      if (w.y < minWy) {
        minWy = w.y;
        top = f;
      }
    }
    if (bottom == null || top == null) return;

    final bS = bottom.landmarks[sIdx];
    final bH = bottom.landmarks[hIdx];
    final bK = bottom.landmarks[kIdx];
    final torso = _torsoHeight(bottom, sIdx, hIdx);

    // Neutral spine proxy: shoulder-hip line angle at bottom (steep hinge is expected,
    // but we flag if shoulder is BELOW hip — implies rounded back over the bar).
    if (bS != null && bH != null) {
      final spineAngle = _angleDeg(bS.x, bS.y, bH.x, bH.y);
      metrics['spine_angle_bottom_deg'] = spineAngle;
      final shoulderBelowHip = bS.y > bH.y;
      final spineScore = shoulderBelowHip
          ? 20
          : (spineAngle > 90
              ? 30
              : (spineAngle > 70 ? 60 : (spineAngle > 50 ? 85 : 100)));
      faults.add(FaultScore(
        key: 'neutral_spine',
        name: 'Neutral spine',
        score: spineScore,
        evidence: shoulderBelowHip
            ? 'Shoulders below hips at bottom — possible rounding'
            : 'Back angle ${spineAngle.toStringAsFixed(0)}° from vertical',
      ));
    }

    // Bar path: wrist x range vs torso scale
    final wxs = frames
        .map((f) => f.landmarks[wIdx]?.x)
        .whereType<double>()
        .toList();
    if (wxs.length >= 2) {
      final drift = (wxs.reduce(math.max) - wxs.reduce(math.min)) / torso;
      metrics['bar_path_drift_norm'] = drift;
      final pathScore = drift < 0.15
          ? 100
          : (100 - (drift - 0.15) * 300).clamp(0, 100).round();
      faults.add(FaultScore(
        key: 'bar_path',
        name: 'Bar path close to body',
        score: pathScore,
        evidence:
            'Hand drifted ${(drift * 100).toStringAsFixed(0)}% of torso through the lift',
      ));
    }

    // Hip hinge vs squat: how much hip went down vs knee
    if (bH != null && bK != null) {
      final topH = top.landmarks[hIdx];
      final topK = top.landmarks[kIdx];
      if (topH != null && topK != null) {
        final hipDrop = (bH.y - topH.y).abs();
        final kneeDrop = (bK.y - topK.y).abs();
        final hingeRatio = kneeDrop == 0 ? 99.0 : hipDrop / kneeDrop;
        metrics['hip_to_knee_ratio'] = hingeRatio;
        // Ratio >1.2 = hinge-dominant (good for RDL); 0.8–1.2 = conv deadlift OK;
        // <0.6 = squat-y (not ideal for deadlift)
        final hingeScore = hingeRatio >= 1.0
            ? 100
            : (hingeRatio * 90).clamp(0, 100).round();
        faults.add(FaultScore(
          key: 'hip_hinge',
          name: 'Hip hinge',
          score: hingeScore,
          evidence: 'Hip moved ${hingeRatio.toStringAsFixed(1)}× as much as knee',
        ));
      }
    }

    // Lockout: at top, shoulder-hip-knee close to vertical line
    final tS = top.landmarks[sIdx];
    final tH = top.landmarks[hIdx];
    final tK = top.landmarks[kIdx];
    if (tS != null && tH != null && tK != null) {
      final hipKneeLine = _angleDeg(tH.x, tH.y, tK.x, tK.y);
      final shoulderHipLine = _angleDeg(tS.x, tS.y, tH.x, tH.y);
      metrics['lockout_hip_knee_deg'] = hipKneeLine;
      metrics['lockout_shoulder_hip_deg'] = shoulderHipLine;
      final lockoutScore =
          ((180 - (hipKneeLine + shoulderHipLine)) / 1.8).clamp(0, 100).round();
      faults.add(FaultScore(
        key: 'lockout',
        name: 'Full lockout',
        score: lockoutScore,
        evidence:
            'Top: hip-knee ${hipKneeLine.toStringAsFixed(0)}°, torso ${shoulderHipLine.toStringAsFixed(0)}° from vertical',
      ));
    }
  }

  static void _computeBench(
    List<PoseFrame> frames,
    String side,
    Map<String, double> metrics,
    List<FaultScore> faults,
  ) {
    final sIdx = side == 'left' ? _leftShoulder : _rightShoulder;
    final eIdx = side == 'left' ? _leftElbow : _rightElbow;
    final wIdx = side == 'left' ? _leftWrist : _rightWrist;

    // Bottom of bench (from side) = wrist closest to chest (lowest y relative to shoulder)
    PoseFrame? bottom;
    PoseFrame? top;
    double bestDelta = double.negativeInfinity;
    double worstDelta = double.infinity;
    for (final f in frames) {
      final w = f.landmarks[wIdx];
      final s = f.landmarks[sIdx];
      if (w == null || s == null) continue;
      final delta = w.y - s.y; // larger = wrist lower than shoulder (closer to chest in supine side view)
      if (delta > bestDelta) {
        bestDelta = delta;
        bottom = f;
      }
      if (delta < worstDelta) {
        worstDelta = delta;
        top = f;
      }
    }
    if (bottom == null || top == null) return;

    final bS = bottom.landmarks[sIdx]!;
    final bE = bottom.landmarks[eIdx];
    final bW = bottom.landmarks[wIdx]!;
    final torso = (bS.y - bW.y).abs().clamp(1, 9999).toDouble();

    // Bar path drift: wrist x range across frames
    final wxs =
        frames.map((f) => f.landmarks[wIdx]?.x).whereType<double>().toList();
    if (wxs.length >= 2) {
      final drift = (wxs.reduce(math.max) - wxs.reduce(math.min)) / torso;
      metrics['bar_path_drift_norm'] = drift;
      final score = drift < 0.20
          ? 100
          : (100 - (drift - 0.20) * 250).clamp(0, 100).round();
      faults.add(FaultScore(
        key: 'bar_path',
        name: 'Bar path consistency',
        score: score,
        evidence: 'Wrist drifted ${(drift * 100).toStringAsFixed(0)}% of torso',
      ));
    }

    // Elbow angle at bottom
    if (bE != null) {
      final elbowAngle = _jointAngleDeg(bS, bE, bW);
      metrics['elbow_angle_bottom_deg'] = elbowAngle;
      final score = (elbowAngle >= 70 && elbowAngle <= 110)
          ? 100
          : (elbowAngle < 70
              ? (elbowAngle / 70 * 100).round()
              : (100 - (elbowAngle - 110) * 2).clamp(0, 100).round());
      faults.add(FaultScore(
        key: 'elbow_angle',
        name: 'Elbow angle at chest',
        score: score,
        evidence: 'Elbow at ${elbowAngle.toStringAsFixed(0)}° at bottom',
      ));
    }
  }

  static void _computeOhp(
    List<PoseFrame> frames,
    String side,
    Map<String, double> metrics,
    List<FaultScore> faults,
  ) {
    final sIdx = side == 'left' ? _leftShoulder : _rightShoulder;
    final hIdx = side == 'left' ? _leftHip : _rightHip;
    final wIdx = side == 'left' ? _leftWrist : _rightWrist;

    PoseFrame? top;
    double minWy = double.infinity;
    for (final f in frames) {
      final w = f.landmarks[wIdx];
      if (w == null) continue;
      if (w.y < minWy) {
        minWy = w.y;
        top = f;
      }
    }
    if (top == null) return;

    final tS = top.landmarks[sIdx];
    final tH = top.landmarks[hIdx];
    final tW = top.landmarks[wIdx];
    final torso = (tS != null && tH != null) ? (tS.y - tH.y).abs() : 1.0;

    // Vertical bar path: wrist x range
    final wxs =
        frames.map((f) => f.landmarks[wIdx]?.x).whereType<double>().toList();
    if (wxs.length >= 2) {
      final drift = (wxs.reduce(math.max) - wxs.reduce(math.min)) / torso;
      metrics['bar_path_drift_norm'] = drift;
      final score = drift < 0.18
          ? 100
          : (100 - (drift - 0.18) * 250).clamp(0, 100).round();
      faults.add(FaultScore(
        key: 'vertical_bar_path',
        name: 'Vertical bar path',
        score: score,
        evidence: 'Wrist drifted ${(drift * 100).toStringAsFixed(0)}% of torso',
      ));
    }

    // Lockout: wrist over shoulder
    if (tS != null && tW != null) {
      final overhead = (tS.x - tW.x).abs() / torso;
      metrics['lockout_drift_norm'] = overhead;
      final score = overhead < 0.15
          ? 100
          : (100 - (overhead - 0.15) * 400).clamp(0, 100).round();
      faults.add(FaultScore(
        key: 'lockout_stacked',
        name: 'Lockout: wrist over shoulder',
        score: score,
        evidence: 'Wrist offset ${(overhead * 100).toStringAsFixed(0)}% from shoulder at top',
      ));
    }

    // Torso angle stability — flag layback (ribs not down)
    final torsoAngles = <double>[];
    for (final f in frames) {
      final s = f.landmarks[sIdx];
      final h = f.landmarks[hIdx];
      if (s == null || h == null) continue;
      torsoAngles.add(_angleDeg(s.x, s.y, h.x, h.y));
    }
    if (torsoAngles.length >= 3) {
      final mx = torsoAngles.reduce(math.max);
      metrics['torso_max_lean_deg'] = mx;
      final score = mx < 15
          ? 100
          : (100 - (mx - 15) * 3).clamp(0, 100).round();
      faults.add(FaultScore(
        key: 'ribs_down',
        name: 'Ribs down (no layback)',
        score: score,
        evidence: 'Max torso lean ${mx.toStringAsFixed(0)}° during press',
      ));
    }
  }

  static void _computeRow(
    List<PoseFrame> frames,
    String side,
    Map<String, double> metrics,
    List<FaultScore> faults,
  ) {
    final sIdx = side == 'left' ? _leftShoulder : _rightShoulder;
    final hIdx = side == 'left' ? _leftHip : _rightHip;
    final eIdx = side == 'left' ? _leftElbow : _rightElbow;
    final wIdx = side == 'left' ? _leftWrist : _rightWrist;

    // Torso stability: shoulder-hip angle variance
    final torsoAngles = <double>[];
    for (final f in frames) {
      final s = f.landmarks[sIdx];
      final h = f.landmarks[hIdx];
      if (s == null || h == null) continue;
      torsoAngles.add(_angleDeg(s.x, s.y, h.x, h.y));
    }
    if (torsoAngles.length >= 3) {
      final mean = torsoAngles.reduce((a, b) => a + b) / torsoAngles.length;
      final variance = torsoAngles
              .map((a) => (a - mean) * (a - mean))
              .reduce((a, b) => a + b) /
          torsoAngles.length;
      final stdev = math.sqrt(variance);
      metrics['torso_angle_stdev_deg'] = stdev;
      final score = stdev < 5
          ? 100
          : (100 - (stdev - 5) * 8).clamp(0, 100).round();
      faults.add(FaultScore(
        key: 'torso_stability',
        name: 'Torso stability',
        score: score,
        evidence: 'Torso swing ${stdev.toStringAsFixed(1)}° stdev across reps',
      ));
    }

    // Pull height: at peak wrist y closest to shoulder (lowest delta)
    PoseFrame? topPull;
    double bestDelta = double.infinity;
    for (final f in frames) {
      final w = f.landmarks[wIdx];
      final s = f.landmarks[sIdx];
      if (w == null || s == null) continue;
      final delta = (w.y - s.y).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        topPull = f;
      }
    }
    if (topPull != null) {
      final s = topPull.landmarks[sIdx]!;
      final w = topPull.landmarks[wIdx]!;
      final e = topPull.landmarks[eIdx];
      final torso = _torsoHeight(topPull, sIdx, hIdx);
      final pullDelta = (w.y - s.y).abs() / torso;
      metrics['pull_height_delta_norm'] = pullDelta;
      final pullScore = pullDelta < 0.20
          ? 100
          : (100 - (pullDelta - 0.20) * 250).clamp(0, 100).round();
      faults.add(FaultScore(
        key: 'pull_height',
        name: 'Pull height',
        score: pullScore,
        evidence: 'Hand reached within ${(pullDelta * 100).toStringAsFixed(0)}% torso of shoulder',
      ));
      // Elbow back (not flared)
      if (e != null) {
        final elbowDelta = (e.x - s.x).abs() / torso;
        metrics['elbow_flare_norm'] = elbowDelta;
        final elbowScore = elbowDelta < 0.25
            ? 100
            : (100 - (elbowDelta - 0.25) * 200).clamp(0, 100).round();
        faults.add(FaultScore(
          key: 'elbow_path',
          name: 'Elbow drives back',
          score: elbowScore,
          evidence: 'Elbow ${(elbowDelta * 100).toStringAsFixed(0)}% torso outside shoulder line',
        ));
      }
    }
  }

  static void _computeLatPulldown(
    List<PoseFrame> frames,
    Map<String, double> metrics,
    List<FaultScore> faults,
  ) {
    // Front view: use both wrists, both shoulders, both hips
    PoseFrame? bottom;
    double bestY = double.negativeInfinity;
    for (final f in frames) {
      final lw = f.landmarks[_leftWrist];
      final rw = f.landmarks[_rightWrist];
      if (lw == null || rw == null) continue;
      final avgY = (lw.y + rw.y) / 2;
      if (avgY > bestY) {
        bestY = avgY;
        bottom = f;
      }
    }
    if (bottom == null) return;

    final lw = bottom.landmarks[_leftWrist]!;
    final rw = bottom.landmarks[_rightWrist]!;
    final ls = bottom.landmarks[_leftShoulder];
    final rs = bottom.landmarks[_rightShoulder];
    final lh = bottom.landmarks[_leftHip];
    final rh = bottom.landmarks[_rightHip];

    if (ls != null && rs != null) {
      final shoulderY = (ls.y + rs.y) / 2;
      final wristY = (lw.y + rw.y) / 2;
      final torso = (lh != null && rh != null)
          ? (((lh.y + rh.y) / 2 - shoulderY).abs())
          : 1.0;
      final pullDelta = (wristY - shoulderY) / torso; // positive = bar at/below shoulder
      metrics['bar_to_chest_norm'] = pullDelta;
      final score = pullDelta >= 0.05
          ? 100
          : (50 + pullDelta * 500).clamp(0, 100).round();
      faults.add(FaultScore(
        key: 'bar_to_chest',
        name: 'Bar reaches upper chest',
        score: score,
        evidence: pullDelta >= 0.05
            ? 'Bar comes to chest level'
            : 'Bar stops above shoulder line',
      ));
    }

    // Torso lean: hip-shoulder line angle change across frames vs reference
    final leans = <double>[];
    for (final f in frames) {
      final s = f.landmarks[_leftShoulder] ?? f.landmarks[_rightShoulder];
      final h = f.landmarks[_leftHip] ?? f.landmarks[_rightHip];
      if (s == null || h == null) continue;
      leans.add(_angleDeg(s.x, s.y, h.x, h.y));
    }
    if (leans.length >= 3) {
      final mx = leans.reduce(math.max);
      metrics['torso_max_lean_deg'] = mx;
      final score = mx < 20
          ? 100
          : (100 - (mx - 20) * 4).clamp(0, 100).round();
      faults.add(FaultScore(
        key: 'torso_lean',
        name: 'Minimal lean-back',
        score: score,
        evidence: 'Max lean ${mx.toStringAsFixed(0)}°',
      ));
    }
  }

  static void _computePushUp(
    List<PoseFrame> frames,
    String side,
    Map<String, double> metrics,
    List<FaultScore> faults,
  ) {
    final sIdx = side == 'left' ? _leftShoulder : _rightShoulder;
    final hIdx = side == 'left' ? _leftHip : _rightHip;
    final aIdx = side == 'left' ? _leftAnkle : _rightAnkle;
    final eIdx = side == 'left' ? _leftElbow : _rightElbow;
    final wIdx = side == 'left' ? _leftWrist : _rightWrist;

    // Plank line: shoulder-hip-ankle colinearity, averaged across frames
    final deviations = <double>[];
    for (final f in frames) {
      final s = f.landmarks[sIdx];
      final h = f.landmarks[hIdx];
      final a = f.landmarks[aIdx];
      if (s == null || h == null || a == null) continue;
      // Distance from hip to line shoulder→ankle, normalized by length
      final lineLen =
          math.sqrt(math.pow(a.x - s.x, 2) + math.pow(a.y - s.y, 2));
      if (lineLen == 0) continue;
      final numerator =
          ((a.y - s.y) * h.x - (a.x - s.x) * h.y + a.x * s.y - a.y * s.x).abs();
      final dist = numerator / lineLen;
      deviations.add(dist / lineLen);
    }
    if (deviations.isNotEmpty) {
      final mx = deviations.reduce(math.max);
      metrics['plank_max_deviation_norm'] = mx;
      final score = mx < 0.05
          ? 100
          : (100 - (mx - 0.05) * 600).clamp(0, 100).round();
      faults.add(FaultScore(
        key: 'plank_line',
        name: 'Plank line',
        score: score,
        evidence: mx < 0.05
            ? 'Hip stays in line with shoulder-ankle'
            : 'Hip deviates ${(mx * 100).toStringAsFixed(0)}% off plank line',
      ));
    }

    // Elbow angle at bottom
    PoseFrame? bottom;
    double maxS = double.negativeInfinity;
    for (final f in frames) {
      final s = f.landmarks[sIdx];
      if (s == null) continue;
      if (s.y > maxS) {
        maxS = s.y;
        bottom = f;
      }
    }
    if (bottom != null) {
      final s = bottom.landmarks[sIdx]!;
      final e = bottom.landmarks[eIdx];
      final w = bottom.landmarks[wIdx];
      if (e != null && w != null) {
        final elbowAngle = _jointAngleDeg(s, e, w);
        metrics['elbow_angle_bottom_deg'] = elbowAngle;
        final score = (elbowAngle >= 75 && elbowAngle <= 105)
            ? 100
            : (elbowAngle < 75
                ? (elbowAngle / 75 * 100).round()
                : (100 - (elbowAngle - 105) * 3).clamp(0, 100).round());
        faults.add(FaultScore(
          key: 'elbow_depth',
          name: 'Elbow angle at bottom',
          score: score,
          evidence: 'Elbow at ${elbowAngle.toStringAsFixed(0)}° at bottom',
        ));
      }
    }
  }

  static void _computeLunge(
    List<PoseFrame> frames,
    String side,
    Map<String, double> metrics,
    List<FaultScore> faults,
  ) {
    final sIdx = side == 'left' ? _leftShoulder : _rightShoulder;
    final hIdx = side == 'left' ? _leftHip : _rightHip;
    final kIdx = side == 'left' ? _leftKnee : _rightKnee;
    final aIdx = side == 'left' ? _leftAnkle : _rightAnkle;

    // Bottom = lowest hip
    PoseFrame? bottom;
    double maxHy = double.negativeInfinity;
    for (final f in frames) {
      final h = f.landmarks[hIdx];
      if (h == null) continue;
      if (h.y > maxHy) {
        maxHy = h.y;
        bottom = f;
      }
    }
    if (bottom == null) return;

    final bS = bottom.landmarks[sIdx];
    final bH = bottom.landmarks[hIdx]!;
    final bK = bottom.landmarks[kIdx];
    final bA = bottom.landmarks[aIdx];
    final torso = bS != null ? (bS.y - bH.y).abs().clamp(1, 9999).toDouble() : 1.0;

    // Torso upright: shoulder-hip angle vs vertical
    if (bS != null) {
      final lean = _angleDeg(bS.x, bS.y, bH.x, bH.y);
      metrics['torso_lean_deg'] = lean;
      final score = lean <= 15
          ? 100
          : (100 - (lean - 15) * 4).clamp(0, 100).round();
      faults.add(FaultScore(
        key: 'torso_upright',
        name: 'Torso upright',
        score: score,
        evidence: 'Torso leans ${lean.toStringAsFixed(0)}° from vertical at bottom',
      ));
    }

    // Front knee angle at bottom (~90° ideal)
    if (bK != null && bA != null) {
      final kneeAngle = _jointAngleDeg(bH, bK, bA);
      metrics['knee_angle_bottom_deg'] = kneeAngle;
      final score = (kneeAngle >= 80 && kneeAngle <= 100)
          ? 100
          : (kneeAngle < 80
              ? (kneeAngle / 80 * 100).round()
              : (100 - (kneeAngle - 100) * 3).clamp(0, 100).round());
      faults.add(FaultScore(
        key: 'depth',
        name: 'Front leg depth',
        score: score,
        evidence: 'Front knee at ${kneeAngle.toStringAsFixed(0)}° at bottom',
      ));
    }

    // Knee over ankle (side view: knee_x not far past ankle_x)
    if (bK != null && bA != null) {
      final kneeAheadOfAnkle = (bK.x - bA.x).abs() / torso;
      metrics['knee_ahead_of_ankle_norm'] = kneeAheadOfAnkle;
      final score = kneeAheadOfAnkle < 0.20
          ? 100
          : (100 - (kneeAheadOfAnkle - 0.20) * 200).clamp(0, 100).round();
      faults.add(FaultScore(
        key: 'knee_position',
        name: 'Knee over ankle',
        score: score,
        evidence:
            'Knee ${(kneeAheadOfAnkle * 100).toStringAsFixed(0)}% of torso forward of ankle',
      ));
    }
  }
}
