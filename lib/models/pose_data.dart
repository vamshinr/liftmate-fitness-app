import 'dart:typed_data';

/// Single 2D landmark from on-device pose detection.
class Landmark {
  final double x;
  final double y;
  final double z;
  final double likelihood;
  const Landmark({
    required this.x,
    required this.y,
    required this.z,
    required this.likelihood,
  });
}

/// Pose detection result for one captured frame.
class PoseFrame {
  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final Map<int, Landmark> landmarks;
  final double avgLikelihood;
  final bool hasPerson;

  const PoseFrame({
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.landmarks,
    required this.avgLikelihood,
    required this.hasPerson,
  });
}

/// Local quality assessment of the captured set — determines if we even
/// bother sending to the cloud coach AI.
class QualityReport {
  final bool usable;
  final int blurScore;
  final int brightnessScore;
  final int framingScore;
  final int angleScore;
  final int subjectVisibilityScore;
  final List<String> issues;
  final String userMessage;

  const QualityReport({
    required this.usable,
    required this.blurScore,
    required this.brightnessScore,
    required this.framingScore,
    required this.angleScore,
    required this.subjectVisibilityScore,
    required this.issues,
    required this.userMessage,
  });

  int get overall {
    final scores = [
      blurScore,
      brightnessScore,
      framingScore,
      angleScore,
      subjectVisibilityScore,
    ];
    return scores.reduce((a, b) => a + b) ~/ scores.length;
  }

  Map<String, dynamic> toJson() => {
        'usable': usable,
        'blurScore': blurScore,
        'brightnessScore': brightnessScore,
        'framingScore': framingScore,
        'angleScore': angleScore,
        'subjectVisibilityScore': subjectVisibilityScore,
        'issues': issues,
      };
}

/// One named fault from the per-lift rubric, with a 0-100 pass score.
class FaultScore {
  final String key;
  final String name;
  final int score;
  final String evidence;

  const FaultScore({
    required this.key,
    required this.name,
    required this.score,
    required this.evidence,
  });

  bool get pass => score >= 70;

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'score': score,
        'evidence': evidence,
      };

  factory FaultScore.fromJson(Map<String, dynamic> j) => FaultScore(
        key: j['key'] as String? ?? '',
        name: j['name'] as String? ?? '',
        score: (j['score'] as num?)?.toInt() ?? 0,
        evidence: j['evidence'] as String? ?? '',
      );
}

/// Objective biomechanical summary derived from the pose frames.
/// Numbers are in display units (degrees for angles, 0-100 for ratios).
class BiomechSummary {
  final String lift;
  final Map<String, double> metrics;
  final List<FaultScore> faults;
  final String sideUsed;

  const BiomechSummary({
    required this.lift,
    required this.metrics,
    required this.faults,
    required this.sideUsed,
  });

  Map<String, dynamic> toJson() => {
        'lift': lift,
        'metrics': metrics,
        'faults': faults.map((f) => f.toJson()).toList(),
        'sideUsed': sideUsed,
      };
}
