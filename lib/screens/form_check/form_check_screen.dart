import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../models/form_check.dart';
import '../../services/claude_service.dart';
import '../../services/profile_service.dart';
import '../../theme.dart';
import '../coach/coach_review_screen.dart';
import '../settings/settings_screen.dart';

class CoreLift {
  final String name;
  final String tagline;
  final IconData icon;
  final String cameraAngle; // "side" | "front" | "45"
  final String angleHint;
  final List<String> positionLabels;

  const CoreLift({
    required this.name,
    required this.tagline,
    required this.icon,
    required this.cameraAngle,
    required this.angleHint,
    required this.positionLabels,
  });
}

const _coreLifts = <CoreLift>[
  CoreLift(
    name: 'Squat',
    tagline: 'Hips below knees, knees tracking toes',
    icon: Icons.accessibility_new,
    cameraAngle: 'side',
    angleHint:
        'Place phone on the floor or a bench ~3m from you, at hip height, profile view.',
    positionLabels: ['Standing tall', 'Bottom of squat', 'Standing tall'],
  ),
  CoreLift(
    name: 'Deadlift / RDL',
    tagline: 'Neutral spine, hinge from the hips',
    icon: Icons.fitness_center,
    cameraAngle: 'side',
    angleHint:
        'Phone ~3m to your side at hip height. We need to see your spine clearly.',
    positionLabels: ['Setup position', 'Bottom / hinge', 'Lockout'],
  ),
  CoreLift(
    name: 'Bench Press',
    tagline: 'Bar to chest, no shoulder shrug',
    icon: Icons.airline_seat_flat,
    cameraAngle: 'side',
    angleHint:
        'Phone at bench height, ~2m to the side. Whole bar path visible.',
    positionLabels: ['Lockout', 'Bar touches chest', 'Lockout'],
  ),
  CoreLift(
    name: 'Overhead Press',
    tagline: 'Vertical bar path, ribs down',
    icon: Icons.arrow_upward,
    cameraAngle: 'side',
    angleHint: 'Phone ~3m to your side at chest height, profile view.',
    positionLabels: ['Rack position', 'Lockout overhead', 'Rack position'],
  ),
  CoreLift(
    name: 'Row',
    tagline: 'Elbows drive back, lats engage first',
    icon: Icons.swap_horiz,
    cameraAngle: 'side',
    angleHint: 'Phone ~3m to the side, hip-to-shoulder height.',
    positionLabels: ['Bottom (arms long)', 'Top (elbow back)', 'Bottom'],
  ),
  CoreLift(
    name: 'Lat Pulldown',
    tagline: 'Bar to upper chest, scaps down first',
    icon: Icons.vertical_align_bottom,
    cameraAngle: 'front',
    angleHint: 'Phone in front of you, ~3m away, chest height.',
    positionLabels: ['Arms extended', 'Bar at chest', 'Arms extended'],
  ),
  CoreLift(
    name: 'Push-up',
    tagline: 'Plank line, scaps protract at top',
    icon: Icons.horizontal_rule,
    cameraAngle: 'side',
    angleHint: 'Phone on the floor ~2m to your side. Profile view.',
    positionLabels: ['Top (arms locked)', 'Bottom (chest near floor)', 'Top'],
  ),
  CoreLift(
    name: 'Lunge / Split Squat',
    tagline: 'Front knee tracks, torso upright',
    icon: Icons.directions_walk,
    cameraAngle: 'side',
    angleHint: 'Phone ~3m to your side at hip height.',
    positionLabels: ['Standing', 'Bottom of lunge', 'Standing'],
  ),
];

class FormCheckScreen extends StatefulWidget {
  const FormCheckScreen({super.key});

  @override
  State<FormCheckScreen> createState() => _FormCheckScreenState();
}

enum _Stage { pickLift, anglePrep, capture, analyzing, results }

class _FormCheckScreenState extends State<FormCheckScreen> {
  CoreLift _selected = _coreLifts.first;
  _Stage _stage = _Stage.pickLift;

  // Camera
  CameraController? _camera;
  bool _cameraReady = false;
  String _cameraError = '';

  // Capture state
  int _frameIndex = 0;
  final List<Uint8List> _frames = [];
  bool _capturing = false;
  String _countdownText = '';

  // TTS
  final FlutterTts _tts = FlutterTts();

  // Result
  FormCheckResult? _result;
  String _analyzeError = '';

