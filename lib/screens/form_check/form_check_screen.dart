import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../models/form_check.dart';
import '../../models/pose_data.dart';
import '../../services/ai_coach_service.dart';
import '../../services/pose_service.dart';
import '../../services/profile_service.dart';
import '../../theme.dart';
import '../../widgets/trainer_network_card.dart';
import '../coach/coach_review_screen.dart';
import '../trainers/trainer_network_screen.dart';

class CoreLift {
  final String name;
  final String tagline;
  final IconData icon;
  final String cameraAngle; // "side" | "front" | "45"
  final String angleHint;

  const CoreLift({
    required this.name,
    required this.tagline,
    required this.icon,
    required this.cameraAngle,
    required this.angleHint,
  });
}

const _coreLifts = <CoreLift>[
  CoreLift(
    name: 'Squat',
    tagline: 'Hips below knees, knees tracking toes',
    icon: Icons.accessibility_new,
    cameraAngle: 'side',
    angleHint: 'Phone ~3m to your side at hip height, profile view.',
  ),
  CoreLift(
    name: 'Deadlift / RDL',
    tagline: 'Neutral spine, hinge from the hips',
    icon: Icons.fitness_center,
    cameraAngle: 'side',
    angleHint: 'Phone ~3m to your side at hip height. Spine clearly visible.',
  ),
  CoreLift(
    name: 'Bench Press',
    tagline: 'Bar to chest, no shoulder shrug',
    icon: Icons.airline_seat_flat,
    cameraAngle: 'side',
    angleHint: 'Phone at bench height, ~2m to the side. Whole bar path visible.',
  ),
  CoreLift(
    name: 'Overhead Press',
    tagline: 'Vertical bar path, ribs down',
    icon: Icons.arrow_upward,
    cameraAngle: 'side',
    angleHint: 'Phone ~3m to your side at chest height, profile view.',
  ),
  CoreLift(
    name: 'Row',
    tagline: 'Elbows drive back, lats engage first',
    icon: Icons.swap_horiz,
    cameraAngle: 'side',
    angleHint: 'Phone ~3m to the side, hip-to-shoulder height.',
  ),
  CoreLift(
    name: 'Lat Pulldown',
    tagline: 'Bar to upper chest, scaps down first',
    icon: Icons.vertical_align_bottom,
    cameraAngle: 'front',
    angleHint: 'Phone in front of you, ~3m away, chest height.',
  ),
  CoreLift(
    name: 'Push-up',
    tagline: 'Plank line, scaps protract at top',
    icon: Icons.horizontal_rule,
    cameraAngle: 'side',
    angleHint: 'Phone on the floor ~2m to your side. Profile view.',
  ),
  CoreLift(
    name: 'Lunge / Split Squat',
    tagline: 'Front knee tracks, torso upright',
    icon: Icons.directions_walk,
    cameraAngle: 'side',
    angleHint: 'Phone ~3m to your side at hip height.',
  ),
];

class FormCheckScreen extends StatefulWidget {
  const FormCheckScreen({super.key});

  @override
  State<FormCheckScreen> createState() => _FormCheckScreenState();
}

enum _Stage { pickLift, live, analyzing, results }

enum _RepPhase { standing, descending, atBottom, ascending }

extension _RepPhaseLabel on _RepPhase {
  String get label => switch (this) {
        _RepPhase.standing => 'Standing',
        _RepPhase.descending => 'Descending',
        _RepPhase.atBottom => 'At Bottom',
        _RepPhase.ascending => 'Ascending',
      };
}

class _FormCheckScreenState extends State<FormCheckScreen> {
  CoreLift _selected = _coreLifts.first;
  _Stage _stage = _Stage.pickLift;

  CameraController? _camera;
  bool _cameraReady = false;
  String _cameraError = '';
  CameraLensDirection _lensDirection = CameraLensDirection.back;
  List<CameraDescription> _availableCameras = const [];

