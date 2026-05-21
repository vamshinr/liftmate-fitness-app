import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
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
  String _selectedEquipment = 'Full Gym';

  bool _isGenerating = false;
  String? _generatedProgram;
  String? _errorMessage;

  final List<Map<String, dynamic>> _goals = [
    {'label': 'Muscle Building', 'icon': Icons.fitness_center},
    {'label': 'Strength', 'icon': Icons.bolt},
    {'label': 'Fat Loss', 'icon': Icons.local_fire_department},
    {'label': 'General Fitness', 'icon': Icons.directions_run},
  ];

  final List<String> _levels = ['Beginner', 'Intermediate', 'Advanced'];

  final List<Map<String, dynamic>> _equipment = [
    {'label': 'Full Gym', 'desc': 'Barbells, machines, cables'},
    {'label': 'Home Gym', 'desc': 'Dumbbells, resistance bands'},
    {'label': 'Bodyweight Only', 'desc': 'No equipment needed'},
  ];

  Future<void> _generateProgram() async {
    setState(() {
      _isGenerating = true;
      _generatedProgram = null;
      _errorMessage = null;
    });

    final prompt =
        'You are an expert strength and conditioning coach. Generate a complete, '
        'practical $_daysPerWeek-day per week training program for a $_selectedLevel '
        'lifter whose primary goal is $_selectedGoal, using $_selectedEquipment.\n\n'
        'Format:\n'
        '- Label each training day clearly (Day 1, Day 2, etc.)\n'
        '- For each exercise: name, Sets x Reps, one short form cue\n'
        '- Mark rest days\n'
        '- End with 3 key coaching notes for this specific goal\n\n'
        'Keep it concise, practical, and beginner-readable. Use clear line breaks.';

    try {
      final response = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'x-api-key': claudeApiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'model': 'claude-sonnet-4-6',
          'max_tokens': 1400,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final text = (data['content'] as List).first['text'] as String;
        setState(() {
          _generatedProgram = text;
          _isGenerating = false;
        });
        _saveProgramToFirebase(text);
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

  Future<void> _saveProgramToFirebase(String program) async {
    try {
      await FirebaseFirestore.instance.collection('programs').add({
        'goal': _selectedGoal,
        'level': _selectedLevel,
        'daysPerWeek': _daysPerWeek,
        'equipment': _selectedEquipment,
        'program': program,
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
        actions: _generatedProgram != null
            ? [
                TextButton.icon(
                  icon: const Icon(Icons.refresh, color: AppTheme.neonLime),
                  label: const Text('Rebuild', style: TextStyle(color: AppTheme.neonLime)),
                  onPressed: () => setState(() {
                    _generatedProgram = null;
                    _errorMessage = null;
                  }),
                ),
              ]
            : null,
      ),
      body: _generatedProgram != null ? _buildResult() : _buildSetup(),
    );
  }

  Widget _buildSetup() {
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header banner
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
                const Row(
                  children: [
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
                  ],
                ),
                const SizedBox(height: 10),
                Text('Build Your Training Block', style: textTheme.headlineMedium),
                const SizedBox(height: 6),
                const Text(
                  'Answer 4 questions. Get a complete periodized program — not a generic template.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Goal selection
          Text('Primary goal?', style: textTheme.titleLarge),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.4,
            children: _goals.map((goal) {
              final isSelected = goal['label'] == _selectedGoal;
              return GestureDetector(
                onTap: () => setState(() => _selectedGoal = goal['label'] as String),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.neonLime.withOpacity(0.1) : AppTheme.cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? AppTheme.neonLime : Colors.white.withOpacity(0.08),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
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
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),

          // Experience level
          Text('Experience level?', style: textTheme.titleLarge),
          const SizedBox(height: 14),
          Row(
            children: _levels.map((level) {
              final isSelected = level == _selectedLevel;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedLevel = level),
                  child: Container(
                    margin: EdgeInsets.only(
                      right: level == _levels.last ? 0 : 10,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.neonCyan.withOpacity(0.1) : AppTheme.cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppTheme.neonCyan : Colors.white.withOpacity(0.08),
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

          // Days per week stepper
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Days per week:', style: textTheme.titleLarge),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_rounded, color: AppTheme.textSecondary),
                      onPressed:
                          _daysPerWeek > 2 ? () => setState(() => _daysPerWeek--) : null,
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
                      onPressed:
                          _daysPerWeek < 6 ? () => setState(() => _daysPerWeek++) : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Equipment selection
          Text('Available equipment?', style: textTheme.titleLarge),
          const SizedBox(height: 14),
          ..._equipment.map((equip) {
            final isSelected = equip['label'] == _selectedEquipment;
            return GestureDetector(
              onTap: () => setState(() => _selectedEquipment = equip['label'] as String),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.neonLime.withOpacity(0.06) : AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppTheme.neonLime : Colors.white.withOpacity(0.06),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                      color: isSelected ? AppTheme.neonLime : AppTheme.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          equip['label'] as String,
                          style: TextStyle(
                            color: isSelected ? AppTheme.neonLime : AppTheme.textPrimary,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        Text(
                          equip['desc'] as String,
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),

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
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
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
                    ],
                  )
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

  Widget _buildResult() {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          color: AppTheme.cardBg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: AppTheme.neonLime, size: 14),
                  const SizedBox(width: 8),
                  Text(
                    '$_selectedGoal  •  $_selectedLevel  •  $_daysPerWeek days/wk  •  $_selectedEquipment',
                    style: const TextStyle(
                      color: AppTheme.neonLime,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Your Training Program', style: textTheme.headlineMedium),
              const SizedBox(height: 4),
              const Text(
                'Saved to Firebase. Start Day 1 when you\'re ready.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
            ],
          ),
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
                _generatedProgram!,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  height: 1.65,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
