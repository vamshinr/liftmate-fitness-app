import 'package:flutter/material.dart';
import '../../services/profile_service.dart';
import '../../theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = ProfileService.current;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Your profile', style: textTheme.titleLarge),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                _row('Goal', p.goal),
                _row('Experience', p.experience),
                _row('Days/week', '${p.daysPerWeek}'),
                _row('Equipment',
                    p.equipment.isEmpty ? 'Bodyweight' : p.equipment.join(', ')),
                _row('Injuries',
                    p.injuries.isEmpty ? 'None reported' : p.injuries.join(', ')),
                _row('Diet', p.dietaryPreference),
                _row('Cleared for exercise',
                    p.clearedForExercise ? 'Yes' : 'Needs clinician sign-off'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.neonLime,
              side: const BorderSide(color: AppTheme.neonLime),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: AppTheme.cardBg,
                  title: const Text('Redo onboarding?',
                      style: TextStyle(color: AppTheme.textPrimary)),
                  content: const Text(
                    'This clears your saved profile and restarts the welcome flow. Your form check history is not affected.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.neonLime,
                        foregroundColor: AppTheme.darkBackground,
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await ProfileService.clear();
                if (context.mounted) {
                  Navigator.popUntil(context, (r) => r.isFirst);
                }
              }
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Redo onboarding'),
          ),
          const SizedBox(height: 28),
          Text('About', style: textTheme.titleLarge),
          const SizedBox(height: 12),
          const Text(
            'LiftMate analyzes your form using Claude\'s vision model — not landmark-based pose detection. The model reasons about depth, bar path, brace, and spine angle holistically. When confidence is limited, a vetted human coach can review for \$9.',
            style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 120,
              child: Text(k,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                  textAlign: TextAlign.right),
            ),
          ],
        ),
      );
}
