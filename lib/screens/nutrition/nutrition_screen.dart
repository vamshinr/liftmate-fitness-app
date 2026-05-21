import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/form_check.dart';
import '../../services/claude_service.dart';
import '../../services/profile_service.dart';
import '../../theme.dart';

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  NutritionPlan? _plan;
  List<LoggedMeal> _logged = [];
  bool _loadingPlan = false;
  bool _loggingMeal = false;
  String _planError = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await ProfileService.load();
    await _loadCachedPlan();
    await _loadLoggedMeals();
    if (_plan == null || !_isToday(_plan!.generatedAt)) {
      await _generatePlan();
    }
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  String get _todayKey {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadCachedPlan() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('nutrition_plan_$_todayKey');
    if (raw != null) {
      try {
        setState(() {
          _plan = NutritionPlan.fromJson(
              jsonDecode(raw) as Map<String, dynamic>);
        });
      } catch (_) {}
    }
  }

  Future<void> _cachePlan(NutritionPlan plan) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'nutrition_plan_$_todayKey', jsonEncode(plan.toJson()));
  }

  Future<void> _loadLoggedMeals() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('logged_meals_$_todayKey') ?? [];
    setState(() {
      _logged = raw
          .map((s) =>
              LoggedMeal.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> _saveLoggedMeal(LoggedMeal meal) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('logged_meals_$_todayKey') ?? [];
    raw.add(jsonEncode(meal.toJson()));
    await prefs.setStringList('logged_meals_$_todayKey', raw);
    setState(() => _logged = [..._logged, meal]);
    try {
      await FirebaseFirestore.instance.collection('meal_logs').add({
        ...meal.toJson(),
        'date': _todayKey,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _generatePlan() async {
    setState(() {
      _loadingPlan = true;
      _planError = '';
    });
    try {
      final plan = await ClaudeService.generateDailyPlan(ProfileService.current);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _loadingPlan = false;
      });
      await _cachePlan(plan);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _planError = '$e';
        _loadingPlan = false;
      });
    }
  }

  int get _eatenCalories =>
      _logged.fold(0, (s, m) => s + m.approxCalories);
  int get _eatenProtein =>
      _logged.fold(0, (s, m) => s + m.approxProteinGrams);

  bool get _proteinGap {
    if (_plan == null) return false;
    final hour = DateTime.now().hour;
    if (hour < 17) return false;
    return _eatenProtein < (_plan!.proteinGrams * 0.7);
  }

  Future<void> _logFromCamera() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
        source: ImageSource.camera, maxWidth: 1280, imageQuality: 80);
    if (file == null) return;
    final bytes = await File(file.path).readAsBytes();
    await _doLog(photo: bytes);
  }

  Future<void> _logFromText() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.cardBg,
        title: const Text('What did you eat?',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'e.g., chicken sandwich and a banana',
            hintStyle: TextStyle(color: AppTheme.textSecondary),
          ),
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
            child: const Text('Log it'),
          ),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    await _doLog(text: ctrl.text.trim());
  }

  Future<void> _doLog({Uint8List? photo, String? text}) async {
    setState(() => _loggingMeal = true);
    try {
      final meal = await ClaudeService.logMeal(photo: photo, text: text);
      await _saveLoggedMeal(meal);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.cardBg,
          content: Text('Logged: ${meal.description}',
              style: const TextStyle(color: AppTheme.textPrimary)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not log: $e')),
      );
    } finally {
      if (mounted) setState(() => _loggingMeal = false);
    }
  }

  void _showLogSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppTheme.neonLime),
                title: const Text('Log with a photo',
                    style: TextStyle(color: AppTheme.textPrimary)),
                subtitle: const Text(
                  'AI will estimate calories and protein.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _logFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_note, color: AppTheme.neonCyan),
                title: const Text('Log with a quick note',
                    style: TextStyle(color: AppTheme.textPrimary)),
                subtitle: const Text('Type what you ate. Approximate.',
                    style: TextStyle(color: AppTheme.textSecondary)),
                onTap: () {
                  Navigator.pop(context);
                  _logFromText();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nutrition Coach'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadingPlan ? null : _generatePlan,
            tooltip: 'Regenerate today\'s plan',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.neonLime,
        foregroundColor: AppTheme.darkBackground,
        onPressed: _loggingMeal ? null : _showLogSheet,
        icon: _loggingMeal
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.darkBackground),
              )
            : const Icon(Icons.add),
        label: const Text('Log meal',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        color: AppTheme.neonLime,
        onRefresh: _generatePlan,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            _greeting(),
            const SizedBox(height: 16),
            if (_planError.isNotEmpty) _errorCard(),
            if (_plan != null) ...[
              _targetsCard(),
              const SizedBox(height: 16),
              if (_proteinGap) _proteinGapAlert(),
              if (_proteinGap) const SizedBox(height: 16),
              Text("Today's plan",
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text(
                "Three simple meals that hit your numbers — pick, swap, or improvise.",
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              ..._plan!.meals.map(_mealCard),
              if (_plan!.shoppingNote.isNotEmpty) ...[
                const SizedBox(height: 8),
                _shoppingNoteCard(),
              ],
            ] else if (_loadingPlan)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.neonLime)),
              ),
            const SizedBox(height: 24),
            if (_logged.isNotEmpty) ...[
              Text("What you've logged today",
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              ..._logged.reversed.map(_loggedCard),
            ],
          ],
        ),
      ),
    );
  }

  Widget _greeting() {
    final p = ProfileService.current;
    final name =
        p.goal.isNotEmpty ? 'For your ${p.goal.toLowerCase()} goal' : 'Today';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 4),
        Text("Hit your numbers — don't track every gram",
            style: Theme.of(context).textTheme.headlineMedium),
      ],
    );
  }

  Widget _errorCard() => Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppTheme.accentRed.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.accentRed.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber, color: AppTheme.accentRed),
            const SizedBox(width: 10),
            Expanded(
              child: Text("Couldn't generate today's plan: $_planError",
                  style: const TextStyle(color: AppTheme.textPrimary)),
            ),
            TextButton(
                onPressed: _generatePlan, child: const Text('Retry')),
          ],
        ),
      );

  Widget _targetsCard() {
    final p = _plan!;
    final calPct = p.calorieTarget == 0
        ? 0.0
        : (_eatenCalories / p.calorieTarget).clamp(0.0, 1.0);
    final protPct = p.proteinGrams == 0
        ? 0.0
        : (_eatenProtein / p.proteinGrams).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Expanded(
              child: _Target(
                  label: 'Calories',
                  current: _eatenCalories,
                  target: p.calorieTarget,
                  unit: 'kcal',
                  pct: calPct,
                  color: AppTheme.neonCyan)),
          const SizedBox(width: 12),
          Expanded(
              child: _Target(
                  label: 'Protein',
                  current: _eatenProtein,
                  target: p.proteinGrams,
                  unit: 'g',
                  pct: protPct,
                  color: AppTheme.neonLime)),
        ],
      ),
    );
  }

  Widget _proteinGapAlert() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.neonLime.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.neonLime),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.bolt, color: AppTheme.neonLime),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Protein gap alert",
                      style: TextStyle(
                          color: AppTheme.neonLime,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    "You're at ${_eatenProtein}g of ${_plan!.proteinGrams}g protein. A quick high-protein snack now (Greek yogurt, eggs, or a protein shake) closes the gap.",
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        height: 1.4,
                        fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _mealCard(MealSuggestion m) => Container(
        margin: const EdgeInsets.only(bottom: 12),
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
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.neonLime.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(m.slot,
                      style: const TextStyle(
                          color: AppTheme.neonLime,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                Text(m.cost,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            Text(m.name,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(m.description,
                style: const TextStyle(
                    color: AppTheme.textSecondary, height: 1.4, fontSize: 13)),
            const SizedBox(height: 10),
            Row(
              children: [
                _miniStat('${m.calories} kcal', AppTheme.neonCyan),
                const SizedBox(width: 8),
                _miniStat('${m.proteinGrams}g protein', AppTheme.neonLime),
              ],
            ),
          ],
        ),
      );

  Widget _miniStat(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );

  Widget _shoppingNoteCard() => Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(
          color: AppTheme.neonCyan.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.neonCyan.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.shopping_basket_outlined,
                color: AppTheme.neonCyan, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_plan!.shoppingNote,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      height: 1.4)),
            ),
          ],
        ),
      );

  Widget _loggedCard(LoggedMeal m) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            const Icon(Icons.check, color: AppTheme.neonLime, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(m.description,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 14)),
            ),
            Text('${m.approxCalories} kcal',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(width: 8),
            Text('${m.approxProteinGrams}g P',
                style: const TextStyle(
                    color: AppTheme.neonLime, fontSize: 12)),
          ],
        ),
      );
}

class _Target extends StatelessWidget {
  final String label;
  final int current;
  final int target;
  final String unit;
  final double pct;
  final Color color;
  const _Target({
    required this.label,
    required this.current,
    required this.target,
    required this.unit,
    required this.pct,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
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
            Text('$current',
                style: TextStyle(
                    color: color,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    height: 1)),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('/ $target $unit',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 5,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}
