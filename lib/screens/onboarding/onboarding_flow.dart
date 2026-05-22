import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../models/user_profile.dart';
import '../../services/profile_service.dart';

class OnboardingFlow extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingFlow({super.key, required this.onComplete});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final PageController _pageController = PageController();
  int _page = 0;

  // Working profile state
  UserProfile _profile = const UserProfile();

  // Intake controllers
  final _ageCtrl = TextEditingController();
  final _bwCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();

  // PAR-Q answers — red flags
  final Map<String, bool> _redFlags = {
    'Chest pain during or after activity': false,
    'Dizziness or loss of balance': false,
    'A diagnosed heart condition': false,
    'Severe joint pain that limits daily activity': false,
    'A doctor told me not to exercise without supervision': false,
  };

  // Non-stop injuries (worked around, not blocked)
  final Map<String, bool> _injuries = {
    'Lower back': false,
    'Knee': false,
    'Shoulder': false,
    'Hip': false,
    'Wrist / elbow': false,
    'Neck': false,
  };

  final List<String> _allEquipment = [
    'Barbell',
    'Dumbbells',
    'Pull-up Bar',
    'Bench',
    'Cable Machine',
    'Squat Rack',
    'Resistance Bands',
    'Kettlebell',
    'Bodyweight only',
  ];
  final Set<String> _selectedEquip = {};

  bool _hardStop = false;

  static const _goals = [
    'Muscle Building',
    'Strength',
    'Fat Loss',
    'General Fitness',
  ];

  static const _experiences = [
    'Brand new — first month',
    'Beginner — under 1 year',
    'Intermediate',
    'Advanced',
  ];

  static const _budgets = ['Tight', 'Moderate', 'Flexible'];
  static const _diets = [
    'No restrictions',
    'Vegetarian',
    'Vegan',
    'Pescatarian',
    'Halal',
    'Kosher',
    'Lactose-free',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _ageCtrl.dispose();
    _bwCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _pages.length - 1) {
      setState(() => _page += 1);
      _pageController.animateToPage(
        _page,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _finish();
    }
  }

  void _back() {
    if (_page == 0) return;
    setState(() => _page -= 1);
    _pageController.animateToPage(
      _page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _finish() async {
    final injuries = _injuries.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
    final redFlags = _redFlags.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    final exp = _profile.experience;
    final needsOrientation = exp == 'Brand new — first month';

    final completed = _profile.copyWith(
      injuries: injuries,
      medicalConditions: redFlags,
      clearedForExercise: redFlags.isEmpty,
      equipment: _selectedEquip.toList(),
      needsGymOrientation: needsOrientation,
      onboardingComplete: true,
      ageYears: int.tryParse(_ageCtrl.text.trim()),
      bodyweightKg: double.tryParse(_bwCtrl.text.trim()),
      heightCm: double.tryParse(_heightCtrl.text.trim()),
    );

    await ProfileService.save(completed);
    widget.onComplete();
  }

  List<Widget> get _pages => [
        _welcomePage(),
        _explainerPage(),
        _goalExperiencePage(),
        _intakePage(),
        _injuryScreeningPage(),
        if (_hardStop) _hardStopPage(),
        _equipmentPage(),
        _nutritionContextPage(),
        if (_profile.experience == 'Brand new — first month') _gymOrientationPage(),
        _warmupPage(),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            _progressBar(),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _pages.length,
                onPageChanged: (p) => setState(() => _page = p),
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: _pages[i],
                ),
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _progressBar() {
    final pct = (_page + 1) / _pages.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Step ${_page + 1} of ${_pages.length}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const Spacer(),
              if (_page > 0 && !_hardStop)
                TextButton(
                  onPressed: _back,
                  child: const Text('Back',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 4,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(AppTheme.neonLime),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    if (_hardStop) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.cardBg,
              foregroundColor: AppTheme.textPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () {
              setState(() {
                _hardStop = false;
                _redFlags.updateAll((k, v) => false);
              });
            },
            child: const Text("I understand — go back"),
          ),
        ),
      );
    }
    final canProceed = _canProceed();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor:
                canProceed ? AppTheme.neonLime : Colors.white12,
            foregroundColor: AppTheme.darkBackground,
            disabledBackgroundColor: Colors.white12,
            disabledForegroundColor: AppTheme.textSecondary,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: canProceed ? _next : null,
          child: Text(
            _page == _pages.length - 1 ? "Let's go" : 'Continue',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ),
    );
  }

  bool _canProceed() {
    // Pages with required fields
    if (_page == 2) {
      return _profile.goal.isNotEmpty && _profile.experience.isNotEmpty;
    }
    return true;
  }

  // ---- pages ----

  Widget _welcomePage() => _Page(
        title: 'Welcome to LiftMate',
        subtitle:
            "Your AI coach for getting strong and staying safe — built for people who feel intimidated by the gym.",
        child: const Column(
          children: [
            SizedBox(height: 12),
            _Bullet('Form analysis on your phone'),
            _Bullet('Cheap, simple nutrition guidance'),
            _Bullet('A real human coach when you need one'),
          ],
        ),
      );

  Widget _explainerPage() => _Page(
        title: 'What this app does — and doesn\'t',
        subtitle: 'Read this once. It matters.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SizedBox(height: 8),
            _ExplainerRow(
              icon: Icons.check_circle,
              color: AppTheme.neonLime,
              title: 'AI can',
              body:
                  "Spot common form mistakes from photos, give you a beginner-friendly program, and suggest simple meals.",
            ),
            _ExplainerRow(
              icon: Icons.support_agent,
              color: AppTheme.neonCyan,
              title: 'A human coach can',
              body:
                  "Give you nuanced, accountable feedback for trickier cases. You can request a review for \$9-15 anytime.",
            ),
            _ExplainerRow(
              icon: Icons.cancel,
              color: AppTheme.accentRed,
              title: 'AI will never claim',
              body:
                  "To diagnose injuries, treat pain, or replace a doctor or physical therapist.",
            ),
          ],
        ),
      );

  Widget _goalExperiencePage() => _Page(
        title: 'What are you working toward?',
        subtitle: 'We tailor everything around this.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text('Primary goal',
                style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _goals
                  .map((g) => _ChipChoice(
                        label: g,
                        selected: _profile.goal == g,
                        onTap: () => setState(() {
                          _profile = _profile.copyWith(goal: g);
                        }),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 24),
            const Text('Experience level',
                style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Column(
              children: _experiences
                  .map((e) => _RadioRow(
                        label: e,
                        selected: _profile.experience == e,
                        onTap: () =>
                            setState(() => _profile = _profile.copyWith(experience: e)),
                      ))
                  .toList(),
            ),
          ],
        ),
      );

  Widget _intakePage() => _Page(
        title: 'A few quick numbers',
        subtitle: 'Used for calorie targets and training load. Skip any you don\'t want to share.',
        child: Column(
          children: [
            const SizedBox(height: 8),
            _NumberField(
                label: 'Age (years)', ctrl: _ageCtrl, hint: 'e.g., 28'),
            const SizedBox(height: 12),
            _NumberField(
                label: 'Bodyweight (kg)', ctrl: _bwCtrl, hint: 'e.g., 75'),
            const SizedBox(height: 12),
            _NumberField(
                label: 'Height (cm)', ctrl: _heightCtrl, hint: 'e.g., 178'),
            const SizedBox(height: 16),
            _DropdownRow(
              label: 'Sex (for calorie estimate)',
              value: _profile.sex,
              options: const ['Male', 'Female', 'Prefer not to say'],
              onChanged: (v) => setState(
                  () => _profile = _profile.copyWith(sex: v ?? _profile.sex)),
            ),
            const SizedBox(height: 12),
            _SliderRow(
              label: 'Training days per week',
              value: _profile.daysPerWeek.toDouble(),
              min: 1,
              max: 6,
              divisions: 5,
              valueLabel: '${_profile.daysPerWeek}',
              onChanged: (v) => setState(() =>
                  _profile = _profile.copyWith(daysPerWeek: v.round())),
            ),
          ],
        ),
      );

  Widget _injuryScreeningPage() => _Page(
        title: 'Quick safety check',
        subtitle:
            'Honest answers protect you. This stays on your device.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            const Text(
              'Have you experienced any of the following? Tap any that apply.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            ..._redFlags.entries.map(
              (e) => _CheckRow(
                label: e.key,
                value: e.value,
                onChanged: (v) {
                  setState(() {
                    _redFlags[e.key] = v;
                    if (v) _hardStop = true;
                  });
                },
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 16),
            const Text(
              'Any nagging joint pain or past injuries we should program around?',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _injuries.entries
                  .map((e) => _ChipChoice(
                        label: e.key,
                        selected: e.value,
                        onTap: () => setState(
                            () => _injuries[e.key] = !e.value),
                      ))
                  .toList(),
            ),
          ],
        ),
      );

  Widget _hardStopPage() => _Page(
        title: 'Please talk to a clinician first',
        subtitle:
            'One or more of your answers needs medical clearance before we coach you.',
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.accentRed.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.accentRed.withOpacity(0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Icon(Icons.medical_services, color: AppTheme.accentRed),
              SizedBox(height: 12),
              Text(
                'LiftMate is not a substitute for a doctor.',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Please get cleared by a physician before resistance training. When you have clearance, come back and uncheck the flagged answer.',
                style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
              ),
              SizedBox(height: 12),
              Text(
                'If you are experiencing chest pain or severe symptoms RIGHT NOW, contact emergency services.',
                style: TextStyle(
                    color: AppTheme.accentRed, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );

  Widget _equipmentPage() => _Page(
        title: 'What gear do you have access to?',
        subtitle: 'Pick everything that applies. We\'ll build programs around it.',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _allEquipment
              .map((e) => _ChipChoice(
                    label: e,
                    selected: _selectedEquip.contains(e),
                    onTap: () => setState(() {
                      if (_selectedEquip.contains(e)) {
                        _selectedEquip.remove(e);
                      } else {
                        _selectedEquip.add(e);
                      }
                    }),
                  ))
              .toList(),
        ),
      );

  Widget _nutritionContextPage() => _Page(
        title: 'Eating preferences',
        subtitle:
            "We'll suggest cheap, simple meals that hit your protein and calorie targets.",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            _DropdownRow(
              label: 'Food budget per day',
              value: _profile.budgetPerDay,
              options: _budgets,
              onChanged: (v) => setState(() =>
                  _profile = _profile.copyWith(budgetPerDay: v ?? 'Moderate')),
            ),
            const SizedBox(height: 12),
            _DropdownRow(
              label: 'Dietary preference',
              value: _profile.dietaryPreference,
              options: _diets,
              onChanged: (v) => setState(() => _profile =
                  _profile.copyWith(dietaryPreference: v ?? 'No restrictions')),
            ),
          ],
        ),
      );

  Widget _warmupPage() => _Page(
        title: 'Warm up — every single session',
        subtitle:
            'The #1 thing beginners skip and regret. 5 minutes saves you weeks of injury setbacks.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(top: 8, bottom: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.neonLime.withValues(alpha: 0.14),
                    AppTheme.neonCyan.withValues(alpha: 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(
                    color: AppTheme.neonLime.withValues(alpha: 0.45)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.local_fire_department_rounded,
                      color: AppTheme.neonLime, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Cold muscles tear, warm muscles grow. Warming up raises tissue temp, primes your nervous system, and surfaces niggles before you load them.',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13.5,
                          height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const Text(
              'The 5-minute recipe',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            const _NumberedTip(
                n: 1,
                title: '2 min light cardio',
                body:
                    'Easy bike, rower, or brisk walk on a treadmill. Goal: light sweat, not winded.'),
            const _NumberedTip(
                n: 2,
                title: '5 dynamic mobility moves',
                body:
                    'Leg swings, hip openers, arm circles, cat-cow, ankle rocks. 10 reps each. No static stretching before lifting.'),
            const _NumberedTip(
                n: 3,
                title: '2–3 ramp-up sets',
                body:
                    'Before your working sets, do the same lift with just the bar, then 50%, then 75% of your working weight. Grease the groove.'),
            const _NumberedTip(
                n: 4,
                title: 'Skip the static stretches',
                body:
                    'Long holds (>30 s) before lifting actually reduce strength. Save deep stretching for after the session or rest days.'),
            const _NumberedTip(
                n: 5,
                title: 'If something pinches, stop',
                body:
                    'Pain in the line of the lift = a red flag, not soreness. Adjust the move, drop the weight, or skip it. Never train through pain.'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.cardBg,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(color: AppTheme.hairline),
              ),
              child: const Row(
                children: [
                  Icon(Icons.tips_and_updates_outlined,
                      color: AppTheme.neonCyan, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Cool-down is optional. A 2-minute slow walk + a few static stretches afterwards helps recovery.',
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12.5,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _gymOrientationPage() => _Page(
        title: 'Your first 30 minutes at the gym',
        subtitle: 'Brand-new? Read this once. It removes most of the anxiety.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SizedBox(height: 8),
            _NumberedTip(
                n: 1,
                title: 'Pick a low-traffic time',
                body:
                    'Mid-morning or mid-afternoon weekdays. Less crowded = less pressure.'),
            _NumberedTip(
                n: 2,
                title: 'Walk a full lap first',
                body:
                    'Find the locker room, water fountains, dumbbell rack, cardio area. Get oriented.'),
            _NumberedTip(
                n: 3,
                title: 'Start with the easiest machine in your plan',
                body:
                    'Use the Gym Scan tab if you don\'t know how a machine works — point your camera at it.'),
            _NumberedTip(
                n: 4,
                title: 'Re-rack your weights',
                body: 'It\'s the one unwritten rule. That\'s it.'),
            _NumberedTip(
                n: 5,
                title: 'Headphones are armor',
                body:
                    'Everyone has them in. Nobody is watching you. They\'re thinking about themselves.'),
          ],
        ),
      );
}

// ---- shared layout helpers ----

class _Page extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _Page({required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(title,
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(subtitle,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 14, height: 1.4)),
          const SizedBox(height: 16),
          child,
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check, color: AppTheme.neonLime, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      height: 1.4))),
        ],
      ),
    );
  }
}

