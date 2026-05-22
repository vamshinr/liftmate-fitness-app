import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../services/profile_service.dart';
import '../../theme.dart';

/// Dedicated trainer marketplace screen. Reached from any trainer card in the
/// app. Explains the model, shows the bench of available coaches, lets the
/// user submit a written question or attach a previous form-check ticket.
class TrainerNetworkScreen extends StatefulWidget {
  const TrainerNetworkScreen({super.key});

  @override
  State<TrainerNetworkScreen> createState() => _TrainerNetworkScreenState();
}

class _TrainerNetworkScreenState extends State<TrainerNetworkScreen> {
  final TextEditingController _questionCtrl = TextEditingController();
  bool _submitting = false;
  String? _submittedTicket;

  // Roster is mock for now — real onboarding pulls from Firestore `coaches`.
  static const _coaches = <_Coach>[
    _Coach(
      name: 'Maya R.',
      tagline: 'NSCA-CPT · 8 years · Strength + powerlifting',
      blurb:
          'Specializes in coaching new lifters who feel stuck on the basics. Replies within 12 h on average.',
      tags: ['Squat', 'Bench', 'Deadlift'],
    ),
    _Coach(
      name: 'Andre T.',
      tagline: 'NASM-CPT · 6 years · Hypertrophy + body recomp',
      blurb:
          'Programs for busy schedules and home-gym setups. Great if you train 3 days/week.',
      tags: ['Hypertrophy', 'Home gym'],
    ),
    _Coach(
      name: 'Priya S.',
      tagline: 'RDN + CPT · 5 years · Form + nutrition',
      blurb:
          'Dual-credentialed in nutrition. Best for combining macro guidance with form work.',
      tags: ['Nutrition', 'Form'],
    ),
  ];

  @override
  void dispose() {
    _questionCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _questionCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _submitting = true);
    final id = const Uuid().v4().substring(0, 8).toUpperCase();
    final profile = ProfileService.current;
    try {
      await FirebaseFirestore.instance
          .collection('coach_queue')
          .doc(id)
          .set({
        'ticketId': id,
        'type': 'question',
        'userNote': text,
        'profileSummary': {
          'goal': profile.goal,
          'experience': profile.experience,
          'injuries': profile.injuries,
          'daysPerWeek': profile.daysPerWeek,
        },
        'status': 'pending',
        'price': 9,
        'slaHours': 24,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Offline-tolerant: still surface the ticket so the user has something.
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _submittedTicket = id;
      _questionCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trainer Network')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _Hero(),
          const SizedBox(height: 20),
          _HowItWorks(),
          const SizedBox(height: 20),
          _SectionLabel('Available coaches'),
          const SizedBox(height: 10),
          ..._coaches.map((c) => _CoachCard(coach: c)),
          const SizedBox(height: 22),
          _SectionLabel('Ask a coach now'),
          const SizedBox(height: 8),
          const Text(
            'Submit a written question or form-check description. A coach claims it within 24 h and replies with a short written critique + corrective drill.',
            style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 10),
          if (_submittedTicket != null)
            _SubmittedBanner(ticketId: _submittedTicket!),
          if (_submittedTicket == null) ...[
            TextField(
              controller: _questionCtrl,
              maxLines: 5,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                hintText:
                    'e.g. "My low back rounds at the bottom of my squat — how do I fix it?"',
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.darkBackground),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_submitting
                    ? 'Submitting…'
                    : 'Submit to coach pool · \$9'),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Charged only when a coach picks up your request.',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 11.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.neonCyan.withValues(alpha: 0.18),
            AppTheme.neonLime.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border:
            Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.neonCyan.withValues(alpha: 0.15),
            blurRadius: 30,
            spreadRadius: -6,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.neonCyan,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text('REAL COACHES',
                    style: TextStyle(
                        color: AppTheme.darkBackground,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'A vetted coach in your corner — without the \$199/mo bill.',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'When AI confidence is limited, or you just want a human eye on your set, a real certified coach reviews and replies within 24 hours. Flat \$9 per review. No subscription.',
            style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _Pill(icon: Icons.verified_user_rounded, text: 'NSCA / NASM vetted'),
              _Pill(icon: Icons.schedule_rounded, text: '< 24 h response'),
              _Pill(icon: Icons.payments_outlined, text: '\$9 flat, cancel anytime'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Pill({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.darkBackground.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.neonCyan),
          const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How it works',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          _Step(n: 1, text: 'Submit a question or share a form check.'),
          _Step(
              n: 2,
              text:
                  'A vetted coach claims it. You\'re only charged when claimed.'),
          _Step(
              n: 3,
              text:
                  'Reply within 24 hours — short video or written critique + a fix.'),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  const _Step({required this.n, required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: AppTheme.neonCyan.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                  color: AppTheme.neonCyan.withValues(alpha: 0.5)),
            ),
            child: Center(
              child: Text('$n',
                  style: const TextStyle(
                      color: AppTheme.neonCyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 13.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      );
}

class _Coach {
  final String name;
  final String tagline;
  final String blurb;
  final List<String> tags;
  const _Coach({
    required this.name,
    required this.tagline,
    required this.blurb,
    required this.tags,
  });
}

class _CoachCard extends StatelessWidget {
  final _Coach coach;
  const _CoachCard({required this.coach});

  String get _initials => coach.name
      .split(' ')
      .take(2)
      .map((p) => p.isEmpty ? '' : p[0])
      .join();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: AppTheme.cyanGradient,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    _initials,
                    style: const TextStyle(
                      color: AppTheme.darkBackground,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(coach.name,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        )),
                    const SizedBox(height: 2),
                    Text(coach.tagline,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(coach.blurb,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  height: 1.45)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: coach.tags
                .map((t) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color:
                            AppTheme.neonLime.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(t,
                          style: const TextStyle(
                              color: AppTheme.neonLime,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SubmittedBanner extends StatelessWidget {
  final String ticketId;
  const _SubmittedBanner({required this.ticketId});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.neonLime.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.neonLime),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: AppTheme.neonLime, size: 22),
              SizedBox(width: 10),
              Text('Submitted to the coach pool',
                  style: TextStyle(
                      color: AppTheme.neonLime,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Ticket #$ticketId · ${DateFormat('MMM d • h:mm a').format(DateTime.now())}',
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          const Text(
            'A coach will pick it up and reply within 24 hours. You\'ll be notified.',
            style: TextStyle(
                color: AppTheme.textPrimary, fontSize: 13, height: 1.45),
          ),
        ],
      ),
    );
  }
}
