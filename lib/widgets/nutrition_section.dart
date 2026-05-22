import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/form_check.dart';
import '../models/user_profile.dart';
import '../services/ai_coach_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';

/// Intake-first nutrition section. Lives inside the Program screen now;
/// no auto-generation, no "today's meals" until the user fills the intake
/// and explicitly asks for suggestions.
class NutritionSection extends StatefulWidget {
  const NutritionSection({super.key});

  @override
  State<NutritionSection> createState() => _NutritionSectionState();
}

enum _NutritionPhase { intake, generating, results }

class _NutritionSectionState extends State<NutritionSection> {
  static const _kIntakeDone = 'nutrition_intake_done_v1';

  _NutritionPhase _phase = _NutritionPhase.intake;
  NutritionPlan? _plan;
  String? _error;

  // Intake state — initialize from saved profile but let user override here.
  late String _budget;
  late String _diet;
  late TextEditingController _allergies;
  String _mealTiming = 'No preference';
  String _appetite = 'Normal';

  static const _budgets = ['Tight', 'Moderate', 'Flexible'];
  static const _diets = [
    'No restrictions',
    'Vegetarian',
    'Vegan',
    'Pescatarian',
    'Halal',
    'Kosher',
    'Gluten-free',
    'Lactose-free'
  ];
  static const _timings = [
    'No preference',
    'Eat after training',
    'Eat before training',
    'Intermittent fasting',
    '3 meals + snack'
  ];
  static const _appetites = ['Small', 'Normal', 'Big'];

  @override
  void initState() {
    super.initState();
    final p = ProfileService.current;
    _budget = _budgets.contains(p.budgetPerDay) ? p.budgetPerDay : 'Moderate';
    _diet = _diets.contains(p.dietaryPreference)
        ? p.dietaryPreference
        : 'No restrictions';
    _allergies = TextEditingController();
    _loadCachedIntake();
  }

