import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('History'),
          bottom: const TabBar(
            indicatorColor: AppTheme.neonLime,
            labelColor: AppTheme.neonLime,
            unselectedLabelColor: AppTheme.textSecondary,
            tabs: [
              Tab(text: 'Form checks'),
              Tab(text: 'Coach queue'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _FormChecksTab(textTheme: textTheme),
            _CoachQueueTab(textTheme: textTheme),
          ],
        ),
      ),
    );
  }
}

class _FormChecksTab extends StatelessWidget {
  final TextTheme textTheme;
  const _FormChecksTab({required this.textTheme});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('form_checks')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _OfflineBanner(message: '${snapshot.error}');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.neonLime));
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _EmptyState(
            icon: Icons.fitness_center,
            title: 'No form checks yet',
            subtitle:
                'Run a form check from the Form Check tab. Your scores will trend here.',
          );
        }

        // Trend strip: last 7 checks form scores
        final last7 = docs.take(7).toList().reversed.toList();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _TrendCard(
                docs: last7
                    .map((d) => d.data() as Map<String, dynamic>)
                    .toList()),
            const SizedBox(height: 20),
            Text('All checks',
                style: textTheme.titleLarge?.copyWith(fontSize: 16)),
            const SizedBox(height: 8),
            ...docs.map((d) {
              final data = d.data() as Map<String, dynamic>;
              return _FormCheckRow(data: data);
            }),
          ],
        );
      },
    );
  }
}

class _CoachQueueTab extends StatelessWidget {
  final TextTheme textTheme;
  const _CoachQueueTab({required this.textTheme});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('coach_queue')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _OfflineBanner(message: '${snapshot.error}');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.neonLime));
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _EmptyState(
            icon: Icons.support_agent,
            title: 'No coach reviews yet',
            subtitle:
                'After a form check, you can request a vetted human coach review for \$9. Pending reviews appear here.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: docs.map((d) {
            final data = d.data() as Map<String, dynamic>;
            return _CoachQueueRow(data: data);
          }).toList(),
        );
      },
    );
  }
}

class _TrendCard extends StatelessWidget {
  final List<Map<String, dynamic>> docs;
  const _TrendCard({required this.docs});
  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) return const SizedBox.shrink();
    final scores = docs
        .map((d) => (d['formScore'] as num?)?.toInt() ?? 0)
        .toList();
    final avg = scores.fold<int>(0, (s, n) => s + n) ~/ scores.length;
    return Container(
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
              Text('Last ${scores.length} form scores',
                  style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('avg $avg',
                  style: const TextStyle(
                      color: AppTheme.neonLime,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: scores.map((s) {
                final h = (s / 100) * 60;
                final color = s >= 80
                    ? AppTheme.neonLime
                    : (s >= 60 ? AppTheme.neonCyan : AppTheme.accentRed);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Container(
                      height: h,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormCheckRow extends StatelessWidget {
  final Map<String, dynamic> data;
  const _FormCheckRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final lift = data['lift'] as String? ?? 'Unknown';
    final score = (data['formScore'] as num?)?.toInt() ?? 0;
    final conf = (data['confidence'] as num?)?.toInt() ?? 0;
    final safety = data['safetyFlag'] as bool? ?? false;
    final correction = data['keyCorrection'] as String? ?? '';
    final ts = data['createdAt'];
    String when = 'Just now';
    if (ts is Timestamp) {
      when = DateFormat('MMM d • h:mm a').format(ts.toDate());
    } else if (data['timestamp'] is String) {
      final dt = DateTime.tryParse(data['timestamp'] as String);
      if (dt != null) when = DateFormat('MMM d • h:mm a').format(dt);
    }
    final color = score >= 80
        ? AppTheme.neonLime
        : (score >= 60 ? AppTheme.neonCyan : AppTheme.accentRed);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: safety ? AppTheme.accentRed.withOpacity(0.6) : Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text('$score',
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lift,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15)),
                    Text('$when · conf $conf%',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              if (safety)
                const Icon(Icons.warning_amber,
                    color: AppTheme.accentRed, size: 18),
            ],
          ),
          if (correction.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(correction,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

class _CoachQueueRow extends StatelessWidget {
  final Map<String, dynamic> data;
  const _CoachQueueRow({required this.data});
  @override
  Widget build(BuildContext context) {
    final lift = data['lift'] as String? ?? '?';
    final status = data['status'] as String? ?? 'pending';
    final ticket = data['ticketId'] as String? ?? '';
    final price = data['price'] as num? ?? 9;
    final ts = data['createdAt'];
    String when = 'Just now';
    if (ts is Timestamp) {
      when = DateFormat('MMM d • h:mm a').format(ts.toDate());
    }
    final statusColor = switch (status) {
      'responded' => AppTheme.neonLime,
      'in_review' => AppTheme.neonCyan,
      _ => AppTheme.textSecondary,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.support_agent,
                  color: AppTheme.neonCyan, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$lift — #$ticket',
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600)),
                    Text(when,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(status.replaceAll('_', ' '),
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Text('\$$price',
                  style: const TextStyle(
                      color: AppTheme.neonLime, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  final String message;
  const _OfflineBanner({required this.message});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, color: Colors.orange, size: 48),
          const SizedBox(height: 12),
          const Text('Running in offline mode',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppTheme.textSecondary.withOpacity(0.5), size: 56),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 18)),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }
}
