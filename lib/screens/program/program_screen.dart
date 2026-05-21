import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/profile_service.dart';
import '../../theme.dart';
import '../../config.dart';

class ProgramScreen extends StatefulWidget {
  const ProgramScreen({super.key});

  @override
  State<ProgramScreen> createState() => _ProgramScreenState();
}

class _ProgramScreenState extends State<ProgramScreen> {
  String _selectedGoal = 'Muscle Building';
  String _selectedLevel = 'Intermediate';
  int _daysPerWeek = 4;
  final List<String> _selectedEquipment = [];
  final TextEditingController _equipSearchController = TextEditingController();

  bool _isGenerating = false;
  bool _isScanningEquipment = false;
  Map<String, dynamic>? _parsedProgram;
  String? _errorMessage;

  static final List<Map<String, dynamic>> _goals = [
    {'label': 'Muscle Building', 'icon': Icons.fitness_center},
    {'label': 'Strength', 'icon': Icons.bolt},
    {'label': 'Fat Loss', 'icon': Icons.local_fire_department},
    {'label': 'Athletic Training', 'icon': Icons.sports},
    {'label': 'General Fitness', 'icon': Icons.directions_run},
    {'label': 'Endurance', 'icon': Icons.loop},
  ];

  static const List<String> _levels = ['Beginner', 'Intermediate', 'Advanced'];

  static const List<String> _equipmentPresets = [
    'Barbell', 'Dumbbells', 'Pull-up Bar', 'Bench', 'Cable Machine',
    'Squat Rack', 'Resistance Bands', 'Kettlebell', 'Treadmill',
    'Rowing Machine', 'Jump Rope', 'Medicine Ball', 'EZ Bar',
    'TRX / Suspension', 'Plyo Box', 'Battle Ropes', 'Foam Roller',
  ];

  @override
  void initState() {
    super.initState();
    final p = ProfileService.current;
    if (p.onboardingComplete) {
      _selectedGoal = _goals.any((g) => g['label'] == p.goal)
          ? p.goal
          : _selectedGoal;
      _selectedLevel = _normalizeExperience(p.experience);
      _daysPerWeek = p.daysPerWeek.clamp(1, 7);
      for (final e in p.equipment) {
        if (!_selectedEquipment.contains(e)) _selectedEquipment.add(e);
      }
    }
  }

  String _normalizeExperience(String e) {
    if (e.startsWith('Brand new') || e.startsWith('Beginner')) return 'Beginner';
    if (e.startsWith('Intermediate')) return 'Intermediate';
    if (e.startsWith('Advanced')) return 'Advanced';
    return _selectedLevel;
  }

  @override
  void dispose() {
    _equipSearchController.dispose();
    super.dispose();
  }

  List<String> get _filteredPresets {
    final q = _equipSearchController.text.trim().toLowerCase();
    if (q.isEmpty) return _equipmentPresets;
    return _equipmentPresets.where((p) => p.toLowerCase().contains(q)).toList();
  }