  final _detector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.base,
    ),
  );

  // Pose stream state
  bool _detectorBusy = false;
  DateTime _lastDetect = DateTime.fromMillisecondsSinceEpoch(0);
  Pose? _livePose;
  Size? _liveImageSize;

  // Live rules state
  String _liveCue = '';
  Color _liveCueColor = AppTheme.neonLime;
  DateTime _lastCueSpokenAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastSpokenCue = '';

  // Per-rep tracking — phase FSM driven off hip-Y velocity
  _RepPhase _phase = _RepPhase.standing;
  int _repCount = 0;
  double? _hipBaselineY;
  double? _prevHipY;
  double _maxHipDepthThisRep = 0; // peak hip drop during current descent
  double _maxLeanThisRep = 0;     // peak torso lean during current rep
  double _maxBarPathDriftThisRep = 0;

  // Live score: starts at 100, decays on bad reps, partially restores on
  // clean ones — matches the reference app's score-on-screen behavior.
  int _score = 100;

  // Detection-loop FPS (rolling average over last second)
  final List<DateTime> _detectTimestamps = [];
  int _fps = 0;

  // Voice toggle. Cues continue to render visually when muted.
  bool _voiceOn = true;

  // Framing status — drives the centered overlay text.
  String _framingMsg = '';
  String _statusMsg = 'Ready — squat when you like.';

  // Collected per-frame metrics across the set, for final synthesis
  final List<PoseFrame> _collectedFrames = [];
  Uint8List? _lastJpeg;

  final FlutterTts _tts = FlutterTts();

  // Result
  FormCheckResult? _result;
  String _analyzeError = '';

  final TextEditingController _painCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.52);
  }

  @override
  void dispose() {
    _stopStream();
    _disposeCamera();
    _detector.close();
    _tts.stop();
    _painCtrl.dispose();
    super.dispose();
  }

  Future<void> _disposeCamera() async {
    final c = _camera;
    _camera = null;
    _cameraReady = false;
    await c?.dispose();
  }

  Future<void> _initCamera() async {
    try {
      if (_availableCameras.isEmpty) {
        _availableCameras = await availableCameras();
      }
      if (_availableCameras.isEmpty) {
        setState(() => _cameraError = 'No camera available.');
        return;
      }
      final desc = _availableCameras.firstWhere(
        (c) => c.lensDirection == _lensDirection,
        orElse: () => _availableCameras.first,
      );
      _camera = CameraController(
        desc,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.nv21,
      );
      await _camera!.initialize();
      if (!mounted) return;
      setState(() {
        _cameraReady = true;
        _cameraError = '';
      });
      await _startStream();
    } catch (e) {
      if (!mounted) return;
      setState(() => _cameraError = 'Camera not available: $e');
    }
  }

  Future<void> _startStream() async {
    final c = _camera;
    if (c == null) return;
    try {
      await c.startImageStream(_onCameraFrame);
    } catch (e) {
      debugPrint('startImageStream failed: $e');
    }
  }

  Future<void> _stopStream() async {
    try {
      if (_camera?.value.isStreamingImages == true) {
        await _camera!.stopImageStream();
      }
    } catch (_) {}
  }

  void _onCameraFrame(CameraImage image) {
    if (_detectorBusy) return;
    final now = DateTime.now();
    // Throttle to ~6 Hz to keep up with the detector and avoid backlog.
    if (now.difference(_lastDetect).inMilliseconds < 160) return;
    _detectorBusy = true;
    _lastDetect = now;

    _detectFromCameraImage(image).then((pose) {
      if (!mounted) {
        _detectorBusy = false;
        return;
      }
      _liveImageSize = Size(image.width.toDouble(), image.height.toDouble());
      _livePose = pose;
      if (pose != null) {
        _onPoseTick(pose, _liveImageSize!);
      }
      setState(() {});
      _detectorBusy = false;
    }).catchError((e) {
      _detectorBusy = false;
    });
  }

  Future<Pose?> _detectFromCameraImage(CameraImage image) async {
    final input = _toInputImage(image);
    if (input == null) return null;
    final poses = await _detector.processImage(input);
    return poses.isEmpty ? null : poses.first;
  }

  InputImage? _toInputImage(CameraImage image) {
    final rotation = _rotationFromSensor();
    if (rotation == null) return null;
    final format =
        InputImageFormatValue.fromRawValue(image.format.raw as int) ??
            (Platform.isIOS
                ? InputImageFormat.bgra8888
                : InputImageFormat.nv21);
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  InputImageRotation? _rotationFromSensor() {
    final desc = _camera?.description;
    if (desc == null) return InputImageRotation.rotation0deg;
    var rotation = desc.sensorOrientation;
    // Front cameras are mirrored — ML Kit handles this when given the
    // correct sensor rotation; we don't try to compensate here.
    return InputImageRotationValue.fromRawValue(rotation) ??
        InputImageRotation.rotation0deg;
  }

  void _onPoseTick(Pose pose, Size imageSize) {
    // Tally FPS (rolling 1-second window)
    final now = DateTime.now();
    _detectTimestamps.add(now);
    _detectTimestamps.removeWhere(
        (t) => now.difference(t).inMilliseconds > 1000);
    _fps = _detectTimestamps.length;

    // Convert landmarks to our internal Landmark map for collection
    final landmarks = <int, Landmark>{};
    double total = 0;
    int n = 0;
    pose.landmarks.forEach((type, lm) {
      landmarks[type.index] = Landmark(
        x: lm.x,
        y: lm.y,
        z: lm.z,
        likelihood: lm.likelihood,
      );
      total += lm.likelihood;
      n += 1;
    });
    final avg = n > 0 ? total / n : 0.0;

    // Framing first — if the user isn't visible, that overrides everything.
    final framing = _evaluateFraming(pose, imageSize, avg);
    _framingMsg = framing;
    if (framing.isNotEmpty) {
      _liveCue = '';
      _statusMsg = framing;
    }

    if (framing.isEmpty) {
      // Per-lift live cue
      final cue = _evaluateLive(pose, imageSize);
      if (cue != null && cue.text.isNotEmpty) {
        _liveCue = cue.text;
        _liveCueColor = cue.color;
        _maybeSpeak(cue.text);
      }

      // Phase machine + rep-quality scoring
      _trackPhase(pose, imageSize);
    }

    // Snapshot every ~750ms for end-of-set analysis
    final shouldStore = _collectedFrames.isEmpty ||
        DateTime.now()
                .difference(_collectedFrames.last.capturedAt())
                .inMilliseconds >
            700;
    if (shouldStore) {
      _collectedFrames.add(
        PoseFrame(
          imageBytes: Uint8List(0),
          imageWidth: imageSize.width.toInt(),
          imageHeight: imageSize.height.toInt(),
          landmarks: landmarks,
          avgLikelihood: avg,
          hasPerson: true,
        ),
      );
      // Cap to last 60 snapshots (~45s)
      if (_collectedFrames.length > 60) {
        _collectedFrames.removeAt(0);
      }
    }
  }

  /// Returns a non-empty status string when the user is not framed cleanly.
  /// Empty string = framing is good and per-lift coaching can proceed.
  String _evaluateFraming(Pose pose, Size imageSize, double avgLikelihood) {
    // Required landmarks per lift type — we want full-body for squats etc.
    final required = [
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
      PoseLandmarkType.leftKnee,
      PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftAnkle,
      PoseLandmarkType.rightAnkle,
    ];
    int seen = 0;
    double sumConfidence = 0;
    for (final t in required) {
      final lm = pose.landmarks[t];
      if (lm != null && lm.likelihood > 0.5) {
        seen += 1;
        sumConfidence += lm.likelihood;
      }
    }
    if (seen < required.length * 0.75) {
      return 'Step into frame';
    }
    if (avgLikelihood < 0.4) {
      return 'Get more light on yourself';
    }
    // Side-on framing check (for side-view lifts): shoulders should be
    // roughly stacked from camera POV — small horizontal x delta.
    if (_selected.cameraAngle == 'side') {
      final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
      final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
      if (ls != null && rs != null) {
        final dx = (ls.x - rs.x).abs() / imageSize.width;
        if (dx > 0.18) {
          return 'Stand side-on, full body';
        }
      }
    }
    // Body height check — if the bounding box covers <50% of vertical
    // frame, user is too close or too far.
    final ank = pose.landmarks[PoseLandmarkType.leftAnkle] ??
        pose.landmarks[PoseLandmarkType.rightAnkle];
    final shd = pose.landmarks[PoseLandmarkType.leftShoulder] ??
        pose.landmarks[PoseLandmarkType.rightShoulder];
    if (ank != null && shd != null) {
      final bodyHeight = (ank.y - shd.y).abs() / imageSize.height;
      if (bodyHeight < 0.40) return 'Step closer — full body in frame';
    }
    // Side-effect: surface a positive status when framing first goes good.
    _statusMsg = 'Looking good — squat when ready';
    if (sumConfidence == 0) return '';
    return '';
  }

  void _trackPhase(Pose pose, Size imageSize) {
    final h = pose.landmarks[PoseLandmarkType.leftHip] ??
        pose.landmarks[PoseLandmarkType.rightHip];
    if (h == null) return;
    final hipY = h.y;
    _hipBaselineY ??= hipY;
    final prevY = _prevHipY ?? hipY;
    _prevHipY = hipY;

    final delta = hipY - _hipBaselineY!; // positive = hip below baseline
    final velocity = hipY - prevY;       // positive = descending

    // Track depth + fault peaks during the rep
    if (delta > _maxHipDepthThisRep) _maxHipDepthThisRep = delta;
    final lean = _currentTorsoLeanRatio(pose, imageSize);
    if (lean > _maxLeanThisRep) _maxLeanThisRep = lean;
    final drift = _currentBarPathDriftRatio(pose, imageSize);
    if (drift > _maxBarPathDriftThisRep) _maxBarPathDriftThisRep = drift;

    // State transitions
    switch (_phase) {
      case _RepPhase.standing:
        if (delta > imageSize.height * 0.045 && velocity > 1) {
          _phase = _RepPhase.descending;
          _statusMsg = 'Descending — control the eccentric.';
        }
        break;
      case _RepPhase.descending:
        if (velocity.abs() < 1.2 && delta > imageSize.height * 0.08) {
          _phase = _RepPhase.atBottom;
          _statusMsg = 'At bottom — drive up.';
        } else if (velocity < -1) {
          _phase = _RepPhase.ascending;
        }
        break;
      case _RepPhase.atBottom:
        if (velocity < -1) {
          _phase = _RepPhase.ascending;
          _statusMsg = 'Ascending — squeeze the top.';
        }
        break;
      case _RepPhase.ascending:
        if (delta < imageSize.height * 0.03) {
          _phase = _RepPhase.standing;
          _completeRep(imageSize);
        }
        break;
    }

    // Slowly track baseline (handle camera/jacket shifts during the set).
    _hipBaselineY = (_hipBaselineY! * 0.985) + (hipY * 0.015);
  }

  void _completeRep(Size imageSize) {
    _repCount += 1;

    // Score the rep. Each fault deducts; clean reps recover slightly.
    final depthRatio = _maxHipDepthThisRep / imageSize.height; // ~0.10 = parallel-ish
    int deduction = 0;
    String? faultCue;
    if (depthRatio < 0.09) {
      deduction += 15;
      faultCue = 'Go deeper next rep.';
    }
    if (_maxLeanThisRep > 0.22) {
      deduction += 12;
      faultCue ??= 'Chest up — less forward lean.';
    }
    if (_maxBarPathDriftThisRep > 0.20) {
      deduction += 8;
      faultCue ??= 'Bar drifted — keep it over midfoot.';
    }
    if (deduction == 0) {
      _score = (_score + 2).clamp(0, 100);
      _statusMsg = 'Clean rep $_repCount.';
      _maybeSpeak('Clean rep $_repCount.');
    } else {
      _score = (_score - deduction).clamp(0, 100);
      _statusMsg = 'Rep $_repCount — $faultCue';
      if (faultCue != null) _maybeSpeak(faultCue);
    }

    // Reset per-rep peaks
    _maxHipDepthThisRep = 0;
    _maxLeanThisRep = 0;
    _maxBarPathDriftThisRep = 0;
  }

  double _currentTorsoLeanRatio(Pose pose, Size imageSize) {
    final s = pose.landmarks[PoseLandmarkType.leftShoulder] ??
        pose.landmarks[PoseLandmarkType.rightShoulder];
    final h = pose.landmarks[PoseLandmarkType.leftHip] ??
        pose.landmarks[PoseLandmarkType.rightHip];
    if (s == null || h == null) return 0;
    return ((s.x - h.x) / imageSize.width).abs();
  }

  double _currentBarPathDriftRatio(Pose pose, Size imageSize) {
    final lw = pose.landmarks[PoseLandmarkType.leftWrist];
    final rw = pose.landmarks[PoseLandmarkType.rightWrist];
    final s = pose.landmarks[PoseLandmarkType.leftShoulder] ??
        pose.landmarks[PoseLandmarkType.rightShoulder];
    if (s == null) return 0;
    final w = lw ?? rw;
    if (w == null) return 0;
    return ((w.x - s.x) / imageSize.width).abs();
  }

  void _maybeSpeak(String text) {
    if (!_voiceOn) return;
    final now = DateTime.now();
    // Min 2.5s between announcements; never repeat same cue twice in 6s.
    if (now.difference(_lastCueSpokenAt).inMilliseconds < 2500) return;
    if (text == _lastSpokenCue &&
        now.difference(_lastCueSpokenAt).inSeconds < 6) {
      return;
    }
    _lastCueSpokenAt = now;
    _lastSpokenCue = text;
    _tts.stop();
    _tts.speak(text);
  }

  void _toggleVoice() {
    setState(() => _voiceOn = !_voiceOn);
    if (!_voiceOn) _tts.stop();
  }

  _LiveCue? _evaluateLive(Pose p, Size imageSize) {
    final lift = _selected.name.toLowerCase();
    if (lift == 'squat') return _liveSquat(p, imageSize);
    if (lift.startsWith('deadlift') || lift.contains('rdl')) {
      return _liveHinge(p, imageSize);
    }
    if (lift.startsWith('bench')) return _liveBench(p, imageSize);
    if (lift.startsWith('overhead') || lift == 'ohp') {
      return _liveOhp(p, imageSize);
    }
    if (lift == 'row') return _liveRow(p, imageSize);
    if (lift.contains('pulldown')) return _liveLatPulldown(p);
    if (lift.contains('push')) return _livePushup(p, imageSize);
    if (lift.contains('lunge') || lift.contains('split')) {
      return _liveLunge(p, imageSize);
    }
    return null;
  }

  _LiveCue? _liveSquat(Pose p, Size sz) {
    final shoulder = p.landmarks[PoseLandmarkType.leftShoulder] ??
        p.landmarks[PoseLandmarkType.rightShoulder];
    final hip = p.landmarks[PoseLandmarkType.leftHip] ??
        p.landmarks[PoseLandmarkType.rightHip];
    final knee = p.landmarks[PoseLandmarkType.leftKnee] ??
        p.landmarks[PoseLandmarkType.rightKnee];
    if (shoulder == null || hip == null || knee == null) return null;
    final torsoLean = ((shoulder.x - hip.x) / sz.width).abs();
    switch (_phase) {
      case _RepPhase.standing:
        return _LiveCue('Ready when you are.', AppTheme.textPrimary);
      case _RepPhase.descending:
        if (torsoLean > 0.22) {
          return _LiveCue('Chest up — stop folding.', AppTheme.accentRed);
        }
        return _LiveCue('Down — control it.', AppTheme.textPrimary);
      case _RepPhase.atBottom:
        if (hip.y < knee.y - sz.height * 0.04) {
          return _LiveCue('Go deeper — hip below knee.', AppTheme.accentAmber);
        }
        if (torsoLean > 0.20) {
          return _LiveCue('Brace harder, chest proud.', AppTheme.accentRed);
        }
        return _LiveCue('Solid depth — drive up.', AppTheme.neonLime);
      case _RepPhase.ascending:
        return _LiveCue('Stand tall, squeeze glutes.', AppTheme.neonLime);
    }
  }

  _LiveCue? _liveHinge(Pose p, Size sz) {
    final shoulder = p.landmarks[PoseLandmarkType.leftShoulder] ??
        p.landmarks[PoseLandmarkType.rightShoulder];
    final hip = p.landmarks[PoseLandmarkType.leftHip] ??
        p.landmarks[PoseLandmarkType.rightHip];
    if (shoulder == null || hip == null) return null;
    if (shoulder.y > hip.y - sz.height * 0.05) {
      return _LiveCue('Watch the rounding — chest proud.', AppTheme.accentRed);
    }
    return _LiveCue('Push the floor away.', AppTheme.neonLime);
  }

  _LiveCue? _liveBench(Pose p, Size sz) {
    final shoulder = p.landmarks[PoseLandmarkType.leftShoulder] ??
        p.landmarks[PoseLandmarkType.rightShoulder];
    final elbow = p.landmarks[PoseLandmarkType.leftElbow] ??
        p.landmarks[PoseLandmarkType.rightElbow];
    final wrist = p.landmarks[PoseLandmarkType.leftWrist] ??
        p.landmarks[PoseLandmarkType.rightWrist];
    if (shoulder == null || elbow == null || wrist == null) return null;
    final flareDelta = (elbow.x - shoulder.x).abs() / sz.width;
    if (flareDelta > 0.28) {
      return _LiveCue('Tuck elbows ~45° in.', AppTheme.accentAmber);
    }
    return _LiveCue('Control the bar down to chest.', AppTheme.neonLime);
  }

  _LiveCue? _liveOhp(Pose p, Size sz) {
    final shoulder = p.landmarks[PoseLandmarkType.leftShoulder] ??
        p.landmarks[PoseLandmarkType.rightShoulder];
    final hip = p.landmarks[PoseLandmarkType.leftHip] ??
        p.landmarks[PoseLandmarkType.rightHip];
    if (shoulder == null || hip == null) return null;
    final lean = ((shoulder.x - hip.x) / sz.width).abs();
    if (lean > 0.18) {
      return _LiveCue('Ribs down — glutes squeezed.', AppTheme.accentRed);
    }
    return _LiveCue('Press to lockout, ears past arms.', AppTheme.neonLime);
  }

  _LiveCue? _liveRow(Pose p, Size sz) {
    final shoulder = p.landmarks[PoseLandmarkType.leftShoulder] ??
        p.landmarks[PoseLandmarkType.rightShoulder];
    final hip = p.landmarks[PoseLandmarkType.leftHip] ??
        p.landmarks[PoseLandmarkType.rightHip];
    if (shoulder == null || hip == null) return null;
    return _LiveCue('Elbows drive back, torso still.', AppTheme.neonLime);
  }

  _LiveCue? _liveLatPulldown(Pose p) {
    final lw = p.landmarks[PoseLandmarkType.leftWrist];
    final rw = p.landmarks[PoseLandmarkType.rightWrist];
    final ls = p.landmarks[PoseLandmarkType.leftShoulder];
    final rs = p.landmarks[PoseLandmarkType.rightShoulder];
    if (lw == null || rw == null || ls == null || rs == null) return null;
    final wAvg = (lw.y + rw.y) / 2;
    final sAvg = (ls.y + rs.y) / 2;
    if (wAvg < sAvg) {
      return _LiveCue('Pull the bar to your chest.', AppTheme.accentAmber);
    }
    return _LiveCue('Lats lead — elbows down and back.', AppTheme.neonLime);
  }

  _LiveCue? _livePushup(Pose p, Size sz) {
    final s = p.landmarks[PoseLandmarkType.leftShoulder] ??
        p.landmarks[PoseLandmarkType.rightShoulder];
    final h = p.landmarks[PoseLandmarkType.leftHip] ??
        p.landmarks[PoseLandmarkType.rightHip];
    final a = p.landmarks[PoseLandmarkType.leftAnkle] ??
        p.landmarks[PoseLandmarkType.rightAnkle];
    if (s == null || h == null || a == null) return null;
    // Hip should sit on the line from shoulder to ankle.
    final lineLen = ((a.x - s.x) * (a.x - s.x) + (a.y - s.y) * (a.y - s.y));
    if (lineLen == 0) return null;
    final numerator =
        ((a.y - s.y) * h.x - (a.x - s.x) * h.y + a.x * s.y - a.y * s.x).abs();
    final dist = numerator / sz.height;
    if (dist > 0.06) {
      return _LiveCue('Hips in line — brace your core.', AppTheme.accentAmber);
    }
    return _LiveCue('Solid plank — chest to floor.', AppTheme.neonLime);
  }

  _LiveCue? _liveLunge(Pose p, Size sz) {
    final s = p.landmarks[PoseLandmarkType.leftShoulder] ??
        p.landmarks[PoseLandmarkType.rightShoulder];
    final h = p.landmarks[PoseLandmarkType.leftHip] ??
        p.landmarks[PoseLandmarkType.rightHip];
    if (s == null || h == null) return null;
    final lean = ((s.x - h.x) / sz.width).abs();
    if (lean > 0.12) {
      return _LiveCue('Torso tall — front heel planted.', AppTheme.accentAmber);
    }
    return _LiveCue('Front knee tracks your toes.', AppTheme.neonLime);
  }

  Future<void> _toggleCamera() async {
    await _stopStream();
    await _disposeCamera();
    _lensDirection = _lensDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    _resetLiveState();
    await _initCamera();
  }

  void _resetLiveState() {
    _livePose = null;
    _liveCue = '';
    _hipBaselineY = null;
    _prevHipY = null;
    _phase = _RepPhase.standing;
    _repCount = 0;
    _score = 100;
    _fps = 0;
    _detectTimestamps.clear();
    _framingMsg = '';
    _statusMsg = 'Ready — squat when you like.';
    _maxHipDepthThisRep = 0;
    _maxLeanThisRep = 0;
    _maxBarPathDriftThisRep = 0;
  }

  Future<void> _startLive() async {
    setState(() {
      _stage = _Stage.live;
      _result = null;
      _analyzeError = '';
      _collectedFrames.clear();
    });
    _resetLiveState();
    await _initCamera();
  }

  Future<void> _endSet() async {
    if (_collectedFrames.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Capture a few more reps before ending the set.')),
      );
      return;
    }
    await _stopStream();
    // Grab one last JPEG for storage
    try {
      final file = await _camera?.takePicture();
      if (file != null) _lastJpeg = await File(file.path).readAsBytes();
    } catch (_) {}
    await _disposeCamera();
    setState(() => _stage = _Stage.analyzing);
    await _runFinalAnalysis();
  }

  Future<void> _runFinalAnalysis() async {
    try {
      // Build a synthetic quality report from the live capture's average likelihood
      final avg = _collectedFrames.isEmpty
          ? 0.0
          : _collectedFrames
                  .map((f) => f.avgLikelihood)
                  .reduce((a, b) => a + b) /
              _collectedFrames.length;
      final visibility = (avg * 100).clamp(0, 100).toInt();
      final quality = QualityReport(
        usable: visibility >= 40,
        blurScore: 80,
        brightnessScore: 80,
        framingScore: visibility,
        angleScore: 75,
        subjectVisibilityScore: visibility,
        issues: visibility < 55 ? ['subject_not_visible'] : const [],
        userMessage: visibility < 55
            ? "We didn't see you clearly during this set — try better lighting next time."
            : 'Live capture looked good.',
      );

      final biomech =
          PoseService.computeBiomech(_collectedFrames, _selected.name);

      final history = await _fetchRecentHistory(_selected.name);
      final profile = ProfileService.current;
      final result = await AICoachService.analyzeForm(
        lift: _selected.name,
        biomech: biomech,
        quality: quality,
        recentHistory: history,
        userReportedPain: _painCtrl.text,
        profile: profile,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _stage = _Stage.results;
      });
      _persistResult(result, biomech, quality);
      if (result.safetyFlag) {
        _maybeSpeak(result.safetyReason);
      } else if (result.coachingCue.isNotEmpty) {
        _maybeSpeak(result.coachingCue);
      } else {
        _maybeSpeak(result.keyCorrection);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzeError = '$e';
        _stage = _Stage.results;
      });
    }
  }

  Future<List<FormCheckResult>> _fetchRecentHistory(String lift) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('form_checks')
          .where('lift', isEqualTo: lift)
          .orderBy('createdAt', descending: true)
          .limit(3)
          .get();
      return snap.docs
          .map((d) {
            try {
              return FormCheckResult.fromJson(d.data());
            } catch (_) {
              return null;
            }
          })
          .whereType<FormCheckResult>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persistResult(
    FormCheckResult r,
    BiomechSummary b,
    QualityReport q,
  ) async {
    try {
      await FirebaseFirestore.instance.collection('form_checks').add({
        ...r.toJson(),
        'biomech': b.toJson(),
        'quality': q.toJson(),
        'reps': _repCount,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  void _reset() {
    setState(() {
      _stage = _Stage.pickLift;
      _result = null;
      _analyzeError = '';
      _collectedFrames.clear();
      _lastJpeg = null;
      _painCtrl.clear();
    });
    _resetLiveState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: _stage != _Stage.pickLift,
        title: const Text('Form Check'),
        leading: _stage != _Stage.pickLift
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () async {
                  await _stopStream();
                  await _disposeCamera();
                  _reset();
                },
              )
            : null,
      ),
      body: switch (_stage) {
        _Stage.pickLift => _buildLiftPicker(),
        _Stage.live => _buildLive(),
        _Stage.analyzing => _buildAnalyzing(),
        _Stage.results => _buildResults(),
      },
    );
  }

  Widget _buildLiftPicker() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pick a lift to check',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            const Text(
              'Live video coaching — we run pose detection on-device and give you real-time cues as you lift.',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: _coreLifts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final l = _coreLifts[i];
                  final sel = l.name == _selected.name;
                  return GestureDetector(
                    onTap: () => setState(() => _selected = l),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: sel
                            ? LinearGradient(
                                colors: [
                                  AppTheme.neonLime.withValues(alpha: 0.12),
                                  AppTheme.neonCyan.withValues(alpha: 0.05),
                                ],
                              )
                            : null,
                        color: sel ? null : AppTheme.cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: sel
                              ? AppTheme.neonLime
                              : AppTheme.hairline,
                          width: sel ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(l.icon,
                              color: sel
                                  ? AppTheme.neonLime
                                  : AppTheme.textPrimary,
                              size: 26),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.name,
                                    style: const TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15.5)),
                                const SizedBox(height: 2),
                                Text(l.tagline,
                                    style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 12.5)),
                              ],
                            ),
                          ),
                          if (sel)
                            const Icon(Icons.check_circle,
                                color: AppTheme.neonLime, size: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _painCtrl,
              maxLines: 1,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                hintText: "Anything bothering you today? (optional)",
                prefixIcon: Icon(Icons.healing_outlined,
                    color: AppTheme.textSecondary, size: 18),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _startLive,
                icon: const Icon(Icons.videocam_rounded),
                label: Text('Start live form check — ${_selected.name}'),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildLive() {
    if (_cameraError.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.no_photography,
                color: AppTheme.accentRed, size: 48),
            const SizedBox(height: 16),
            Text(_cameraError,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _reset, child: const Text('Go back')),
          ],
        ),
      );
    }
    if (!_cameraReady) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.neonLime));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview
        Center(
          child: AspectRatio(
            aspectRatio: _camera!.value.aspectRatio,
            child: CameraPreview(_camera!),
          ),
        ),
        // Pose skeleton overlay
        if (_livePose != null && _liveImageSize != null)
          IgnorePointer(
            child: CustomPaint(
              painter: _LivePosePainter(
                pose: _livePose!,
                imageSize: _liveImageSize!,
                mirror: _lensDirection == CameraLensDirection.front,
              ),
            ),
          ),
        // Top-left HUD: lift, reps, score, fps, voice
        Positioned(
          top: 14,
          left: 12,
          right: 12,
          child: _LiveHudBar(
            lift: _selected.name,
            phase: _phase,
            reps: _repCount,
            score: _score,
            fps: _fps,
            voiceOn: _voiceOn,
            onToggleVoice: _toggleVoice,
          ),
        ),
        // Right-edge score bar (vertical) — quick glance gauge
        Positioned(
          right: 12,
          top: 84,
          bottom: 140,
          child: _ScoreBar(score: _score),
        ),
        // Centered framing message (only shows when framing fails)
        if (_framingMsg.isNotEmpty)
          Center(
            child: _CenteredOverlay(text: _framingMsg),
          ),
        // Live cue chip (bottom-center)
        if (_liveCue.isNotEmpty && _framingMsg.isEmpty)
          Positioned(
            bottom: 100,
            left: 20,
            right: 20,
            child: _CueChip(text: _liveCue, color: _liveCueColor),
          ),
        // Status footer (above controls)
        Positioned(
          bottom: 78,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _statusMsg,
                style: const TextStyle(
                  color: AppTheme.neonLime,
                  fontFamily: 'Courier',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        // Bottom: controls
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: _LiveControls(
            onFlip: _toggleCamera,
            onEnd: _endSet,
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyzing() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppTheme.neonLime),
            const SizedBox(height: 20),
            Text('Crunching your set…',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '${_collectedFrames.length} pose frames captured · $_repCount reps',
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_analyzeError.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber, color: AppTheme.accentRed, size: 48),
            const SizedBox(height: 12),
            Text('Analysis failed',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(_analyzeError,
                style: const TextStyle(color: AppTheme.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _reset, child: const Text('Try again')),
          ],
        ),
      );
    }
    final r = _result!;
    final lowConf = r.lowConfidence;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.safetyFlag) _SafetyBanner(reason: r.safetyReason),
          if (r.safetyFlag) const SizedBox(height: 14),
          if (lowConf && !r.safetyFlag) const _LowConfBanner(),
          if (lowConf && !r.safetyFlag) const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                  child: _ScoreCard(
                      label: 'Form score',
                      value: '${r.formScore}',
                      color: _scoreColor(r.formScore))),
              const SizedBox(width: 10),
              Expanded(
                  child: _ScoreCard(
                      label: 'Reps',
                      value: '$_repCount',
                      color: AppTheme.neonCyan)),
              const SizedBox(width: 10),
              Expanded(
                  child: _ScoreCard(
                      label: 'Confidence',
                      value: '${r.confidence}',
                      color: _scoreColor(r.confidence))),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Key correction',
            body: r.keyCorrection,
            icon: Icons.center_focus_strong,
            accent: AppTheme.neonLime,
          ),
          if (r.coachingCue.isNotEmpty) ...[
            const SizedBox(height: 10),
            _CoachingCueCard(cue: r.coachingCue),
          ],
          if (r.rubric.isNotEmpty) ...[
            const SizedBox(height: 10),
            _RubricCard(rubric: r.rubric),
          ],
          if (r.drills.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DrillsCard(drills: r.drills),
          ],
          if (r.whatWentWell.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Section(
              title: 'What went well',
              body: r.whatWentWell,
              icon: Icons.thumb_up_alt_outlined,
              accent: AppTheme.neonCyan,
            ),
          ],
          if (r.watchOuts.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Section(
              title: 'Watch on next set',
              icon: Icons.visibility_outlined,
              accent: AppTheme.textSecondary,
              bullets: r.watchOuts,
            ),
          ],
          const SizedBox(height: 14),
          TrainerNetworkCard(
            title: lowConf || r.safetyFlag
                ? 'AI confidence was limited here'
                : 'Want a definitive review?',
            description: lowConf || r.safetyFlag
                ? 'A vetted coach can review the same set and give you a clear answer.'
                : 'A vetted coach can validate your form and prescribe a custom drill.',
            ctaLabel: 'Request a coach review · \$9',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CoachReviewScreen(
                    lift: _selected.name,
                    frames: _lastJpeg == null ? const [] : [_lastJpeg!],
                    aiResult: r,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const TrainerNetworkScreen()),
              ),
              icon: const Icon(Icons.support_agent_rounded,
                  size: 16, color: AppTheme.neonCyan),
              label: const Text('Browse the trainer network',
                  style: TextStyle(
                      color: AppTheme.neonCyan,
                      fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Another set'),
            ),
          ),
        ],
      ),
    );
  }

  Color _scoreColor(int n) {
    if (n >= 80) return AppTheme.neonLime;
    if (n >= 60) return AppTheme.neonCyan;
    return AppTheme.accentRed;
  }
}

