import 'package:flutter/material.dart';
import '../theme.dart';

/// Trainer network is LiftMate's escape hatch when AI confidence is limited.
/// This card is the same look-and-feel everywhere it appears: Plan tab as a
/// hero promo, Form-check results as an upsell, Coach chat as a fallback.
class TrainerNetworkCard extends StatelessWidget {
  final String title;
  final String description;
  final String ctaLabel;
  final VoidCallback? onTap;
  final bool compact;

  const TrainerNetworkCard({
    super.key,
    this.title = 'Trainer network',
    this.description =
        'Stuck or unsure? Get a video review from a vetted human coach in under 24 hours.',
    this.ctaLabel = 'Request a coach review · \$9',
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final pad = compact ? 14.0 : 18.0;
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.neonCyan.withValues(alpha: 0.12),
            AppTheme.neonLime.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.neonCyan.withValues(alpha: 0.12),
            blurRadius: 24,
            spreadRadius: -4,
          ),
        ],
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
                  color: AppTheme.neonCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppTheme.neonCyan.withValues(alpha: 0.4)),
                ),
                child:
                    const Icon(Icons.support_agent, color: AppTheme.neonCyan),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TRAINER NETWORK',
                      style: TextStyle(
                        color: AppTheme.neonCyan,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: const [
                _Bullet(text: 'Vetted independent coaches'),
                _Bullet(text: 'Response within 24 h'),
                _Bullet(text: 'Short video / written critique'),
              ],
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.neonCyan,
                foregroundColor: AppTheme.darkBackground,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: onTap,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(ctaLabel,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.darkBackground.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline,
              size: 12, color: AppTheme.neonCyan),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
