import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme.dart';
import '../../services/ai_coach_service.dart';
import '../../widgets/trainer_network_card.dart';
import '../trainers/trainer_network_screen.dart';

class WayfindingScreen extends StatefulWidget {
  const WayfindingScreen({super.key});

  @override
  State<WayfindingScreen> createState() => _WayfindingScreenState();
}

class _WayfindingScreenState extends State<WayfindingScreen> {
  CameraController? _camera;
  bool _cameraReady = false;
  bool _isScanning = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _errorMessage = 'No camera found');
        return;
      }
      _camera = CameraController(cameras[0], ResolutionPreset.medium, enableAudio: false);
      await _camera!.initialize();
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Camera unavailable: $e');
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_isScanning || _camera == null || !_cameraReady) return;
    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });

    try {
      final file = await _camera!.takePicture();
      final bytes = await file.readAsBytes();
      final info = await AICoachService.identifyMachine(bytes);
      if (!mounted) return;
      setState(() => _isScanning = false);
      _showMachineSheet(info);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _errorMessage = 'Could not identify machine. Try again.';
        });
      }
    }
  }

  void _showMachineSheet(MachineInfo info) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => MachineChatSheet(machine: info),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Scan Machine'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_cameraReady && _camera != null)
            CameraPreview(_camera!)
          else
            Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.videocam_off, color: AppTheme.textSecondary, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage ?? 'Initializing camera...',
                      style: const TextStyle(color: AppTheme.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          CustomPaint(painter: ScannerOverlayPainter(isScanning: _isScanning)),
          // Top hint
          Positioned(
            top: 16,
            left: 20,
            right: 20,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppTheme.neonLime.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.center_focus_strong_rounded,
                      color: AppTheme.neonLime, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Point at any gym machine. We\'ll tell you what it is and how to use it.',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom area: status + giant capture button
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Column(
              children: [
                if (_isScanning)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.neonCyan),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Analyzing…',
                          style: TextStyle(
                              color: AppTheme.neonCyan,
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                if (_errorMessage != null && !_isScanning)
                  Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 24)
                            .copyWith(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.accentRed.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                _CaptureButton(
                  busy: _isScanning,
                  onTap: _isScanning ? null : _scan,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tap to scan',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Large prominent capture button styled like a camera shutter.
class _CaptureButton extends StatelessWidget {
  final bool busy;
  final VoidCallback? onTap;
  const _CaptureButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.3),
          border: Border.all(
            color: busy
                ? AppTheme.neonCyan
                : AppTheme.neonLime.withValues(alpha: 0.9),
            width: 4,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.neonLime.withValues(alpha: 0.35),
              blurRadius: 20,
              spreadRadius: -2,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: busy ? AppTheme.cardBg : AppTheme.neonLime,
            ),
            child: busy
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppTheme.neonCyan),
                    ),
                  )
                : const Icon(Icons.camera_alt_rounded,
                    color: AppTheme.darkBackground, size: 28),
          ),
        ),
      ),
    );
  }
}

// ─── Machine Chat Sheet ───────────────────────────────────────────────────────

typedef _ChatMsg = ({String role, String text});

class MachineChatSheet extends StatefulWidget {
  final MachineInfo machine;
  const MachineChatSheet({super.key, required this.machine});

  @override
  State<MachineChatSheet> createState() => _MachineChatSheetState();
}

class _MachineChatSheetState extends State<MachineChatSheet> {
  final _tts = FlutterTts();
  final _stt = SpeechToText();
  final _textController = TextEditingController();

  ScrollController? _scrollController;

  final List<AIMessage> _history = [];
  final List<_ChatMsg> _display = [];

  bool _sttAvailable = false;
  bool _isListening = false;
  bool _isThinking = false;
  String _interim = '';

  @override
  void initState() {
    super.initState();
    _initTts();
    _initStt();
    _addWelcomeAndSpeak();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
  }

  Future<void> _initStt() async {
    _sttAvailable = await _stt.initialize(onError: (_) {
      if (mounted) setState(() => _isListening = false);
    });
    if (mounted) setState(() {});
  }