  // User pain input (optional)
  final TextEditingController _painCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.5);
  }

  @override
  void dispose() {
    _disposeCamera();
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
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _cameraError = 'No camera available on this device.');
        return;
      }
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      _camera = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _camera!.initialize();
      if (!mounted) return;
      setState(() {
        _cameraReady = true;
        _cameraError = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cameraError = 'Camera not available: $e');
    }
  }

  void _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _startCapture() async {
    setState(() {
      _stage = _Stage.capture;
      _frameIndex = 0;
      _frames.clear();
      _analyzeError = '';
    });
    await _initCamera();
    if (!_cameraReady) return;
    await _captureNextFrame();
  }

  Future<void> _captureNextFrame() async {
    if (!mounted || _camera == null || !_cameraReady) return;
    final label = _selected.positionLabels[_frameIndex];
    _speak('Get into position: $label. Capturing in 3.');
    for (var i = 3; i >= 1; i--) {
      if (!mounted) return;
      setState(() => _countdownText = '$i');
      await Future.delayed(const Duration(seconds: 1));
    }
    if (!mounted) return;
    setState(() {
      _countdownText = '';
      _capturing = true;
    });
    try {
      final file = await _camera!.takePicture();
      final bytes = await File(file.path).readAsBytes();
      _frames.add(bytes);
    } catch (e) {
      setState(() => _analyzeError = 'Capture failed: $e');
      return;
    }
    setState(() => _capturing = false);

    _frameIndex += 1;
    if (_frameIndex < _selected.positionLabels.length) {
      await Future.delayed(const Duration(milliseconds: 400));
      await _captureNextFrame();
    } else {
      await _analyze();
    }
  }

  Future<void> _analyze() async {
    setState(() => _stage = _Stage.analyzing);
    await _disposeCamera();
    try {
      final profile = ProfileService.current;
      final result = await ClaudeService.analyzeForm(
        lift: _selected.name,
        frames: _frames,
        framePositions: _selected.positionLabels,
        userReportedPain: _painCtrl.text,
        profile: profile,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _stage = _Stage.results;
      });
      _persistResult(result);
      if (result.safetyFlag) {
        _speak('Safety flag: ${result.safetyReason}. Consider a coach review.');
      } else {
        _speak(result.keyCorrection);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzeError = '$e';
        _stage = _Stage.results;
      });
    }
  }

  Future<void> _persistResult(FormCheckResult r) async {
    try {
      await FirebaseFirestore.instance.collection('form_checks').add({
        ...r.toJson(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Offline — silently fall back.
    }
  }

  void _reset() {
    setState(() {
      _stage = _Stage.pickLift;
      _frames.clear();
      _frameIndex = 0;
      _result = null;
      _analyzeError = '';
      _painCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Form Check'),
        leading: _stage != _Stage.pickLift
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () async {
                  await _disposeCamera();
                  _reset();
                },
              )
            : null,
        actions: _stage == _Stage.pickLift
            ? [
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SettingsScreen()),
                  ),
                ),
              ]
            : null,
      ),
      body: switch (_stage) {
        _Stage.pickLift => _buildLiftPicker(),
        _Stage.anglePrep => _buildAnglePrep(),
        _Stage.capture => _buildCapture(),
        _Stage.analyzing => _buildAnalyzing(),
        _Stage.results => _buildResults(),
      },
    );
  }

  Widget _buildLiftPicker() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pick a lift to check',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            const Text(
              'We support 8 core lifts. Pick one and we\'ll walk you through capturing a clean rep.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: _coreLifts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final l = _coreLifts[i];
                  final selected = l.name == _selected.name;
                  return GestureDetector(
                    onTap: () => setState(() => _selected = l),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.neonLime.withOpacity(0.08)
                            : AppTheme.cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              selected ? AppTheme.neonLime : Colors.white12,
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(l.icon,
                              color: selected
                                  ? AppTheme.neonLime
                                  : AppTheme.textPrimary,
                              size: 28),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.name,
                                    style: const TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                const SizedBox(height: 4),
                                Text(l.tagline,
                                    style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                          if (selected)
                            const Icon(Icons.check_circle,
                                color: AppTheme.neonLime, size: 22),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.neonLime,
                  foregroundColor: AppTheme.darkBackground,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () =>
                    setState(() => _stage = _Stage.anglePrep),
                icon: const Icon(Icons.arrow_forward),
                label: Text('Set up ${_selected.name}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildAnglePrep() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Camera setup', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            const Text(
              "Camera angle matters for accuracy. Take a moment to set up.",
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            _AngleDiagram(angle: _selected.cameraAngle),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline,
                      color: AppTheme.neonCyan),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_selected.angleHint,
                        style: const TextStyle(
                            color: AppTheme.textPrimary, height: 1.4)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('What\'s happening',
                style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ..._selected.positionLabels.asMap().entries.map(
                  (e) => _StepRow(
                    n: e.key + 1,
                    title: e.value,
                    body: e.key == 0
                        ? "We'll count you down to 3 — be in position and hold."
                        : (e.key == _selected.positionLabels.length - 1
                            ? "Return to start, we capture the final frame."
                            : "Hit the key position and hold. Snap."),
                  ),
                ),
            const SizedBox(height: 20),
            const Text('Anything bothering you right now?',
                style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _painCtrl,
              maxLines: 2,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.cardBg,
                hintText:
                    'Optional. e.g., "tight left hip" or "twinge in lower back"',
                hintStyle: const TextStyle(color: AppTheme.textSecondary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.neonLime,
                  foregroundColor: AppTheme.darkBackground,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _startCapture,
                icon: const Icon(Icons.camera_alt),
                label: const Text("I'm set — start capture",
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapture() {
    if (_cameraError.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.no_photography, color: AppTheme.accentRed, size: 48),
            const SizedBox(height: 16),
            Text(_cameraError, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 24),
            TextButton(
              onPressed: _reset,
              child: const Text('Go back'),
            ),
          ],
        ),
      );
    }
    if (!_cameraReady) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.neonLime));
    }
    final pos = _frameIndex < _selected.positionLabels.length
        ? _selected.positionLabels[_frameIndex]
        : '';
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_camera!),
        Container(color: Colors.black.withOpacity(0.25)),
        Positioned(
          top: 24,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Frame ${_frameIndex + 1} of ${_selected.positionLabels.length}',
                  style: const TextStyle(
                      color: AppTheme.neonLime,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(pos,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        if (_countdownText.isNotEmpty)
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppTheme.neonLime.withOpacity(0.85),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _countdownText,
                  style: const TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.darkBackground,
                  ),
                ),
              ),
            ),
          ),
        if (_capturing)
          Container(color: Colors.white.withOpacity(0.6)),
      ],
    );
  }

  Widget _buildAnalyzing() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppTheme.neonLime),
          const SizedBox(height: 24),
          Text('Analyzing your ${_selected.name}…',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Reviewing biomechanics across your captured frames.',
              style:
                  TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ],
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
            const Icon(Icons.warning_amber,
                color: AppTheme.accentRed, size: 48),
            const SizedBox(height: 12),
            Text('Analysis failed',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(_analyzeError,
                style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.neonLime,
                foregroundColor: AppTheme.darkBackground,
              ),
              onPressed: _reset,
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    final r = _result!;
    final lowConf = r.lowConfidence;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.safetyFlag) _SafetyBanner(reason: r.safetyReason),
          if (r.safetyFlag) const SizedBox(height: 16),
          if (lowConf && !r.safetyFlag) _LowConfBanner(),
          if (lowConf && !r.safetyFlag) const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _ScoreCard(
                      label: 'Form score',
                      value: '${r.formScore}',
                      color: _scoreColor(r.formScore))),
              const SizedBox(width: 12),
              Expanded(
                  child: _ScoreCard(
                      label: 'Confidence',
                      value: '${r.confidence}',
                      color: _scoreColor(r.confidence))),
            ],
          ),
          const SizedBox(height: 20),
          _Section(
              title: 'Key correction',
              body: r.keyCorrection,
              icon: Icons.center_focus_strong,
              accent: AppTheme.neonLime),
          if (r.whatWentWell.isNotEmpty) const SizedBox(height: 12),
          if (r.whatWentWell.isNotEmpty)
            _Section(
              title: 'What went well',
              body: r.whatWentWell,
              icon: Icons.thumb_up_alt_outlined,
              accent: AppTheme.neonCyan,
            ),
          if (r.watchOuts.isNotEmpty) const SizedBox(height: 12),
          if (r.watchOuts.isNotEmpty)
            _Section(
              title: 'Watch on next set',
              icon: Icons.visibility_outlined,
              accent: AppTheme.textSecondary,
              bullets: r.watchOuts,
            ),
          const SizedBox(height: 20),
          _CoachUpsell(
              lift: r.lift,
              frames: _frames,
              priority: r.safetyFlag || lowConf,
              aiResult: r),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textPrimary,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Another check'),
                ),
              ),
            ],
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

