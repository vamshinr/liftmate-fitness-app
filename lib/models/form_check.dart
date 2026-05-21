class FormCheckResult {
  final String lift;
  final int confidence; // 0-100; below threshold → suggest human review
  final int formScore; // 0-100
  final String keyCorrection;
  final String whatWentWell;
  final List<String> watchOuts;
  final bool safetyFlag;
  final String safetyReason;
  final DateTime timestamp;

  const FormCheckResult({
    required this.lift,
    required this.confidence,
    required this.formScore,
    required this.keyCorrection,
    required this.whatWentWell,
    required this.watchOuts,
    required this.safetyFlag,
    required this.safetyReason,
    required this.timestamp,
  });

  bool get lowConfidence => confidence < 60;

  Map<String, dynamic> toJson() => {
        'lift': lift,
        'confidence': confidence,
        'formScore': formScore,
        'keyCorrection': keyCorrection,
        'whatWentWell': whatWentWell,
        'watchOuts': watchOuts,
        'safetyFlag': safetyFlag,
        'safetyReason': safetyReason,
        'timestamp': timestamp.toIso8601String(),
      };

  factory FormCheckResult.fromJson(Map<String, dynamic> j) => FormCheckResult(
        lift: j['lift'] as String? ?? '',
        confidence: (j['confidence'] as num?)?.toInt() ?? 0,
        formScore: (j['formScore'] as num?)?.toInt() ?? 0,
        keyCorrection: j['keyCorrection'] as String? ?? '',
        whatWentWell: j['whatWentWell'] as String? ?? '',
        watchOuts: (j['watchOuts'] as List?)?.cast<String>() ?? const [],
        safetyFlag: j['safetyFlag'] as bool? ?? false,
        safetyReason: j['safetyReason'] as String? ?? '',
        timestamp: DateTime.tryParse(j['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );
}

class NutritionPlan {
  final int calorieTarget;
  final int proteinGrams;
  final List<MealSuggestion> meals;
  final String shoppingNote;
  final DateTime generatedAt;

  const NutritionPlan({
    required this.calorieTarget,
    required this.proteinGrams,
    required this.meals,
    required this.shoppingNote,
    required this.generatedAt,
  });

  Map<String, dynamic> toJson() => {
        'calorieTarget': calorieTarget,
        'proteinGrams': proteinGrams,
        'meals': meals.map((m) => m.toJson()).toList(),
        'shoppingNote': shoppingNote,
        'generatedAt': generatedAt.toIso8601String(),
      };

  factory NutritionPlan.fromJson(Map<String, dynamic> j) => NutritionPlan(
        calorieTarget: (j['calorieTarget'] as num?)?.toInt() ?? 0,
        proteinGrams: (j['proteinGrams'] as num?)?.toInt() ?? 0,
        meals: (j['meals'] as List?)
                ?.map((e) => MealSuggestion.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        shoppingNote: j['shoppingNote'] as String? ?? '',
        generatedAt: DateTime.tryParse(j['generatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class MealSuggestion {
  final String slot; // Breakfast/Lunch/Dinner/Snack
  final String name;
  final int calories;
  final int proteinGrams;
  final String description;
  final String cost; // e.g., "$3.50"

  const MealSuggestion({
    required this.slot,
    required this.name,
    required this.calories,
    required this.proteinGrams,
    required this.description,
    required this.cost,
  });

  Map<String, dynamic> toJson() => {
        'slot': slot,
        'name': name,
        'calories': calories,
        'proteinGrams': proteinGrams,
        'description': description,
        'cost': cost,
      };

  factory MealSuggestion.fromJson(Map<String, dynamic> j) => MealSuggestion(
        slot: j['slot'] as String? ?? '',
        name: j['name'] as String? ?? '',
        calories: (j['calories'] as num?)?.toInt() ?? 0,
        proteinGrams: (j['proteinGrams'] as num?)?.toInt() ?? 0,
        description: j['description'] as String? ?? '',
        cost: j['cost'] as String? ?? '',
      );
}

class LoggedMeal {
  final String description;
  final int approxCalories;
  final int approxProteinGrams;
  final DateTime loggedAt;

  const LoggedMeal({
    required this.description,
    required this.approxCalories,
    required this.approxProteinGrams,
    required this.loggedAt,
  });

  Map<String, dynamic> toJson() => {
        'description': description,
        'approxCalories': approxCalories,
        'approxProteinGrams': approxProteinGrams,
        'loggedAt': loggedAt.toIso8601String(),
      };

  factory LoggedMeal.fromJson(Map<String, dynamic> j) => LoggedMeal(
        description: j['description'] as String? ?? '',
        approxCalories: (j['approxCalories'] as num?)?.toInt() ?? 0,
        approxProteinGrams: (j['approxProteinGrams'] as num?)?.toInt() ?? 0,
        loggedAt:
            DateTime.tryParse(j['loggedAt'] as String? ?? '') ?? DateTime.now(),
      );
}
