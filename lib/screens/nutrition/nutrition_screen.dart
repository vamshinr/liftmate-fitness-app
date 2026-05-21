import 'package:flutter/material.dart';
import '../../theme.dart';

class NutritionScreen extends StatelessWidget {
  const NutritionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Nutrition Coach"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Daily Decision Heading
            Text(
              "Today's Plan",
              style: textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              "No meticulous tracking. Just hit these two numbers today.",
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            // Target Numbers Row
            Row(
              children: [
                Expanded(
                  child: _buildTargetCard(
                    context,
                    "Calories",
                    "2,400 kcal",
                    "Target Limit",
                    AppTheme.neonCyan,
                    0.7,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTargetCard(
                    context,
                    "Protein",
                    "160 g",
                    "Minimum Target",
                    AppTheme.neonLime,
                    0.55,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            // Daily recommendations header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Suggested Budget Meals",
                  style: textTheme.titleLarge,
                ),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.refresh, size: 16, color: AppTheme.neonLime),
                  label: const Text("Swap All", style: TextStyle(color: AppTheme.neonLime)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Meal Cards
            _buildMealCard(
              context,
              "Breakfast",
              "Greek Yogurt & Peanut Butter Oatmeal",
              "550 kcal • 40g Protein • \$1.80 cost",
              "Mix 1 cup oats, 1 scoop whey or 1/2 cup Greek yogurt, and 1 tbsp peanut butter. Add water or milk. Cheap, fast, and high protein.",
              Icons.breakfast_dining,
            ),
            _buildMealCard(
              context,
              "Lunch",
              "Quick Chicken Rice & Broccoli Bowl",
              "720 kcal • 52g Protein • \$2.50 cost",
              "200g pan-seared chicken breast, 1.5 cups jasmine rice, 1 cup steamed broccoli. Drizzle with low-calorie teriyaki sauce.",
              Icons.lunch_dining,
            ),
            _buildMealCard(
              context,
              "Dinner",
              "Canned Tuna & Avocado Pasta Salad",
              "680 kcal • 45g Protein • \$2.10 cost",
              "100g high-protein chickpea pasta, 1 can light tuna in water, 1/2 avocado, cherry tomatoes. Simple cold prep, high fiber, zero cooking required.",
              Icons.dinner_dining,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetCard(
    BuildContext context,
    String label,
    String value,
    String subtitle,
    Color color,
    double progress,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white.withOpacity(0.08),
            color: color,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      ),
    );
  }

  Widget _buildMealCard(
    BuildContext context,
    String mealTime,
    String title,
    String macros,
    String recipe,
    IconData icon,
  ) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.neonLime, size: 20),
              const SizedBox(width: 8),
              Text(
                mealTime.toUpperCase(),
                style: const TextStyle(
                  color: AppTheme.neonLime,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              const Icon(Icons.arrow_forward_ios, size: 12, color: AppTheme.textSecondary),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            macros,
            style: const TextStyle(
              color: AppTheme.neonCyan,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            recipe,
            style: textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
