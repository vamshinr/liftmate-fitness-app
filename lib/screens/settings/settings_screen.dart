import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../config.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  String _maskApiKey(String key) {
    if (key.length <= 15) return key;
    return "${key.substring(0, 14)}..."
        "${key.substring(key.length - 12)}";
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // API Key section
            Text(
              "Model Integration",
              style: textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              "LiftMate comes with native, built-in access to Anthropic Claude. Your nutrition advice, program generation, and chat responses are processed securely using our dedicated models.",
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 20),
            // Integrated Key Info Box
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.neonLime.withOpacity(0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.vpn_key, color: AppTheme.neonLime, size: 20),
                      SizedBox(width: 8),
                      Text(
                        "CLAUDE INTEGRATION ACTIVE",
                        style: TextStyle(
                          color: AppTheme.neonLime,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _maskApiKey(claudeApiKey),
                    style: const TextStyle(
                      fontFamily: "Courier",
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Token Tier: Claude 3.5 Sonnet (Production)",
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            // App Information
            Text(
              "System Diagnostics",
              style: textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _buildSystemRow("Firebase Link", "CONNECTED (liftmate-17fb6)", AppTheme.neonLime),
            _buildSystemRow("Pose Engine", "Vision Framework Local v2.0", AppTheme.textPrimary),
            _buildSystemRow("GTM Platform", "Flutter + iOS SDK 19.0", AppTheme.textPrimary),
            _buildSystemRow("Local Database", "SharedPreferences + Cache", AppTheme.textPrimary),
            const SizedBox(height: 40),
            // Reset / Sign Out Info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.04)),
              ),
              child: const Text(
                "You are currently running the developer build of LiftMate Fitness App. All analytics and logs are synchronized with Firebase Console for debugging.",
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemRow(String key, String value, [Color valueColor = AppTheme.textSecondary]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(key, style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
