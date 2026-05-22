import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/user_profile.dart';
import '../../services/profile_service.dart';
import '../../theme.dart';
import '../../widgets/trainer_network_card.dart';
import '../navigation_hub.dart';
import '../trainers/trainer_network_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late UserProfile _profile;

  @override
  void initState() {
    super.initState();
    _profile = ProfileService.current;
  }

  Future<void> _saveAndReload(UserProfile updated) async {
    await ProfileService.save(updated);
    if (!mounted) return;
    setState(() => _profile = updated);
  }

  Future<void> _editGoal() async {
    final result = await _pickFrom(
      title: 'Primary goal',
      options: const [
        'Muscle Building',
        'Strength',
        'Fat Loss',
        'Athletic Training',
        'General Fitness',
        'Endurance',
      ],
      current: _profile.goal,
    );
    if (result != null) await _saveAndReload(_profile.copyWith(goal: result));
  }

  Future<void> _editExperience() async {
    final result = await _pickFrom(
      title: 'Experience',
      options: const ['Beginner', 'Intermediate', 'Advanced'],
      current: _profile.experience,
    );
    if (result != null) {
      await _saveAndReload(_profile.copyWith(experience: result));
    }
  }

  Future<void> _editDays() async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) {
        int value = _profile.daysPerWeek;
        return StatefulBuilder(builder: (ctx, setSt) {
          return AlertDialog(
            title: const Text('Days per week'),
            content: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline,
                      color: AppTheme.neonLime),
                  onPressed:
                      value > 1 ? () => setSt(() => value--) : null,
                ),
                SizedBox(
                  width: 56,
                  child: Text('$value',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppTheme.neonLime,
                          fontSize: 28,
                          fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline,
                      color: AppTheme.neonLime),
                  onPressed:
                      value < 7 ? () => setSt(() => value++) : null,
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context, value),
                  child: const Text('Save')),
            ],
          );
        });
      },
    );
    if (result != null) {
      await _saveAndReload(_profile.copyWith(daysPerWeek: result));
    }
  }

  Future<String?> _pickFrom({
    required String title,
    required List<String> options,
    required String current,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.cardBgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(title,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.left),
              const SizedBox(height: 12),
              ...options.map((o) {
                final sel = o == current;
                return InkWell(
                  onTap: () => Navigator.pop(ctx, o),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: sel
                          ? AppTheme.neonLime.withValues(alpha: 0.10)
                          : AppTheme.cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: sel
                              ? AppTheme.neonLime
                              : AppTheme.hairline),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(o,
                              style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: sel
                                      ? FontWeight.w700
                                      : FontWeight.w500)),
                        ),
                        if (sel)
                          const Icon(Icons.check_circle,
                              color: AppTheme.neonLime, size: 20),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _resetOnboarding() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Redo onboarding?'),
        content: const Text(
            'This clears your saved profile and restarts the welcome flow. Your form check history is not affected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ProfileService.clear();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const NavigationHub()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('You'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
        children: [
          _ProfileHeader(profile: _profile),
          const SizedBox(height: 16),
          _StatsGrid(),
          const SizedBox(height: 16),
          TrainerNetworkCard(
            title: 'Your coach network',
            description:
                'Submit a form check or question; a vetted human coach replies in under 24 hours.',
            ctaLabel: 'Browse trainers · \$9 per review',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const TrainerNetworkScreen()),
            ),
          ),
          const SizedBox(height: 20),
          _SectionTitle('Profile'),
          const SizedBox(height: 10),
          _editRow(
            icon: Icons.flag_outlined,
            label: 'Goal',
            value: _profile.goal,
            onTap: _editGoal,
          ),
          _editRow(
            icon: Icons.timeline_rounded,
            label: 'Experience',
            value: _profile.experience,
            onTap: _editExperience,
          ),
          _editRow(
            icon: Icons.calendar_today_rounded,
            label: 'Days / week',
            value: '${_profile.daysPerWeek}',
            onTap: _editDays,
          ),
          _staticRow(
            icon: Icons.fitness_center_rounded,
            label: 'Equipment',
            value: _profile.equipment.isEmpty
                ? 'Bodyweight'
                : _profile.equipment.join(', '),
          ),
          _staticRow(
            icon: Icons.health_and_safety_outlined,
            label: 'Injuries',
            value: _profile.injuries.isEmpty
                ? 'None reported'
                : _profile.injuries.join(', '),
          ),
          _staticRow(
            icon: Icons.restaurant_outlined,
            label: 'Diet',
            value: _profile.dietaryPreference,
          ),
          const SizedBox(height: 20),
          _SectionTitle('Recent activity'),
          const SizedBox(height: 10),
          const _RecentFormChecks(),
          const SizedBox(height: 20),
          _SectionTitle('Settings'),
          const SizedBox(height: 10),
          _actionRow(
            icon: Icons.refresh_rounded,
            label: 'Redo onboarding',
            description: 'Clear profile and restart the welcome flow.',
            onTap: _resetOnboarding,
            tint: AppTheme.neonLime,
          ),
          const SizedBox(height: 24),
          const _AboutCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _editRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: AppTheme.hairline),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppTheme.textSecondary, size: 20),
                const SizedBox(width: 12),
                Text(label,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    )),
                const Spacer(),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textTertiary, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _staticRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: 20),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              )),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow({
    required IconData icon,
    required String label,
    required String description,
    required VoidCallback onTap,
    required Color tint,
  }) {
    return Material(
      color: AppTheme.cardBg,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppTheme.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: tint, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(description,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final UserProfile profile;
  const _ProfileHeader({required this.profile});

  String get _initials {
    final g = profile.goal;
    if (g.isEmpty) return 'LM';
    final parts = g.split(' ');
    return parts.take(2).map((p) => p.isEmpty ? '' : p[0]).join();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.neonLime.withValues(alpha: 0.18),
            AppTheme.neonCyan.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.neonLime.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: AppTheme.limeGradient,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _initials.toUpperCase(),
                style: const TextStyle(
                  color: AppTheme.darkBackground,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.goal,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${profile.experience} · ${profile.daysPerWeek} days/wk',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QuerySnapshot>>(
      stream: _combinedCountsStream(),
      builder: (context, snapshot) {
        int formChecks = 0;
        int meals = 0;
        int programs = 0;
        if (snapshot.hasData) {
          formChecks = snapshot.data![0].docs.length;
          meals = snapshot.data![1].docs.length;
          programs = snapshot.data![2].docs.length;
        }
        return Row(
          children: [
            Expanded(
                child: _StatCard(
                    label: 'Form checks',
                    value: '$formChecks',
                    icon: Icons.fitness_center_rounded,
                    color: AppTheme.neonLime)),
            const SizedBox(width: 10),
            Expanded(
                child: _StatCard(
                    label: 'Meals logged',
                    value: '$meals',
                    icon: Icons.restaurant_menu_rounded,
                    color: AppTheme.neonCyan)),
            const SizedBox(width: 10),
            Expanded(
                child: _StatCard(
                    label: 'Programs',
                    value: '$programs',
                    icon: Icons.auto_awesome_rounded,
                    color: AppTheme.neonViolet)),
          ],
        );
      },
    );
  }

  Stream<List<QuerySnapshot>> _combinedCountsStream() async* {
    final fs = FirebaseFirestore.instance;
    await for (final fc in fs.collection('form_checks').snapshots()) {
      final ml = await fs.collection('meal_logs').get();
      final pr = await fs.collection('programs').get();
      yield [fc, ml, pr];
    }
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1,
              )),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              )),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _RecentFormChecks extends StatelessWidget {
  const _RecentFormChecks();
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('form_checks')
          .orderBy('createdAt', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _EmptyHint(
            icon: Icons.cloud_off_rounded,
            text: 'Offline — sync when reconnected.',
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _EmptyHint(
            icon: Icons.history_rounded,
            text: 'No form checks yet. Run one from the Form tab.',
          );
        }
        return Column(
          children: docs.map((d) {
            final data = d.data() as Map<String, dynamic>;
            return _ActivityRow(data: data);
          }).toList(),
        );
      },
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ActivityRow({required this.data});
  @override
  Widget build(BuildContext context) {
    final lift = data['lift'] as String? ?? '?';
    final score = (data['formScore'] as num?)?.toInt() ?? 0;
    final ts = data['createdAt'];
    String when = 'just now';
    if (ts is Timestamp) {
      when = DateFormat('MMM d • h:mm a').format(ts.toDate());
    }
    final color = score >= 80
        ? AppTheme.neonLime
        : (score >= 60 ? AppTheme.neonCyan : AppTheme.accentRed);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text('$score',
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  )),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lift,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 2),
                Text(when,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    )),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppTheme.textTertiary),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyHint({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: const Text(
        'LiftMate runs pose detection on-device, then an AI coach synthesizes objective measurements into one clear correction per lift. When confidence is limited, a vetted human coach can review for \$9.',
        style: TextStyle(
            color: AppTheme.textSecondary, fontSize: 12.5, height: 1.5),
      ),
    );
  }
}
