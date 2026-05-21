import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../theme.dart';

class WayfindingScreen extends StatefulWidget {
  const WayfindingScreen({super.key});

  @override
  State<WayfindingScreen> createState() => _WayfindingScreenState();
}

class _WayfindingScreenState extends State<WayfindingScreen> {
  List<CameraDescription> _cameras = [];
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
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
      debugPrint("Camera initialization failed: $e (Simulator)");
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  void _triggerScan() {
    setState(() {
      _isScanning = true;
    });

    // Simulate scanning delay
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
      });
      _showMachineTutorialSheet();
    });
  }

  void _showMachineTutorialSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.neonCyan.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          "MACHINE IDENTIFIED",
                          style: TextStyle(
                            color: AppTheme.neonCyan,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const Row(
                        children: [
                          Icon(Icons.star, color: AppTheme.neonLime, size: 16),
                          SizedBox(width: 4),
                          Text("Today's Plan", style: TextStyle(color: AppTheme.neonLime, fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Cable Lat Pulldown",
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Primary Muscles: Latissimus Dorsi, Rhomboids, Biceps",
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  // Tutorial Video Simulator Box
                  Container(
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: Opacity(
                            opacity: 0.4,
                            child: Image.network(
                              "https://images.unsplash.com/photo-1534438327276-14e5300c3a48?q=80&w=600&auto=format&fit=crop",
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(color: Colors.blueGrey.shade900);
                              },
                            ),
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                color: AppTheme.neonLime,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow,
                                color: AppTheme.darkBackground,
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              "Play 30s Quick Tutorial",
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "Setup & Execution",
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _buildInstructionRow("1", "Adjust thigh pad so your knees are locked at 90 degrees."),
                  _buildInstructionRow("2", "Grip bar slightly wider than shoulder width, palms facing away."),
                  _buildInstructionRow("3", "Pull bar to upper chest while leaning back slightly; keep elbows vertical."),
                  _buildInstructionRow("4", "Control weight back up slowly for a 3-second negative phase."),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.neonLime.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.neonLime.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          "Today's Target:",
                          style: TextStyle(color: AppTheme.neonLime, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "3 Sets x 10-12 Reps (RPE 8) • Rest 90s between sets.",
                          style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.neonLime,
                      foregroundColor: AppTheme.darkBackground,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Added Lat Pulldown to active workout!"),
                          backgroundColor: AppTheme.neonLime,
                        ),
                      );
                    },
                    child: const Text("ADD TO TODAY'S WORKOUT", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInstructionRow(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.neonCyan.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: AppTheme.neonCyan,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("In-Gym Wayfinding"),
      ),
      body: Stack(
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
                    Text("Point camera at a machine to scan", style: TextStyle(color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ),
          // HUD grid overlay
          CustomPaint(
            painter: ScannerOverlayPainter(isScanning: _isScanning),
          ),
          // Scan button overlay
          Positioned(
            bottom: 40,
            left: 40,
            right: 40,
            child: Column(
              children: [
                if (_isScanning)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.neonCyan,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          "Analyzing equipment geometry...",
                          style: TextStyle(color: AppTheme.neonCyan, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isScanning ? AppTheme.cardBg : AppTheme.neonLime,
                    foregroundColor: _isScanning ? AppTheme.textSecondary : AppTheme.darkBackground,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 4,
                  ),
                  icon: const Icon(Icons.camera_alt),
                  label: Text(
                    _isScanning ? "IDENTIFYING..." : "SCAN MACHINE",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5),
                  ),
                  onPressed: _isScanning ? null : _triggerScan,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ScannerOverlayPainter extends CustomPainter {
  final bool isScanning;

  ScannerOverlayPainter({required this.isScanning});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isScanning ? AppTheme.neonCyan : Colors.white24
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final width = size.width;
    final height = size.height;
    final padding = 50.0;

    // Draw scanner framing corners
    final rect = Rect.fromLTRB(padding, padding + 100, width - padding, height - 200);
    
    // Corner length
    const len = 30.0;

    // Top Left Corner
    canvas.drawLine(Offset(rect.left, rect.top), Offset(rect.left + len, rect.top), paint);
    canvas.drawLine(Offset(rect.left, rect.top), Offset(rect.left, rect.top + len), paint);

    // Top Right Corner
    canvas.drawLine(Offset(rect.right, rect.top), Offset(rect.right - len, rect.top), paint);
    canvas.drawLine(Offset(rect.right, rect.top), Offset(rect.right, rect.top + len), paint);

    // Bottom Left Corner
    canvas.drawLine(Offset(rect.left, rect.bottom), Offset(rect.left + len, rect.bottom), paint);
    canvas.drawLine(Offset(rect.left, rect.bottom), Offset(rect.left, rect.bottom - len), paint);

    // Bottom Right Corner
    canvas.drawLine(Offset(rect.right, rect.bottom), Offset(rect.right - len, rect.bottom), paint);
    canvas.drawLine(Offset(rect.right, rect.bottom), Offset(rect.right, rect.bottom - len), paint);

    if (isScanning) {
      // Draw scan animated sweep line or dots
      final paintSweep = Paint()
        ..color = AppTheme.neonCyan.withOpacity(0.15)
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, paintSweep);
    }
  }

  @override
  bool shouldRepaint(covariant ScannerOverlayPainter oldDelegate) {
    return oldDelegate.isScanning != isScanning;
  }
}