  void _addWelcomeAndSpeak() {
    final m = widget.machine;
    final firstStep = m.steps.isNotEmpty ? ' ${m.steps.first}' : '';
    final welcome = "I've identified a ${m.name}, which targets your ${m.muscles}.$firstStep Ask me anything!";

    setState(() {
      _display.add((role: 'assistant', text: welcome));
      _history.add(AIMessage(role: 'assistant', content: welcome));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _tts.speak(welcome));
  }

  @override
  void dispose() {
    _tts.stop();
    _stt.stop();
    _textController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sc = _scrollController;
      if (sc != null && sc.hasClients) {
        sc.animateTo(
          sc.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isThinking) return;
    _textController.clear();

    setState(() {
      _history.add(AIMessage(role: 'user', content: trimmed));
      _display.add((role: 'user', text: trimmed));
      _isThinking = true;
      _interim = '';
    });
    _scrollToBottom();

    try {
      final m = widget.machine;
      final system = 'You are LiftMate AI, a friendly gym coach helping a complete beginner use a ${m.name} '
          '(targets: ${m.muscles}; suggested starting weight: ${m.startingWeight}). '
          'Keep answers to 2-3 sentences — they will be spoken aloud. Be encouraging and specific.';

      final reply = await AICoachService.chat(_history, system);

      setState(() {
        _history.add(AIMessage(role: 'assistant', content: reply));
        _display.add((role: 'assistant', text: reply));
        _isThinking = false;
      });
      _scrollToBottom();
      await _tts.speak(reply);
    } catch (e) {
      setState(() {
        _isThinking = false;
        _display.add((role: 'assistant', text: 'Sorry, I had trouble connecting. Please try again.'));
      });
    }
  }

  Future<void> _toggleListen() async {
    if (_isListening) {
      await _stt.stop();
      setState(() => _isListening = false);
      return;
    }
    await _tts.stop();
    setState(() {
      _isListening = true;
      _interim = '';
    });

    await _stt.listen(
      onResult: (result) {
        setState(() => _interim = result.recognizedWords);
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          setState(() => _isListening = false);
          _send(result.recognizedWords);
        }
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) {
        _scrollController = scrollController;
        return Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            // Scrollable content
            Expanded(
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverToBoxAdapter(child: _buildMachineHeader()),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    sliver: SliverList.builder(
                      itemCount: _display.length +
                          (_interim.isNotEmpty ? 1 : 0) +
                          (_isThinking ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i < _display.length) {
                          final msg = _display[i];
                          return _buildBubble(msg.role, msg.text);
                        }
                        if (_interim.isNotEmpty && i == _display.length) {
                          return _buildBubble('user', _interim, isInterim: true);
                        }
                        return _buildThinkingIndicator();
                      },
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                ],
              ),
            ),
            _buildInputBar(context),
          ],
        );
      },
    );
  }

  Widget _buildMachineHeader() {
    final m = widget.machine;
    final query =
        m.demoQuery.isNotEmpty ? m.demoQuery : '${m.name} proper form beginner';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.neonCyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'MACHINE IDENTIFIED',
              style: TextStyle(
                  color: AppTheme.neonCyan,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5),
            ),
          ),
          const SizedBox(height: 10),
          Text(m.name,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(m.muscles,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.fitness_center,
                  color: AppTheme.neonLime, size: 14),
              const SizedBox(width: 4),
              Text('Start: ${m.startingWeight}',
                  style: const TextStyle(
                      color: AppTheme.neonLime,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 16),
          _DemoButtons(query: query),
          const SizedBox(height: 18),
          const Text(
            'Setup',
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          ...m.steps
              .asMap()
              .entries
              .map((e) => _buildStep('${e.key + 1}', e.value)),
          if (m.commonMistakes.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Watch out for',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            ...m.commonMistakes.map((mistake) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(Icons.warning_amber_rounded,
                            color: AppTheme.accentAmber, size: 14),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          mistake,
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 13,
                              height: 1.45),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          const SizedBox(height: 16),
          TrainerNetworkCard(
            compact: true,
            title: 'Want a trainer to walk you through?',
            description:
                'A vetted coach can write a 2-minute setup brief for ${m.name} — under 24 hours.',
            ctaLabel: 'Ask a human · \$9',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const TrainerNetworkScreen()),
            ),
          ),
          const Divider(color: AppTheme.hairline, height: 32),
          const Text(
            'AI COACH',
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
              style: const TextStyle(color: AppTheme.neonCyan, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(String role, String text, {bool isInterim = false}) {
    final isUser = role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: isUser
              ? AppTheme.neonLime.withOpacity(isInterim ? 0.05 : 0.12)
              : AppTheme.neonCyan.withOpacity(0.1),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: Border.all(
            color: isUser
                ? AppTheme.neonLime.withOpacity(isInterim ? 0.15 : 0.25)
                : AppTheme.neonCyan.withOpacity(0.2),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isInterim ? AppTheme.textSecondary : AppTheme.textPrimary,
            fontSize: 14,
            height: 1.4,
            fontStyle: isInterim ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildThinkingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.neonCyan),
          ),
          const SizedBox(width: 8),
          const Text(
            'LiftMate is thinking...',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.cardBg,
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          if (_sttAvailable)
            GestureDetector(
              onTap: _toggleListen,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _isListening ? AppTheme.neonCyan.withOpacity(0.2) : Colors.white.withOpacity(0.07),
                  shape: BoxShape.circle,
                  border: Border.all(color: _isListening ? AppTheme.neonCyan : Colors.white24),
                ),
                child: Icon(
                  _isListening ? Icons.stop_rounded : Icons.mic,
                  color: _isListening ? AppTheme.neonCyan : AppTheme.textSecondary,
                  size: 20,
                ),
              ),
            ),
          if (_sttAvailable) const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _textController,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: _isListening ? 'Listening...' : 'Ask about this machine...',
                hintStyle: TextStyle(
                  color: _isListening ? AppTheme.neonCyan.withOpacity(0.5) : AppTheme.textSecondary,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: _send,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _send(_textController.text),
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppTheme.neonLime,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded, color: AppTheme.darkBackground, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Scanner Overlay ──────────────────────────────────────────────────────────

class ScannerOverlayPainter extends CustomPainter {
  final bool isScanning;
  const ScannerOverlayPainter({required this.isScanning});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isScanning ? AppTheme.neonCyan : Colors.white24
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    const padding = 50.0;
    final rect = Rect.fromLTRB(padding, padding + 100, size.width - padding, size.height - 200);
    const len = 30.0;

    // Corner brackets
    for (final (x, dx, y, dy) in [
      (rect.left, len, rect.top, len),
      (rect.right, -len, rect.top, len),
      (rect.left, len, rect.bottom, -len),
      (rect.right, -len, rect.bottom, -len),
    ]) {
      canvas.drawLine(Offset(x, y), Offset(x + dx, y), paint);
      canvas.drawLine(Offset(x, y), Offset(x, y + dy), paint);
    }

    if (isScanning) {
      canvas.drawRect(
        rect,
        Paint()
          ..color = AppTheme.neonCyan.withOpacity(0.12)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ScannerOverlayPainter old) => old.isScanning != isScanning;
}

// ─── Visual demo buttons ──────────────────────────────────────────────────────

class _DemoButtons extends StatelessWidget {
  final String query;
  const _DemoButtons({required this.query});

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String get _youtubeUrl =>
      'https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent(query)}';
  String get _imagesUrl =>
      'https://www.google.com/search?tbm=isch&q=${Uri.encodeQueryComponent(query)}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'See it in action',
          style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _DemoTile(
                icon: Icons.play_circle_fill_rounded,
                color: AppTheme.accentRed,
                title: 'Watch demo video',
                subtitle: 'Curated YouTube results',
                onTap: () => _open(_youtubeUrl),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DemoTile(
                icon: Icons.photo_library_rounded,
                color: AppTheme.neonCyan,
                title: 'Form pictures',
                subtitle: 'Reference images',
                onTap: () => _open(_imagesUrl),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DemoTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _DemoTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.cardBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(height: 10),
              Text(title,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text('Open',
                      style: TextStyle(
                          color: color,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 2),
                  Icon(Icons.arrow_forward_rounded, size: 12, color: color),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
