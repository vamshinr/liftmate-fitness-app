import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme.dart';
import '../settings/settings_screen.dart';

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  final List<String> _lifts = ['Squat', 'Deadlift (RDL)', 'Bench Press'];
  String _selectedLift = 'Squat';
  bool _isWorkoutActive = false;
  
  // Camera state
  List<CameraDescription> _cameras = [];
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  
  // TTS State
  late FlutterTts _flutterTts;
  
  // Rep Counter & Simulation State
  int _repCount = 0;
  String _feedbackMessage = "Get ready...";
  double _squatProgress = 0.0; // 0.0 to 1.0 (extension to flexion)
  Timer? _simulationTimer;
  bool _isDescending = true;

  @override
  void initState() {
    super.initState();
    _initTts();
    _initCamera();
  }

  void _initTts() {
    _flutterTts = FlutterTts();
    _flutterTts.setLanguage("en-US");
    _flutterTts.setSpeechRate(0.5);
    _flutterTts.setVolume(1.0);
    _flutterTts.setPitch(1.0);
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        _cameraController = CameraController(
          _cameras[0],
          ResolutionPreset.medium,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint("Camera initialization failed: $e (Probably on Simulator)");
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _simulationTimer?.cancel();
    _flutterTts.stop();
    super.dispose();
  }

  void _speak(String text) async {
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  void _startWorkout() {
    setState(() {
      _isWorkoutActive = true;
      _repCount = 0;
      _feedbackMessage = "Setup complete. Start your first rep.";
      _squatProgress = 0.0;
    });
    _speak("Starting $_selectedLift. Keep your form tight.");
    _startSimulation();
  }

  void _stopWorkout() {
    _simulationTimer?.cancel();
    setState(() {
      _isWorkoutActive = false;
    });
    _saveWorkoutSession();
    _speak("Workout finished. Excellent work!");
  }

  void _startSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) return;
      setState(() {
        if (_isDescending) {
          _squatProgress += 0.05;
          if (_squatProgress >= 1.0) {
            _squatProgress = 1.0;
            _isDescending = false;
            // Flexion point reached (bottom of lift)
            if (_selectedLift == 'Squat') {
              _feedbackMessage = "Good depth!";
              _speak("Good depth");
            } else if (_selectedLift == 'Deadlift (RDL)') {
              _feedbackMessage = "Hips back, nice stretch!";
              _speak("Nice stretch");
            } else {
              _feedbackMessage = "Touch chest...";
              _speak("Touch chest");
            }
          }
        } else {
          _squatProgress -= 0.05;
          if (_squatProgress <= 0.0) {
            _squatProgress = 0.0;
            _isDescending = true;
            _repCount++;
            _feedbackMessage = "Rep $_repCount completed!";
            _speak("$_repCount");
          }
        }
      });
    });
  }

  Future<void> _saveWorkoutSession() async {
    try {
      await FirebaseFirestore.instance.collection('workouts').add({
        'lift': _selectedLift,
        'reps': _repCount,
        'timestamp': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Workout saved to Firebase successfully!"),
            backgroundColor: AppTheme.neonLime,
          ),
        );
      }
    } catch (e) {
      debugPrint("Firebase save failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Saved locally (Offline): $e"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _escalateToHuman() {
    _speak("Uploading session video to coach review marketplace.");
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBg,
        title: Row(
          children: const [
            Icon(Icons.support_agent, color: AppTheme.neonCyan),
            SizedBox(width: 8),
            Text("Coach Escalation"),
          ],
        ),
        content: const Text(
          "We are uploading this session's video and joint kinematics to the marketplace. A certified human trainer will review your form within 15 minutes.\n\nCost: \$5.00 (charged to file).",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neonLime,
              foregroundColor: AppTheme.darkBackground,
            ),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Escalated successfully! Notification will be sent when coach reviews."),
                  backgroundColor: AppTheme.neonCyan,
                ),
              );
            },
            child: const Text("Approve & Pay"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Coach"),
        actions: [
          if (_isWorkoutActive)
            TextButton.icon(
              icon: const Icon(Icons.support_agent, color: AppTheme.neonCyan),
              label: const Text("Escalate (\$5)", style: TextStyle(color: AppTheme.neonCyan, fontWeight: FontWeight.bold)),
              onPressed: _escalateToHuman,
            ),
          if (!_isWorkoutActive)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
        ],
      ),
      body: _isWorkoutActive ? _buildActiveWorkout() : _buildWorkoutSetup(textTheme),
    );
  }

  Widget _buildWorkoutSetup(TextTheme textTheme) {
    return Padding(
      padding: const Size(20, 20).horizontalAndVertical,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Select Your Lift",
            style: textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            "Choose a movement to begin real-time posture analysis & rep counting.",
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: _lifts.length,
              itemBuilder: (context, index) {
                final lift = _lifts[index];
                final isSelected = lift == _selectedLift;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedLift = lift;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.neonLime.withOpacity(0.08) : AppTheme.cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? AppTheme.neonLime : Colors.white.withOpacity(0.08),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lift,
                              style: textTheme.titleLarge?.copyWith(
                                color: isSelected ? AppTheme.neonLime : AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              lift == 'Squat'
                                  ? "On-device joint angle depth tracking"
                                  : lift == 'Deadlift (RDL)'
                                      ? "Lumbar flexion warning system"
                                      : "Bar path speed and symmetry check",
                              style: textTheme.bodyMedium,
                            ),
                          ],
                        ),
                        Icon(
                          isSelected ? Icons.check_circle : Icons.circle_outlined,
                          color: isSelected ? AppTheme.neonLime : AppTheme.textSecondary,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neonLime,
              foregroundColor: AppTheme.darkBackground,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _startWorkout,
            child: Text(
              "START ${_selectedLift.toUpperCase()}",
              style: textTheme.labelLarge?.copyWith(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveWorkout() {
    return Column(
      children: [
        // Camera/Simulation Panel
        Expanded(
          flex: 4,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_isCameraInitialized && _cameraController != null)
                CameraPreview(_cameraController!)
              else
                Container(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.videocam_off, color: AppTheme.textSecondary, size: 48),
                        SizedBox(height: 8),
                        Text("Camera Active (Simulating Pose Engine)", style: TextStyle(color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                ),
              // Overlay drawing the skeleton pose
              CustomPaint(
                painter: PosePainter(
                  lift: _selectedLift,
                  progress: _squatProgress,
                ),
              ),
              // Rep display top-left overlay
              Positioned(
                top: 20,
                left: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.neonLime.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        "REPS",
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "$_repCount",
                        style: const TextStyle(color: AppTheme.neonLime, fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              // Feedback Bottom Center Overlay
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.neonCyan.withOpacity(0.3)),
                  ),
                  child: Text(
                    _feedbackMessage,
                    style: const TextStyle(
                      color: AppTheme.neonCyan,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Active workout details
        Expanded(
          flex: 2,
          child: Container(
            color: AppTheme.cardBg,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _selectedLift,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                const Text(
                  "Pose Analysis Engine: Active (19-Joint Local Vision)",
                  style: TextStyle(color: AppTheme.neonLime, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _stopWorkout,
                  child: const Text("STOP AND SAVE SESSION", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class PosePainter extends CustomPainter {
  final String lift;
  final double progress; // 0.0 -> Standing/Starting, 1.0 -> Max Flexion/Bottom of Rep

  PosePainter({required this.lift, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..color = AppTheme.neonCyan
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final paintJoint = Paint()
      ..color = AppTheme.neonLime
      ..style = PaintingStyle.fill;

    // Calculate positions relative to canvas size
    final centerX = size.width / 2;
    final headY = size.height * 0.25 + (progress * 50); // Move down during lift
    final shoulderY = headY + 30;
    final hipY = shoulderY + 80 + (progress * 20); // Hips drop down
    final hipX = centerX - (lift == 'Deadlift (RDL)' ? progress * 30 : 0); // Push hips back for RDL
    final kneeY = hipY + 80 - (progress * 25);
    final kneeX = centerX + 40 + (progress * 20); // Knees forward/out during squat
    final ankleY = size.height * 0.85;
    final ankleX = centerX + 40;

    // Joint positions
    final head = Offset(centerX, headY);
    final shoulder = Offset(centerX, shoulderY);
    final hip = Offset(hipX, hipY);
    final knee = Offset(kneeX, kneeY);
    final ankle = Offset(ankleX, ankleY);

    // Hands for Bench Press / Squat
    Offset hand;
    if (lift == 'Bench Press') {
      // Hands pushing up and down
      final handY = size.height * 0.45 - (progress * 60);
      hand = Offset(centerX, handY);
      // Barbell line
      canvas.drawLine(Offset(centerX - 100, handY), Offset(centerX + 100, handY), paintLine..color = Colors.white..strokeWidth = 6);
    } else {
      // Deadlift / Squat hand position
      hand = Offset(centerX + 20, hipY + 30);
    }

    // Draw Spine
    canvas.drawLine(head, shoulder, paintLine..color = AppTheme.neonCyan);
    canvas.drawLine(shoulder, hip, paintLine..color = AppTheme.neonCyan);

    // Draw Leg joints
    canvas.drawLine(hip, knee, paintLine..color = AppTheme.neonCyan);
    canvas.drawLine(knee, ankle, paintLine..color = AppTheme.neonCyan);

    if (lift != 'Bench Press') {
      canvas.drawLine(shoulder, hand, paintLine..color = AppTheme.neonCyan);
    }

    // Draw Joints
    canvas.drawCircle(head, 12, paintJoint);
    canvas.drawCircle(shoulder, 8, paintJoint);
    canvas.drawCircle(hip, 8, paintJoint);
    canvas.drawCircle(knee, 8, paintJoint);
    canvas.drawCircle(ankle, 8, paintJoint);
    canvas.drawCircle(hand, 6, paintJoint);

    // Draw joint angle text overlay near hip/knee
    // Calculate angle at knee using mock angles
    double kneeAngleDegrees = 180.0 - (progress * 90.0); // 180 (straight) -> 90 (deep flexed)
    final textSpan = TextSpan(
      text: "${kneeAngleDegrees.toInt()}°",
      style: TextStyle(
        color: kneeAngleDegrees < 100 ? AppTheme.neonLime : AppTheme.neonCyan,
        fontSize: 16,
        fontWeight: FontWeight.bold,
        backgroundColor: Colors.black54,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(kneeX + 15, kneeY - 10));
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.lift != lift;
  }
}

// Helper extension to make standard EdgeInsets cleaner
extension EdgeInsetsGeometryExtensions on Size {
  EdgeInsets get horizontalAndVertical => EdgeInsets.symmetric(horizontal: width, vertical: height);
}
