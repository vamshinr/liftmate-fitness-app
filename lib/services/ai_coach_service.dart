import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/form_check.dart';
import '../models/pose_data.dart';
import '../models/user_profile.dart';

class AIMessage {
  final String role;
  final String content;
  const AIMessage({required this.role, required this.content});
  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class MachineInfo {
  final String name;
  final String muscles;
  final List<String> steps;
  final String startingWeight;
  final String demoQuery;
  final List<String> commonMistakes;
  const MachineInfo({
    required this.name,
    required this.muscles,
    required this.steps,
    required this.startingWeight,
    this.demoQuery = '',
    this.commonMistakes = const [],
  });
}

class AICoachService {
  static const _apiUrl = 'https://api.anthropic.com/v1/messages';

  static Map<String, String> get _headers => {
        'x-api-key': aiCoachApiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      };

  static List<Map<String, dynamic>> _imageBlocks(List<Uint8List> images) =>
      images
          .map((b) => {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': 'image/jpeg',
                  'data': base64Encode(b),
                },
              })
          .toList();

  static Future<Map<String, dynamic>> _request(Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse(_apiUrl),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('AI service ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static String _firstText(Map<String, dynamic> data) =>
      (data['content'] as List).first['text'] as String;

  static String _extractJson(String text) {
    final codeBlock = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(text);
    if (codeBlock != null) return codeBlock.group(1)!;
    final jsonBlock = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (jsonBlock != null) return jsonBlock.group(0)!;
    return text;
  }

  static List<String> _extractList(String text) {
    final match = RegExp(r'\[.*?\]', dotAll: true).firstMatch(text);
    if (match == null) return const [];
    try {
      return (jsonDecode(match.group(0)!) as List).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  // ---- Machine identification (gym wayfinding) ----
  static Future<MachineInfo> identifyMachine(Uint8List imageBytes) async {
    final data = await _request({
      'model': aiPrimaryModel,
      'max_tokens': 1024,
      'messages': [
        {
          'role': 'user',
          'content': [
            ..._imageBlocks([imageBytes]),
            {
              'type': 'text',
              'text':
                  '''You are an expert gym trainer helping a complete beginner. Identify the gym machine or equipment in this image.
Respond with ONLY valid JSON — no markdown, no explanation:
{
  "name": "Exact machine name",
  "muscles": "Primary muscles worked",
  "steps": [
    "Step 1 — specific beginner setup",
    "Step 2 — specific beginner setup",
    "Step 3 — execution cue",
    "Step 4 — safety tip"
  ],
  "startingWeight": "Recommended starting resistance for a complete beginner",
  "demoQuery": "A 3-6 word phrase a beginner could YouTube-search to see this exercise demoed properly, e.g. 'lat pulldown proper form beginner'",
  "commonMistakes": ["1-3 short common-mistake one-liners specific to THIS machine"]
}
If this is not gym equipment, use name "This Area" and give helpful gym navigation guidance in the steps.''',
            },
          ],
        }
      ],
    });

    final json =
        jsonDecode(_extractJson(_firstText(data))) as Map<String, dynamic>;
    return MachineInfo(
      name: json['name'] as String? ?? 'Gym Machine',
      muscles: json['muscles'] as String? ?? 'Various muscles',
      steps:
          (json['steps'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      startingWeight: json['startingWeight'] as String? ??
          'Start light and increase gradually',
      demoQuery: json['demoQuery'] as String? ?? '',
      commonMistakes:
          (json['commonMistakes'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
    );
  }

  // ---- Equipment scan (for program builder) ----
  static Future<List<String>> identifyEquipmentFromPhoto(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
  }) async {
    final data = await _request({
      'model': aiPrimaryModel,
      'max_tokens': 300,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': mimeType,
                'data': base64Encode(imageBytes),
              },
            },
            {
              'type': 'text',
              'text':
                  'List the gym/fitness equipment visible in this image. '
                  'Return ONLY a JSON array of short names like ["Barbell","Bench","Cable Machine"]. '
                  'No other text.',
            },
          ],
        }
      ],
    });
    return _extractList(_firstText(data));
  }

  // ---- Form analysis (text-only synthesis over structured biomech) ----
  /// Takes the on-device biomech rubric + quality + history + context and
  /// asks the coach AI to synthesize ONE coaching priority, drills, and
  /// confidence. No images are sent — pose detection and rubric scoring
  /// happen locally, which keeps this call cheap and grounded in objective
  /// measurements.
  static Future<FormCheckResult> analyzeForm({
    required String lift,
    required BiomechSummary biomech,
    required QualityReport quality,
    List<FormCheckResult> recentHistory = const [],
    String? userReportedPain,
    UserProfile? profile,
  }) async {
    final faultsJson = biomech.faults
        .map((f) => {
              'name': f.name,
              'score': f.score,
              'pass': f.pass,
              'evidence': f.evidence,
            })
        .toList();

    final metricsJson = biomech.metrics.map(
      (k, v) => MapEntry(k, double.parse(v.toStringAsFixed(3))),
    );

    final qualityJson = {
      'blur': quality.blurScore,
      'lighting': quality.brightnessScore,
      'framing': quality.framingScore,
      'angle': quality.angleScore,
      'subjectVisibility': quality.subjectVisibilityScore,
      'issues': quality.issues,
    };

    final historyJson = recentHistory
        .take(3)
        .map((r) => {
              'when': r.timestamp.toIso8601String(),
              'formScore': r.formScore,
              'priorCorrection': r.keyCorrection,
            })
        .toList();

    final injuryContext = (profile?.injuries.isNotEmpty ?? false)
        ? 'Prior injuries to work around: ${profile!.injuries.join(", ")}.'
        : 'No reported prior injuries.';
    final painContext = (userReportedPain ?? '').trim().isNotEmpty
        ? 'CURRENT pain/discomfort user reported BEFORE the set: "$userReportedPain"'
        : 'No current pain reported by user.';

    final experience = profile?.experience ?? 'Beginner';

    final prompt = '''You are a certified strength coach synthesizing a $lift form check for a $experience.

The analysis below was computed locally from on-device pose detection — these are objective measurements, not your guesses. Trust the numbers and reason from them.

LIFT: $lift
SIDE USED FOR ANALYSIS: ${biomech.sideUsed}
$injuryContext
$painContext

PER-FAULT RUBRIC (each scored 0–100 from pose geometry; lower = worse):
${jsonEncode(faultsJson)}

RAW METRICS (degrees / normalized to torso height):
${jsonEncode(metricsJson)}

IMAGE QUALITY (0–100):
${jsonEncode(qualityJson)}

RECENT HISTORY for THIS lift (most recent first):
${historyJson.isEmpty ? '[none — first form check for this lift]' : jsonEncode(historyJson)}

Your job:
1. Pick the SINGLE most-impactful correction to address NOW. Anchor it to the lowest-scoring fault, unless safety dictates otherwise.
2. If history shows the same fault recurring, acknowledge it ("you're still working on...") and shift to a fresh angle or drill.
3. Write coaching in plain language. The user is a beginner — concrete cues (e.g. "imagine bracing for a punch") beat anatomical jargon.
4. Prescribe 1–2 SHORT corrective drills they can do as accessory work next session. Each: name, 1-sentence how-to, brief dose ("3×8" or "2 min daily").
5. Compute an overall confidence breakdown FROM the image-quality scores above; do NOT invent. Use those four numbers directly.
6. Form score: weighted average of the rubric, then anchor to: 90+ = clean, 70–89 = solid with one fix, 50–69 = real fault, <50 = serious fault.
7. SAFETY: set safetyFlag=true ONLY if (a) user reported pain in the line of fire, OR (b) a fault score is below 30 AND the fault is one of: neutral_spine, plank_line, depth (under heavy load), bar_path drift on bench/OHP. Never coach around pain — escalate.

Respond with ONLY valid JSON (no markdown, no commentary):
{
  "confidence": 0-100,
  "formScore": 0-100,
  "keyCorrection": "One paragraph, plain language, the single most-important correction with a concrete cue.",
  "coachingCue": "ONE short imperative sentence the user can repeat in their head on the next set.",
  "whatWentWell": "ONE specific positive observation drawn from the rubric.",
  "watchOuts": ["1-3 secondary things to keep an eye on next set"],
  "safetyFlag": true | false,
  "safetyReason": "If safetyFlag is true, the specific risk. Empty string otherwise.",
  "drills": [
    {"name": "Drill name", "howTo": "1-sentence instruction", "dose": "e.g. 3×8 or 2 min"}
  ],
  "confidenceBreakdown": {
    "visibility": 0-100,
    "angle": 0-100,
    "lighting": 0-100,
    "framing": 0-100
  }
}''';

    final data = await _request({
      'model': aiAnalysisModel,
      'max_tokens': 1800,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt}
          ],
        }
      ],
    });

    final json =
        jsonDecode(_extractJson(_firstText(data))) as Map<String, dynamic>;

    final drills = (json['drills'] as List?)
            ?.map((e) => CorrectiveDrill.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const <CorrectiveDrill>[];

    ConfidenceBreakdown? breakdown;
    if (json['confidenceBreakdown'] is Map<String, dynamic>) {
      breakdown = ConfidenceBreakdown.fromJson(
          json['confidenceBreakdown'] as Map<String, dynamic>);
    }

    final rubric = biomech.faults
        .map((f) => RubricScore(key: f.key, name: f.name, score: f.score))
        .toList();

    return FormCheckResult(
      lift: lift,
      confidence: (json['confidence'] as num?)?.toInt().clamp(0, 100) ??
          (breakdown?.overall ?? quality.overall),
      formScore: (json['formScore'] as num?)?.toInt().clamp(0, 100) ?? 0,
      keyCorrection:
          json['keyCorrection'] as String? ?? 'No specific correction returned.',
      coachingCue: json['coachingCue'] as String? ?? '',
      whatWentWell: json['whatWentWell'] as String? ?? '',
      watchOuts:
          (json['watchOuts'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      safetyFlag: json['safetyFlag'] as bool? ?? false,
      safetyReason: json['safetyReason'] as String? ?? '',
      timestamp: DateTime.now(),
      drills: drills,
      confidenceBreakdown: breakdown,
      rubric: rubric,
    );
  }

  // ---- Nutrition: today's plan (3 meals + targets) ----
  static Future<NutritionPlan> generateDailyPlan(UserProfile profile) async {
    final calories = profile.estimatedDailyCalories() ?? 2200;
    final protein = profile.proteinTargetGrams() ?? 140;

    final prompt =
        '''You are a registered dietitian helping a beginner who does NOT want to track every gram.
User profile:
- Goal: ${profile.goal}
- Experience: ${profile.experience}
- Days training/week: ${profile.daysPerWeek}
- Daily calorie target: $calories kcal
- Protein target: ${protein}g
- Budget per day: ${profile.budgetPerDay}
- Dietary preference: ${profile.dietaryPreference}

Suggest exactly 3 specific, cheap, easy meal ideas for TODAY that together hit those numbers.
Each meal must be a real, common meal the user can buy or cook quickly. No micronutrient detail. No fancy ingredients.
Avoid suggesting supplements. If dietary preference excludes something, respect it strictly.

Respond with ONLY valid JSON (no markdown):
{
  "meals": [
    {
      "slot": "Breakfast" | "Lunch" | "Dinner" | "Snack",
      "name": "Short meal name",
      "calories": int,
      "proteinGrams": int,
      "description": "1-2 sentence plain-English description of what to eat and how much",
      "cost": "Approx cost like '\$3.50'"
    }
  ],
  "shoppingNote": "ONE practical shopping/prep tip for today (under 30 words)"
}''';

    final data = await _request({
      'model': aiPrimaryModel,
      'max_tokens': 1200,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt}
          ],
        }
      ],
    });

    final json =
        jsonDecode(_extractJson(_firstText(data))) as Map<String, dynamic>;
    final meals = (json['meals'] as List?)
            ?.map((e) => MealSuggestion.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const <MealSuggestion>[];
    return NutritionPlan(
      calorieTarget: calories,
      proteinGrams: protein,
      meals: meals,
      shoppingNote: json['shoppingNote'] as String? ?? '',
      generatedAt: DateTime.now(),
    );
  }

  // ---- Nutrition: log a meal (photo or text) ----
  static Future<LoggedMeal> logMeal({
    Uint8List? photo,
    String? text,
  }) async {
    final content = <Map<String, dynamic>>[
      if (photo != null) ..._imageBlocks([photo]),
      {
        'type': 'text',
        'text':
            '''You are a nutrition coach. Estimate the calories and protein for this meal. Be approximate — "good enough" not obsessive.
${text != null && text.trim().isNotEmpty ? 'User note: "$text"' : ''}

If you can't tell what's in the photo, say so and use 0/0. Never invent specific brands or detailed macros.

Respond with ONLY valid JSON (no markdown):
{
  "description": "Short plain-English description of the meal",
  "approxCalories": int,
  "approxProteinGrams": int
}''',
      },
    ];

    final data = await _request({
      'model': aiPrimaryModel,
      'max_tokens': 400,
      'messages': [
        {'role': 'user', 'content': content}
      ],
    });

    final json =
        jsonDecode(_extractJson(_firstText(data))) as Map<String, dynamic>;
    return LoggedMeal(
      description: json['description'] as String? ?? (text ?? 'Meal'),
      approxCalories: (json['approxCalories'] as num?)?.toInt() ?? 0,
      approxProteinGrams: (json['approxProteinGrams'] as num?)?.toInt() ?? 0,
      loggedAt: DateTime.now(),
    );
  }

  // ---- Program builder (used by program_screen) ----
  static Future<Map<String, dynamic>> generateProgramFromInputs({
    required String goal,
    required String level,
    required int daysPerWeek,
    required List<String> equipment,
    List<String> injuries = const [],
  }) async {
    final equipmentStr =
        equipment.isEmpty ? 'no equipment (bodyweight only)' : equipment.join(', ');
    final injuryLine = injuries.isEmpty
        ? ''
        : 'Work around these injuries (no loaded patterns that aggravate them; substitute safer variants): ${injuries.join(", ")}.\n';

    final beginner = level.toLowerCase().contains('begin');
    final warmupRule = beginner
        ? 'EVERY training day MUST start with a "Warm-up" exercise: '
            '"name":"Warm-up","sets":1,"reps":"5 min","formCue":"2 min easy cardio → dynamic mobility (leg swings, hip openers, arm circles) → 2 ramp-up sets at light weight before working sets. Skip static stretching pre-lift."\n'
        : 'EVERY training day MUST start with a "Warm-up" exercise (1 set, "5 min" reps, brief formCue covering cardio + dynamic mobility + ramp-up sets).\n';

    final prompt =
        'You are an expert strength and conditioning coach. '
        'Create a complete $daysPerWeek-day/week training program.\n'
        'Goal: $goal | Level: $level | Equipment: $equipmentStr\n'
        '$injuryLine'
        '$warmupRule'
        'At least ONE coachingNote MUST emphasize that warming up before every session is non-negotiable for injury prevention.\n'
        'Respond with ONLY valid JSON, no markdown code fences, no extra text:\n'
        '{"programTitle":"...","overview":"1-2 sentences","days":['
        '{"dayNumber":1,"focus":"Upper Body Push","isRestDay":false,"exercises":['
        '{"name":"Warm-up","sets":1,"reps":"5 min","formCue":"..."},'
        '{"name":"Bench Press","sets":4,"reps":"6-8","formCue":"Retract shoulder blades"}]}],'
        '"coachingNotes":["note1","note2","note3"]}\n\n'
        'Include all $daysPerWeek training days (warm-up + 4-6 working exercises each). '
        'Fill the remaining days of a 7-day week as rest days (isRestDay:true, exercises:[]).';

    final data = await _request({
      'model': aiPrimaryModel,
      'max_tokens': 3000,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
    });

    final text = _firstText(data);
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (match == null) return {'_raw': text};
    try {
      return jsonDecode(match.group(0)!) as Map<String, dynamic>;
    } catch (_) {
      return {'_raw': text};
    }
  }

  static Future<Map<String, dynamic>> generateProgram(UserProfile profile) {
    return generateProgramFromInputs(
      goal: profile.goal,
      level: profile.experience,
      daysPerWeek: profile.daysPerWeek,
      equipment: profile.equipment,
      injuries: profile.injuries,
    );
  }

  static Future<String> chat(
      List<AIMessage> history, String systemPrompt) async {
    final data = await _request({
      'model': aiPrimaryModel,
      'max_tokens': 512,
      'system': systemPrompt,
      'messages': history.map((m) => m.toJson()).toList(),
    });
    return _firstText(data);
  }
}