  Future<void> _loadCachedIntake() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kIntakeDone);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _budget = j['budget'] as String? ?? _budget;
        _diet = j['diet'] as String? ?? _diet;
        _allergies.text = j['allergies'] as String? ?? '';
        _mealTiming = j['mealTiming'] as String? ?? _mealTiming;
        _appetite = j['appetite'] as String? ?? _appetite;
      });
    } catch (_) {}
  }

  Future<void> _saveIntake() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kIntakeDone,
        jsonEncode({
          'budget': _budget,
          'diet': _diet,
          'allergies': _allergies.text.trim(),
          'mealTiming': _mealTiming,
          'appetite': _appetite,
        }));
  }

  @override
  void dispose() {
    _allergies.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _phase = _NutritionPhase.generating;
      _error = null;
    });
    await _saveIntake();

    // Persist user-controllable parts back to the profile so other surfaces
    // (program prompt, AI coach RAG context) stay in sync.
    final p = ProfileService.current;
    final updated = p.copyWith(
      budgetPerDay: _budget,
      dietaryPreference: _diet,
    );
    await ProfileService.save(updated);

    final profileForPrompt = updated.copyWith();
    final allergiesNote = _allergies.text.trim();
    try {
      // Tag user notes onto the profile-driven prompt via a wrapper.
      final plan = await _generateWithExtras(
        profile: profileForPrompt,
        mealTiming: _mealTiming,
        appetite: _appetite,
        allergiesFreeform: allergiesNote,
      );
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _phase = _NutritionPhase.results;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _NutritionPhase.intake;
        _error = "Couldn't generate meals: $e";
      });
    }
  }

  Future<NutritionPlan> _generateWithExtras({
    required UserProfile profile,
    required String mealTiming,
    required String appetite,
    required String allergiesFreeform,
  }) async {
    // Bake the extras into a transient profile so the service prompt picks
    // them up. The cleanest path: piggy-back on dietaryPreference.
    final extras = <String>[];
    if (allergiesFreeform.isNotEmpty) {
      extras.add('avoid: $allergiesFreeform');
    }
    extras.add('appetite: $appetite');
    extras.add('timing: $mealTiming');
    final merged =
        '${profile.dietaryPreference} (${extras.join('; ')})';
    final p = profile.copyWith(dietaryPreference: merged);
    return AICoachService.generateDailyPlan(p);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.neonLime.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.restaurant_menu_rounded,
                    color: AppTheme.neonLime, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nutrition',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 2),
                    const Text(
                      'Daily targets + cheap meal ideas, built around your habits.',
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12.5,
                          height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _TargetsRow(),
          const SizedBox(height: 16),
          switch (_phase) {
            _NutritionPhase.intake => _buildIntake(),
            _NutritionPhase.generating => _buildLoading(),
            _NutritionPhase.results => _buildResults(),
          },
        ],
      ),
    );
  }

  Widget _buildIntake() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppTheme.accentRed.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppTheme.accentRed.withValues(alpha: 0.4)),
            ),
            child: Text(_error!,
                style: const TextStyle(
                    color: AppTheme.accentRed, fontSize: 12)),
          ),
        ],
        const Text(
          'Tell me a bit before I recommend meals',
          style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        _PickerField(
          label: 'Daily budget',
          value: _budget,
          options: _budgets,
          onChanged: (v) => setState(() => _budget = v),
        ),
        const SizedBox(height: 8),
        _PickerField(
          label: 'Diet',
          value: _diet,
          options: _diets,
          onChanged: (v) => setState(() => _diet = v),
        ),
        const SizedBox(height: 8),
        _PickerField(
          label: 'Meal timing',
          value: _mealTiming,
          options: _timings,
          onChanged: (v) => setState(() => _mealTiming = v),
        ),
        const SizedBox(height: 8),
        _PickerField(
          label: 'Appetite',
          value: _appetite,
          options: _appetites,
          onChanged: (v) => setState(() => _appetite = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _allergies,
          decoration: const InputDecoration(
            labelText: 'Allergies / foods to avoid',
            hintText: 'e.g., peanuts, shellfish, dairy',
            isDense: true,
          ),
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('Suggest meals for today'),
          ),
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return Container(
      height: 120,
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppTheme.neonLime),
          SizedBox(height: 12),
          Text('Generating meal ideas…',
              style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final plan = _plan!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text("Today's suggestions",
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            TextButton.icon(
              onPressed: () =>
                  setState(() => _phase = _NutritionPhase.intake),
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('Adjust'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...plan.meals.map((m) => _MealCard(meal: m)),
        if (plan.shoppingNote.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.neonCyan.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppTheme.neonCyan.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.shopping_basket_outlined,
                    color: AppTheme.neonCyan, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(plan.shoppingNote,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          height: 1.45)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _generate,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Regenerate'),
        ),
      ],
    );
  }
}

class _TargetsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = ProfileService.current;
    final cals = p.estimatedDailyCalories();
    final protein = p.proteinTargetGrams();
    if (cals == null || protein == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.cardBgElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.hairline),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline_rounded,
                color: AppTheme.textSecondary, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Add age, height, and bodyweight in onboarding to see daily targets.',
                style:
                    TextStyle(color: AppTheme.textSecondary, fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: _TargetTile(
            label: 'Calories',
            value: '$cals',
            unit: 'kcal/day',
            color: AppTheme.neonCyan,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _TargetTile(
            label: 'Protein',
            value: '$protein',
            unit: 'g/day',
            color: AppTheme.neonLime,
          ),
        ),
      ],
    );
  }
}

class _TargetTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  const _TargetTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBgElevated,
        borderRadius: BorderRadius.circular(12),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(unit,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  const _PickerField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: AppTheme.cardBgElevated,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(label,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                ...options.map((o) {
                  final sel = o == value;
                  return ListTile(
                    title: Text(o,
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight:
                                sel ? FontWeight.w700 : FontWeight.w500)),
                    trailing: sel
                        ? const Icon(Icons.check_circle,
                            color: AppTheme.neonLime)
                        : null,
                    onTap: () => Navigator.pop(context, o),
                  );
                }),
              ],
            ),
          ),
        );
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.cardBgElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.hairline),
        ),
        child: Row(
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
            const Spacer(),
            Text(value,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            const Icon(Icons.unfold_more_rounded,
                color: AppTheme.textTertiary, size: 18),
          ],
        ),
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  final MealSuggestion meal;
  const _MealCard({required this.meal});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBgElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.neonLime.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(meal.slot,
                    style: const TextStyle(
                        color: AppTheme.neonLime,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              Text(meal.cost,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Text(meal.name,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(meal.description,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 8),
          Row(
            children: [
              _MiniStat(text: '${meal.calories} kcal', color: AppTheme.neonCyan),
              const SizedBox(width: 8),
              _MiniStat(
                  text: '${meal.proteinGrams}g protein',
                  color: AppTheme.neonLime),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String text;
  final Color color;
  const _MiniStat({required this.text, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