class _LiveCue {
  final String text;
  final Color color;
  const _LiveCue(this.text, this.color);
}

extension on PoseFrame {
  DateTime capturedAt() => DateTime.now();
}

// ─── Live HUD & controls ──────────────────────────────────────────────────────

/// Compact monospace HUD bar styled after the reference squat-coach demo:
/// `LIFT | Reps N | Score 100 | 22 fps | Voice ON`.
class _LiveHudBar extends StatelessWidget {
  final String lift;
  final _RepPhase phase;
  final int reps;
  final int score;
  final int fps;
  final bool voiceOn;
  final VoidCallback onToggleVoice;
  const _LiveHudBar({
    required this.lift,
    required this.phase,
    required this.reps,
    required this.score,
    required this.fps,
    required this.voiceOn,
    required this.onToggleVoice,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.neonLime.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _hudChip(text: lift.toUpperCase(), color: AppTheme.neonLime),
              const _Sep(),
              _hudChip(text: 'Reps $reps', color: Colors.white),
              const _Sep(),
              _hudChip(
                  text: 'Score $score',
                  color: score >= 80
                      ? AppTheme.neonLime
                      : (score >= 60
                          ? AppTheme.accentAmber
                          : AppTheme.accentRed)),
              const _Sep(),
              _hudChip(
                  text: '$fps fps',
                  color: fps >= 5 ? Colors.white70 : AppTheme.accentAmber),
              const _Sep(),
              GestureDetector(
                onTap: onToggleVoice,
                child: _hudChip(
                  text: 'Voice ${voiceOn ? 'ON' : 'OFF'}',
                  color: voiceOn ? AppTheme.neonCyan : Colors.white54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Phase: ${phase.label}',
            style: const TextStyle(
              color: AppTheme.neonLime,
              fontFamily: 'Courier',
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hudChip({required String text, required Color color}) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontFamily: 'Courier',
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Text('|',
            style: TextStyle(
                color: Colors.white24,
                fontSize: 12,
                fontWeight: FontWeight.w400)),
      );
}

/// Right-edge vertical "Pose" / score gauge that pulses when score drops.
class _ScoreBar extends StatelessWidget {
  final int score;
  const _ScoreBar({required this.score});

  @override
  Widget build(BuildContext context) {
    final color = score >= 80
        ? AppTheme.neonLime
        : (score >= 60 ? AppTheme.accentAmber : AppTheme.accentRed);
    return Container(
      width: 14,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.white24),
      ),
      padding: const EdgeInsets.all(2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: (score / 100).clamp(0.02, 1.0),
                child: Container(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Big centered text like the reference's "Step into frame" overlay.
class _CenteredOverlay extends StatelessWidget {
  final String text;
  const _CenteredOverlay({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          shadows: [
            Shadow(color: Colors.black, blurRadius: 6),
          ],
        ),
      ),
    );
  }
}

/// Single-line live cue chip, bottom-centered above status footer.
class _CueChip extends StatelessWidget {
  final String text;
  final Color color;
  const _CueChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Container(
        key: ValueKey(text),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.75)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.record_voice_over_rounded, color: color, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  color: color,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveControls extends StatelessWidget {
  final VoidCallback onFlip;
  final VoidCallback onEnd;
  const _LiveControls({required this.onFlip, required this.onEnd});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundButton(
          icon: Icons.cameraswitch_rounded,
          onTap: onFlip,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentRed,
                foregroundColor: Colors.white,
              ),
              onPressed: onEnd,
              icon: const Icon(Icons.stop_circle_rounded),
              label: const Text('End set'),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
          border: Border.all(
              color: AppTheme.neonLime.withValues(alpha: 0.6), width: 2),
        ),
        child: Icon(icon, color: AppTheme.neonLime, size: 24),
      ),
    );
  }
}

// ─── Live pose painter ────────────────────────────────────────────────────────

class _LivePosePainter extends CustomPainter {
  final Pose pose;
  final Size imageSize;
  final bool mirror;

  _LivePosePainter({
    required this.pose,
    required this.imageSize,
    required this.mirror,
  });

  static const _bones = [
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width == 0 || imageSize.height == 0) return;
    // Camera preview is fit to the screen — assume aspect-fill, so compute scale
    final scaleX = size.width / imageSize.height; // sensor rotated landscape
    final scaleY = size.height / imageSize.width;
    final scale = (scaleX > scaleY) ? scaleX : scaleY;

    Offset map(PoseLandmark lm) {
      // Convert from image coords; for a portrait preview the sensor is
      // landscape so x/y swap. This works well enough for the common case.
      var x = lm.y * scale;
      var y = (imageSize.width - lm.x) * scale;
      if (mirror) x = size.width - x;
      return Offset(x, y);
    }

    // White lines with soft halo + cyan joints — matches the reference's look.
    final bonePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    final boneHalo = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;
    final jointPaint = Paint()..color = AppTheme.neonCyan;
    final jointRing = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final pair in _bones) {
      final a = pose.landmarks[pair[0]];
      final b = pose.landmarks[pair[1]];
      if (a == null || b == null) continue;
      if (a.likelihood < 0.4 || b.likelihood < 0.4) continue;
      final p1 = map(a);
      final p2 = map(b);
      canvas.drawLine(p1, p2, boneHalo);
      canvas.drawLine(p1, p2, bonePaint);
    }

    for (final entry in pose.landmarks.entries) {
      final lm = entry.value;
      if (lm.likelihood < 0.4) return;
      final p = map(lm);
      canvas.drawCircle(p, 4.5, jointPaint);
      canvas.drawCircle(p, 4.5, jointRing);
    }
  }