  void _addCustomEquipment() {
    final text = _equipSearchController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      if (!_selectedEquipment.contains(text)) _selectedEquipment.add(text);
      _equipSearchController.clear();
    });
  }

  Future<void> _showImageSourceSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Scan Your Equipment', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                const Text(
                  'AI will identify gym equipment from your photo',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.neonLime.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt_rounded, color: AppTheme.neonLime, size: 20),
            ),
            title: const Text('Take a Photo', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
            subtitle: const Text('Use camera', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            onTap: () {
              Navigator.pop(ctx);
              _scanEquipment(ImageSource.camera);
            },
          ),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.neonCyan.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.photo_library_rounded, color: AppTheme.neonCyan, size: 20),
            ),
            title: const Text('Choose from Gallery', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
            subtitle: const Text('Select existing photo', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            onTap: () {
              Navigator.pop(ctx);
              _scanEquipment(ImageSource.gallery);
            },
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Future<void> _scanEquipment(ImageSource source) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1024,
    );
    if (image == null) return;

    setState(() => _isScanningEquipment = true);

    try {
      final bytes = await image.readAsBytes();
      final b64 = base64Encode(bytes);
      final ext = image.path.split('.').last.toLowerCase();
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';

      final response = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'x-api-key': claudeApiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'model': claudeModel,
          'max_tokens': 300,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image',
                  'source': {'type': 'base64', 'media_type': mime, 'data': b64},
                },
                {
                  'type': 'text',
                  'text':
                      'List the gym/fitness equipment visible in this image. '
                      'Return ONLY a JSON array of short names like ["Barbell","Bench","Cable Machine"]. '
                      'No other text.',
                },
              ],
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final text = (data['content'] as List).first['text'] as String;
        final match = RegExp(r'\[.*?\]', dotAll: true).firstMatch(text);
        if (match != null) {
          final found = (jsonDecode(match.group(0)!) as List).cast<String>();
          setState(() {
            for (final item in found) {
              if (!_selectedEquipment.contains(item)) _selectedEquipment.add(item);
            }
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                'Detected ${found.length} equipment item${found.length == 1 ? '' : 's'}',
              ),
              backgroundColor: AppTheme.cardBg,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('Equipment scan error: $e');
    } finally {
      if (mounted) setState(() => _isScanningEquipment = false);
    }
  }

  Future<void> _generateProgram() async {
    setState(() {
      _isGenerating = true;
      _parsedProgram = null;
      _errorMessage = null;
    });

    final equipmentStr = _selectedEquipment.isEmpty
        ? 'no equipment (bodyweight only)'
        : _selectedEquipment.join(', ');

    final injuries = ProfileService.current.injuries;
    final injuryLine = injuries.isEmpty
        ? ''
        : 'Work around these injuries (no loaded patterns that aggravate them; substitute safer variants): ${injuries.join(", ")}.\n';

    final prompt =
        'You are an expert strength and conditioning coach. '
        'Create a complete $_daysPerWeek-day/week training program.\n'
        'Goal: $_selectedGoal | Level: $_selectedLevel | Equipment: $equipmentStr\n'
        '$injuryLine'
        'Respond with ONLY valid JSON, no markdown code fences, no extra text:\n'
        '{"programTitle":"...","overview":"1-2 sentences","days":['
        '{"dayNumber":1,"focus":"Upper Body Push","isRestDay":false,"exercises":['
        '{"name":"Bench Press","sets":4,"reps":"6-8","formCue":"Retract shoulder blades"}]}],'
        '"coachingNotes":["note1","note2","note3"]}\n\n'
        'Include all $_daysPerWeek training days. Fill the remaining days of a 7-day week as rest days '
        '(isRestDay:true, exercises:[]). Include 4-6 exercises per training day.';

    try {
      final response = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'x-api-key': claudeApiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'model': claudeModel,
          'max_tokens': 3000,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final text = (data['content'] as List).first['text'] as String;
        final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
        if (jsonMatch != null) {
          try {
            final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
            setState(() {
              _parsedProgram = parsed;
              _isGenerating = false;
            });
            _saveProgramToFirebase(parsed);
          } catch (_) {
            setState(() {
              _parsedProgram = {'_raw': text};
              _isGenerating = false;
            });
          }
        } else {
          setState(() {
            _parsedProgram = {'_raw': text};
            _isGenerating = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'API error ${response.statusCode}. Check your key.';
          _isGenerating = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection failed: $e';
        _isGenerating = false;
      });
    }
  }

  Future<void> _saveProgramToFirebase(Map<String, dynamic> parsed) async {
    try {
      await FirebaseFirestore.instance.collection('programs').add({
        'goal': _selectedGoal,
        'level': _selectedLevel,
        'daysPerWeek': _daysPerWeek,
        'equipment': _selectedEquipment,
        'programTitle': parsed['programTitle'],
        'program': jsonEncode(parsed),
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Firebase program save failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('AI Program Builder'),
        actions: _parsedProgram != null
            ? [
                TextButton.icon(
                  icon: const Icon(Icons.refresh, color: AppTheme.neonLime),
                  label: const Text('Rebuild', style: TextStyle(color: AppTheme.neonLime)),
                  onPressed: () => setState(() {
                    _parsedProgram = null;
                    _errorMessage = null;
                  }),
                ),
              ]
            : null,
      ),
      body: _parsedProgram != null ? _buildResult() : _buildSetup(),
    );
  }

  // ─── SETUP SCREEN ─────────────────────────────────────────────────────────

  Widget _buildSetup() {
    final tt = Theme.of(context).textTheme;
    final itemWidth = (MediaQuery.of(context).size.width - 50) / 2;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.neonLime.withOpacity(0.08),
                  AppTheme.neonCyan.withOpacity(0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.neonLime.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.auto_awesome, color: AppTheme.neonLime, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'POWERED BY CLAUDE AI',
                    style: TextStyle(
                      color: AppTheme.neonLime,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Text('Build Your Training Block', style: tt.headlineMedium),
                const SizedBox(height: 6),
                const Text(
                  'Answer 4 questions. Get a complete periodized program — not a generic template.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Goal ──────────────────────────────────────────────────────────
          Text('Primary goal?', style: tt.titleLarge),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _goals.map((goal) {
              final isSelected = goal['label'] == _selectedGoal;
              return GestureDetector(
                onTap: () => setState(() => _selectedGoal = goal['label'] as String),
                child: SizedBox(
                  width: itemWidth,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.neonLime.withOpacity(0.1)
                          : AppTheme.cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.neonLime
                            : Colors.white.withOpacity(0.08),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(children: [
                      Icon(
                        goal['icon'] as IconData,
                        color: isSelected ? AppTheme.neonLime : AppTheme.textSecondary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          goal['label'] as String,
                          style: TextStyle(
                            color: isSelected ? AppTheme.neonLime : AppTheme.textPrimary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),

          // ── Level ─────────────────────────────────────────────────────────
          Text('Experience level?', style: tt.titleLarge),
          const SizedBox(height: 14),
          Row(
            children: _levels.map((level) {
              final isSelected = level == _selectedLevel;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedLevel = level),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: EdgeInsets.only(right: level == _levels.last ? 0 : 10),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.neonCyan.withOpacity(0.1)
                          : AppTheme.cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.neonCyan
                            : Colors.white.withOpacity(0.08),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      level,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isSelected ? AppTheme.neonCyan : AppTheme.textPrimary,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),

          // ── Days per week ──────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Days per week:', style: tt.titleLarge),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.remove_rounded, color: AppTheme.textSecondary),
                    onPressed: _daysPerWeek > 2
                        ? () => setState(() => _daysPerWeek--)
                        : null,
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '$_daysPerWeek',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.neonLime,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_rounded, color: AppTheme.textSecondary),
                    onPressed: _daysPerWeek < 6
                        ? () => setState(() => _daysPerWeek++)
                        : null,
                  ),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── Equipment ─────────────────────────────────────────────────────
          _buildEquipmentSection(tt),

          const SizedBox(height: 16),

          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.accentRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.accentRed.withOpacity(0.3)),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: AppTheme.accentRed, fontSize: 13),
              ),
            ),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.neonLime,
              foregroundColor: AppTheme.darkBackground,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _isGenerating ? null : _generateProgram,
            child: _isGenerating
                ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.darkBackground,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Claude is building your program...',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ])
                : const Text(
                    'GENERATE MY PROGRAM',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildEquipmentSection(TextTheme tt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Available equipment?', style: tt.titleLarge),
            GestureDetector(
              onTap: _isScanningEquipment ? null : _showImageSourceSheet,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppTheme.neonCyan.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.neonCyan.withOpacity(0.35)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _isScanningEquipment
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppTheme.neonCyan,
                          ),
                        )
                      : const Icon(Icons.document_scanner_outlined,
                          color: AppTheme.neonCyan, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    _isScanningEquipment ? 'Scanning...' : 'Scan photo',
                    style: const TextStyle(
                      color: AppTheme.neonCyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Search / custom add
        Container(
          decoration: BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: TextField(
            controller: _equipSearchController,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search or type equipment to add...',
              hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: AppTheme.textSecondary, size: 20),
              suffixIcon: IconButton(
                icon: const Icon(Icons.add_circle_rounded, color: AppTheme.neonLime),
                onPressed: _addCustomEquipment,
              ),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            ),
            onSubmitted: (_) => _addCustomEquipment(),
          ),
        ),
        const SizedBox(height: 14),

        // Quick-add presets
        const Text(
          'Quick add:',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: _filteredPresets.map((preset) {
            final isAdded = _selectedEquipment.contains(preset);
            return GestureDetector(
              onTap: () => setState(() {
                if (isAdded) {
                  _selectedEquipment.remove(preset);
                } else {
                  _selectedEquipment.add(preset);
                }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isAdded
                      ? AppTheme.neonLime.withOpacity(0.1)
                      : AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isAdded
                        ? AppTheme.neonLime
                        : Colors.white.withOpacity(0.08),
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (isAdded) ...[
                    const Icon(Icons.check_rounded,
                        color: AppTheme.neonLime, size: 12),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    preset,
                    style: TextStyle(
                      color: isAdded ? AppTheme.neonLime : AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ]),
              ),
            );
          }).toList(),
        ),

        // Selected equipment summary
        if (_selectedEquipment.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.neonLime.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.neonLime.withOpacity(0.18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_selectedEquipment.length} item${_selectedEquipment.length == 1 ? '' : 's'} selected',
                      style: const TextStyle(
                        color: AppTheme.neonLime,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _selectedEquipment.clear()),
                      child: const Text(
                        'Clear all',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _selectedEquipment.map((item) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: AppTheme.neonLime.withOpacity(0.25)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          item,
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 12),
                        ),
                        const SizedBox(width: 5),
                        GestureDetector(
                          onTap: () =>
                              setState(() => _selectedEquipment.remove(item)),
                          child: const Icon(Icons.close_rounded,
                              size: 13, color: AppTheme.textSecondary),
                        ),
                      ]),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 8),
          const Text(
            'No equipment selected — bodyweight exercises will be used',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  // ─── RESULT SCREEN ────────────────────────────────────────────────────────

  Widget _buildResult() {
    final rawText = _parsedProgram?['_raw'] as String?;
    if (rawText != null) return _buildRawResult(rawText);

    final title = _parsedProgram!['programTitle'] as String? ?? 'Your Program';
    final overview = _parsedProgram!['overview'] as String? ?? '';
    final days = (_parsedProgram!['days'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final notes = (_parsedProgram!['coachingNotes'] as List? ?? []).cast<String>();

    final equipStr = _selectedEquipment.isEmpty
        ? 'Bodyweight'
        : (_selectedEquipment.take(2).join(', ') +
            (_selectedEquipment.length > 2
                ? ' +${_selectedEquipment.length - 2} more'
                : ''));

    return Column(
      children: [
        // Result header card
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          decoration: BoxDecoration(
            color: AppTheme.cardBg,
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.auto_awesome, color: AppTheme.neonLime, size: 13),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '$_selectedGoal  •  $_selectedLevel  •  $_daysPerWeek days/wk  •  $equipStr',
                    style: const TextStyle(
                      color: AppTheme.neonLime,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              if (overview.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  overview,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),

        // Scrollable day cards + coaching notes
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              ...days.map(_buildDayCard),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 4),
                _buildCoachingNotesCard(notes),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDayCard(Map<String, dynamic> day) {
    final isRestDay = day['isRestDay'] as bool? ?? false;
    final dayNum = day['dayNumber'] as int? ?? 0;
    final focus = day['focus'] as String? ?? (isRestDay ? 'Rest Day' : '');
    final exercises =
        (day['exercises'] as List? ?? []).cast<Map<String, dynamic>>();

    if (isRestDay) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$dayNum',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.bedtime_outlined, color: AppTheme.textSecondary, size: 15),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              focus,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const Text(
              'Recovery & Mobility',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ]),
        ]),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(children: [
        // Day header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.neonLime.withOpacity(0.13),
                AppTheme.neonCyan.withOpacity(0.06),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                color: AppTheme.neonLime,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$dayNum',
                  style: const TextStyle(
                    color: AppTheme.darkBackground,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                focus,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            Text(
              '${exercises.length} exercises',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
          ]),
        ),

        // Exercise rows
        ...exercises.asMap().entries.map((entry) {
          final i = entry.key;
          final ex = entry.value;
          final isLast = i == exercises.length - 1;
          final formCue = ex['formCue'] as String? ?? '';

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : Border(
                      bottom: BorderSide(color: Colors.white.withOpacity(0.04)),
                    ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 18,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      height: 1.8,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ex['name'] as String? ?? '',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (formCue.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          formCue,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.neonLime.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.neonLime.withOpacity(0.25)),
                  ),
                  child: Text(
                    '${ex['sets']}×${ex['reps']}',
                    style: const TextStyle(
                      color: AppTheme.neonLime,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ]),
    );
  }

  Widget _buildCoachingNotesCard(List<String> notes) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.neonCyan.withOpacity(0.07),
            AppTheme.neonLime.withOpacity(0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.neonCyan.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.lightbulb_outline_rounded, color: AppTheme.neonCyan, size: 16),
            SizedBox(width: 8),
            Text(
              'COACHING NOTES',
              style: TextStyle(
                color: AppTheme.neonCyan,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 0.8,
              ),
            ),
          ]),
          const SizedBox(height: 14),
          ...notes.asMap().entries.map((entry) => Padding(
            padding: EdgeInsets.only(bottom: entry.key < notes.length - 1 ? 12 : 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppTheme.neonCyan.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${entry.key + 1}',
                    style: const TextStyle(
                      color: AppTheme.neonCyan,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.value,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
            ]),
          )),
        ],
      ),
    );
  }

  Widget _buildRawResult(String text) {
    final equipStr = _selectedEquipment.isEmpty
        ? 'Bodyweight'
        : _selectedEquipment.take(2).join(', ');
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        color: AppTheme.cardBg,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome, color: AppTheme.neonLime, size: 14),
            const SizedBox(width: 8),
            Text(
              '$_selectedGoal  •  $_selectedLevel  •  $_daysPerWeek days/wk  •  $equipStr',
              style: const TextStyle(
                color: AppTheme.neonLime,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text('Your Training Program',
              style: Theme.of(context).textTheme.headlineMedium),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: SelectableText(
              text,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                height: 1.65,
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