class _ExplainerRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _ExplainerRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, height: 1.4, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ChipChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.neonLime.withOpacity(0.12) : AppTheme.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.neonLime : Colors.white12,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? AppTheme.neonLime : AppTheme.textPrimary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 14,
            )),
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RadioRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.neonLime.withOpacity(0.08) : AppTheme.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? AppTheme.neonLime : Colors.white12),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppTheme.neonLime : AppTheme.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 15))),
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _CheckRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: value ? AppTheme.accentRed.withOpacity(0.08) : AppTheme.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: value ? AppTheme.accentRed : Colors.white12),
        ),
        child: Row(
          children: [
            Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              color: value ? AppTheme.accentRed : AppTheme.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 14, height: 1.3)),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController ctrl;
  const _NumberField({required this.label, required this.hint, required this.ctrl});
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
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppTheme.cardBg,
            hintText: hint,
            hintStyle: const TextStyle(color: AppTheme.textSecondary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _DropdownRow extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  const _DropdownRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
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
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: options.contains(value) ? value : options.first,
              isExpanded: true,
              dropdownColor: AppTheme.cardBg,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
              items: options
                  .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(valueLabel,
                style: const TextStyle(
                    color: AppTheme.neonLime,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: AppTheme.neonLime,
          inactiveColor: Colors.white12,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _NumberedTip extends StatelessWidget {
  final int n;
  final String title;
  final String body;
  const _NumberedTip({required this.n, required this.title, required this.body});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppTheme.neonLime.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.neonLime),
            ),
            child: Center(
              child: Text('$n',
                  style: const TextStyle(
                      color: AppTheme.neonLime,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, height: 1.4, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