  @override
  bool shouldRepaint(covariant _LivePosePainter old) =>
      old.pose != pose || old.imageSize != imageSize || old.mirror != mirror;
}

// ─── Result widgets (preserved) ───────────────────────────────────────────────

class _SafetyBanner extends StatelessWidget {
  final String reason;
  const _SafetyBanner({required this.reason});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accentRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accentRed),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber, color: AppTheme.accentRed),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Safety flag',
                    style: TextStyle(
                        color: AppTheme.accentRed,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(reason,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LowConfBanner extends StatelessWidget {
  const _LowConfBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.neonCyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.5)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: AppTheme.neonCyan),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "We weren't sure about this set — consider a quick human coach review.",
              style: TextStyle(color: AppTheme.textPrimary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _ScoreCard({
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  height: 1)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? body;
  final List<String>? bullets;
  final IconData icon;
  final Color accent;
  const _Section({
    required this.title,
    this.body,
    this.bullets,
    required this.icon,
    required this.accent,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 16),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          if (body != null)
            Text(body!,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 14, height: 1.5)),
          if (bullets != null)
            ...bullets!.map((b) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Icon(Icons.circle,
                            color: AppTheme.textSecondary, size: 4.5),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(b,
                            style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 13.5,
                                height: 1.45)),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

class _CoachingCueCard extends StatelessWidget {
  final String cue;
  const _CoachingCueCard({required this.cue});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.neonLime.withValues(alpha: 0.18),
            AppTheme.neonCyan.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.neonLime.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.record_voice_over,
                  color: AppTheme.neonLime, size: 16),
              SizedBox(width: 6),
              Text('Cue for next set',
                  style: TextStyle(
                      color: AppTheme.neonLime,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Text('"$cue"',
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 17,
                  fontStyle: FontStyle.italic,
                  height: 1.35,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _RubricCard extends StatelessWidget {
  final List<RubricScore> rubric;
  const _RubricCard({required this.rubric});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.list_alt, color: AppTheme.neonCyan, size: 16),
              SizedBox(width: 6),
              Text('Per-fault rubric',
                  style: TextStyle(
                      color: AppTheme.neonCyan,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
              SizedBox(width: 6),
              Text('· measured on-device',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 10),
          ...rubric.map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 116,
                      child: Text(r.name,
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 12.5)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: r.score / 100,
                          minHeight: 7,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            r.score >= 80
                                ? AppTheme.neonLime
                                : (r.score >= 60
                                    ? AppTheme.neonCyan
                                    : AppTheme.accentRed),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 28,
                      child: Text('${r.score}',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _DrillsCard extends StatelessWidget {
  final List<CorrectiveDrill> drills;
  const _DrillsCard({required this.drills});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.sports_gymnastics,
                  color: AppTheme.neonLime, size: 16),
              SizedBox(width: 6),
              Text('Corrective drills',
                  style: TextStyle(
                      color: AppTheme.neonLime,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          ...drills.map((d) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.neonLime.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(d.dose,
                          style: const TextStyle(
                              color: AppTheme.neonLime,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.name,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(d.howTo,
                              style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12.5,
                                  height: 1.4)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