// ---- result widgets ----

class _SafetyBanner extends StatelessWidget {
  final String reason;
  const _SafetyBanner({required this.reason});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.accentRed.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accentRed),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber, color: AppTheme.accentRed),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Safety flag',
                    style: TextStyle(
                        color: AppTheme.accentRed,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                const SizedBox(height: 4),
                Text(reason,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, height: 1.4, fontSize: 14)),
                const SizedBox(height: 6),
                const Text(
                  'Stop loading this pattern until a coach or clinician reviews.',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LowConfBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.neonCyan.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.neonCyan.withOpacity(0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.info_outline, color: AppTheme.neonCyan),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "We weren't sure about this one — consider a quick human coach review.",
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
  const _ScoreCard(
      {required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      height: 1)),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('/ 100',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
              ),
            ],
          ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      color: accent,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          if (body != null)
            Text(body!,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 15, height: 1.4)),
          if (bullets != null)
            ...bullets!.map((b) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 7),
                        child: Icon(Icons.circle,
                            color: AppTheme.textSecondary, size: 5),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(b,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 14,
                                  height: 1.4))),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

class _CoachUpsell extends StatelessWidget {
  final String lift;
  final List<Uint8List> frames;
  final FormCheckResult aiResult;
  final bool priority;
  const _CoachUpsell({
    required this.lift,
    required this.frames,
    required this.aiResult,
    required this.priority,
  });

