import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../theme.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  IconData _getLiftIcon(String lift) {
    if (lift.contains('Squat')) return Icons.accessibility_new;
    if (lift.contains('Deadlift')) return Icons.fitness_center;
    return Icons.horizontal_rule_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Workout History"),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('workouts')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.orange, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      "Running in Offline Mode",
                      style: textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Firestore rules or connection might be pending. Any workouts saved during this session will sync when online.",
                      style: TextStyle(color: AppTheme.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.neonLime),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, color: AppTheme.textSecondary.withOpacity(0.5), size: 64),
                  const SizedBox(height: 16),
                  Text(
                    "No workouts logged yet",
                    style: textTheme.titleLarge?.copyWith(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Completed sessions from the AI Coach will appear here.",
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final lift = data['lift'] ?? 'Unknown Lift';
              final reps = data['reps'] ?? 0;
              final timestamp = data['timestamp'] as Timestamp?;
              
              String formattedDate = "Just now";
              if (timestamp != null) {
                formattedDate = DateFormat('MMM d, yyyy • h:mm a').format(timestamp.toDate());
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.neonLime.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getLiftIcon(lift),
                        color: AppTheme.neonLime,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lift,
                            style: textTheme.titleLarge?.copyWith(fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formattedDate,
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          "$reps",
                          style: const TextStyle(
                            color: AppTheme.neonCyan,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          "REPS",
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
