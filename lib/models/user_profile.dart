class UserProfile {
  final String goal;
  final String experience;
  final int? ageYears;
  final double? bodyweightKg;
  final double? heightCm;
  final String sex;
  final int daysPerWeek;
  final List<String> equipment;
  final List<String> injuries;
  final List<String> medicalConditions;
  final bool clearedForExercise;
  final bool needsGymOrientation;
  final bool onboardingComplete;
  final String budgetPerDay;
  final String dietaryPreference;

  const UserProfile({
    this.goal = 'General Fitness',
    this.experience = 'Beginner',
    this.ageYears,
    this.bodyweightKg,
    this.heightCm,
    this.sex = 'Prefer not to say',
    this.daysPerWeek = 3,
    this.equipment = const [],
    this.injuries = const [],
    this.medicalConditions = const [],
    this.clearedForExercise = false,
    this.needsGymOrientation = true,
    this.onboardingComplete = false,
    this.budgetPerDay = 'Moderate',
    this.dietaryPreference = 'No restrictions',
  });

  UserProfile copyWith({
    String? goal,
    String? experience,
    int? ageYears,
    double? bodyweightKg,
    double? heightCm,
    String? sex,
    int? daysPerWeek,
    List<String>? equipment,
    List<String>? injuries,
    List<String>? medicalConditions,
    bool? clearedForExercise,
    bool? needsGymOrientation,
    bool? onboardingComplete,
    String? budgetPerDay,
    String? dietaryPreference,
  }) =>
      UserProfile(
        goal: goal ?? this.goal,
        experience: experience ?? this.experience,
        ageYears: ageYears ?? this.ageYears,
        bodyweightKg: bodyweightKg ?? this.bodyweightKg,
        heightCm: heightCm ?? this.heightCm,
        sex: sex ?? this.sex,
        daysPerWeek: daysPerWeek ?? this.daysPerWeek,
        equipment: equipment ?? this.equipment,
        injuries: injuries ?? this.injuries,
        medicalConditions: medicalConditions ?? this.medicalConditions,
        clearedForExercise: clearedForExercise ?? this.clearedForExercise,
        needsGymOrientation: needsGymOrientation ?? this.needsGymOrientation,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
        budgetPerDay: budgetPerDay ?? this.budgetPerDay,
        dietaryPreference: dietaryPreference ?? this.dietaryPreference,
      );

  Map<String, dynamic> toJson() => {
        'goal': goal,
        'experience': experience,
        'ageYears': ageYears,
        'bodyweightKg': bodyweightKg,
        'heightCm': heightCm,
        'sex': sex,
        'daysPerWeek': daysPerWeek,
        'equipment': equipment,
        'injuries': injuries,
        'medicalConditions': medicalConditions,
        'clearedForExercise': clearedForExercise,
        'needsGymOrientation': needsGymOrientation,
        'onboardingComplete': onboardingComplete,
        'budgetPerDay': budgetPerDay,
        'dietaryPreference': dietaryPreference,
      };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        goal: j['goal'] as String? ?? 'General Fitness',
        experience: j['experience'] as String? ?? 'Beginner',
        ageYears: (j['ageYears'] as num?)?.toInt(),
        bodyweightKg: (j['bodyweightKg'] as num?)?.toDouble(),
        heightCm: (j['heightCm'] as num?)?.toDouble(),
        sex: j['sex'] as String? ?? 'Prefer not to say',
        daysPerWeek: (j['daysPerWeek'] as num?)?.toInt() ?? 3,
        equipment: (j['equipment'] as List?)?.cast<String>() ?? const [],
        injuries: (j['injuries'] as List?)?.cast<String>() ?? const [],
        medicalConditions:
            (j['medicalConditions'] as List?)?.cast<String>() ?? const [],
        clearedForExercise: j['clearedForExercise'] as bool? ?? false,
        needsGymOrientation: j['needsGymOrientation'] as bool? ?? true,
        onboardingComplete: j['onboardingComplete'] as bool? ?? false,
        budgetPerDay: j['budgetPerDay'] as String? ?? 'Moderate',
        dietaryPreference: j['dietaryPreference'] as String? ?? 'No restrictions',
      );

  /// Mifflin-St Jeor maintenance calories with goal adjustment.
  /// Returns null if essential inputs are missing.
  int? estimatedDailyCalories() {
    if (bodyweightKg == null || heightCm == null || ageYears == null) return null;
    final w = bodyweightKg!;
    final h = heightCm!;
    final a = ageYears!;
    final s = sex == 'Male' ? 5 : (sex == 'Female' ? -161 : -78);
    final bmr = (10 * w) + (6.25 * h) - (5 * a) + s;
    final activity = 1.4 + (daysPerWeek * 0.05);
    final maintenance = bmr * activity;
    final adjusted = switch (goal) {
      'Fat Loss' => maintenance - 400,
      'Muscle Building' => maintenance + 250,
      'Strength' => maintenance + 150,
      _ => maintenance,
    };
    return adjusted.round();
  }

  /// Default 1.6 g/kg bodyweight; bumped for muscle/strength goals.
  int? proteinTargetGrams() {
    if (bodyweightKg == null) return null;
    final perKg = switch (goal) {
      'Muscle Building' => 2.0,
      'Strength' => 1.9,
      'Fat Loss' => 2.0,
      _ => 1.6,
    };
    return (bodyweightKg! * perKg).round();
  }
}