  void _open(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CoachReviewScreen(
          lift: lift,
          frames: frames,
          aiResult: aiResult,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.neonCyan.withOpacity(0.08),
            AppTheme.neonLime.withOpacity(0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: priority
                ? AppTheme.neonCyan
                : AppTheme.neonCyan.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.support_agent, color: AppTheme.neonCyan),
              SizedBox(width: 8),
              Text(
                'Human coach review',
                style: TextStyle(
                  color: AppTheme.neonCyan,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            priority
                ? 'AI confidence was limited here — a vetted coach can give you a definitive answer.'
                : 'Want a vetted human coach to review this same set? Response in under 24h.',
            style: const TextStyle(
                color: AppTheme.textPrimary, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.neonCyan,
                foregroundColor: AppTheme.darkBackground,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => _open(context),
              child: const Text('Request coach review · \$9',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- angle diagram ----

class _AngleDiagram extends StatelessWidget {
  final String angle;
  const _AngleDiagram({required this.angle});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: CustomPaint(painter: _AnglePainter(angle: angle)),
    );
  }
}

class _AnglePainter extends CustomPainter {
  final String angle;
  _AnglePainter({required this.angle});
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final personPaint = Paint()
      ..color = AppTheme.neonLime
      ..style = PaintingStyle.fill;
    final phonePaint = Paint()
      ..color = AppTheme.neonCyan
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = AppTheme.neonCyan.withOpacity(0.4)
      ..strokeWidth = 1.5;

    // person centered
    final px = w / 2;
    final py = h * 0.55;
    canvas.drawCircle(Offset(px, py - 22), 8, personPaint);
    canvas.drawRect(
        Rect.fromCenter(center: Offset(px, py), width: 16, height: 38),
        personPaint);

    // phone position
    Offset phone;
    String label;
    switch (angle) {
      case 'front':
        phone = Offset(px, h * 0.9);
        label = 'Phone in front (~3m)';
        break;
      case '45':
        phone = Offset(w * 0.85, h * 0.85);
        label = 'Phone at 45° (~3m)';
        break;
      default:
        phone = Offset(w * 0.92, py);
        label = 'Phone to the side (~3m)';
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: phone, width: 22, height: 12),
          const Radius.circular(2)),
      phonePaint,
    );
    final path = Path()
      ..moveTo(phone.dx, phone.dy)
      ..lineTo(px, py);
    canvas.drawPath(path, linePaint);

    final tp = TextPainter(
      text: TextSpan(
          text: label,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w - 24);
    tp.paint(canvas, Offset((w - tp.width) / 2, h - tp.height - 10));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StepRow extends StatelessWidget {
  final int n;
  final String title;
  final String body;
  const _StepRow({required this.n, required this.title, required this.body});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppTheme.neonLime.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.neonLime),
            ),
            child: Center(
              child: Text('$n',
                  style: const TextStyle(
                      color: AppTheme.neonLime,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600)),
                Text(body,
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
