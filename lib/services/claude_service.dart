import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/form_check.dart';
import '../models/user_profile.dart';

class ClaudeMessage {
  final String role;
  final String content;
  const ClaudeMessage({required this.role, required this.content});
  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class MachineInfo {
  final String name;
  final String muscles;
  final List<String> steps;
  final String startingWeight;
  const MachineInfo({
    required this.name,
    required this.muscles,
    required this.steps,
    required this.startingWeight,
  });
}

class ClaudeService {
  static const _apiUrl = 'https://api.anthropic.com/v1/messages';

  static Map<String, String> get _headers => {
        'x-api-key': claudeApiKey,
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
      throw Exception('Claude API ${response.statusCode}: ${response.body}');
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

  // ---- Machine identification (gym wayfinding) ----
  static Future<MachineInfo> identifyMachine(Uint8List imageBytes) async {
    final data = await _request({
      'model': claudeModel,
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
    "Step 4 — safety tip / common mistake"
  ],
  "startingWeight": "Recommended starting resistance for a complete beginner"
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
    );
  }

  // ---- Form analysis (3 stills: top → bottom → top) ----
  static Future<FormCheckResult> analyzeForm({
    required String lift,
    required List<Uint8List> frames,
    required List<String> framePositions,
    String? userReportedPain,
    UserProfile? profile,
  }) async {
    assert(frames.length == framePositions.length);

    final positionLabels = List.generate(
      frames.length,
      (i) => 'Frame ${i + 1}: ${framePositions[i]}',
    ).join(', ');

    final injuryContext = (profile?.injuries.isNotEmpty ?? false)
        ? 'User reports prior injuries: ${profile!.injuries.join(", ")}. '
        : '';
    final painContext = (userReportedPain ?? '').trim().isNotEmpty
        ? 'User reports CURRENT pain/discomfort: "$userReportedPain". '
        : '';

    final prompt = '''You are a certified strength coach reviewing a beginner's $lift form.
You are looking at ${frames.length} still photos of a single rep, in order: $positionLabels.

${injuryContext}${painContext}
Analyze biomechanics across these still frames:
- Squat / Split Squat / Lunge: depth, knee tracking over toes, neutral spine, brace, hip hinge timing, heel pressure
- Deadlift / RDL: hip hinge vs squat, neutral spine (especially lumbar), bar path, lat engagement, lockout
- Bench / OHP: shoulder packing, bar path, scap retraction, elbow flare, foot pressure, lower-back arch (excess)
- Row / Lat Pulldown: scapular initiation, elbow path, torso angle, lat vs bicep dominance
- Push-up: plank line, scap protraction at top, elbow angle, head/neck position

Be honest about confidence. If the image is blurry, off-angle, poorly lit, or the lifter isn't fully visible, lower confidence accordingly — do NOT guess. The user is a beginner and over-confident wrong advice is worse than saying "let a human review this."

CRITICAL safety triggers (set safetyFlag=true and explain): visibly rounded lower back under load, knee valgus collapse, dropped chest with heavy load, unstable bar path, any sign of acute pain in the photos, or user-reported pain in the wrong place. Never coach around pain — escalate to a human or clinician.

Respond with ONLY valid JSON (no markdown):
{
  "confidence": 0-100,
  "formScore": 0-100,
  "keyCorrection": "ONE single most-important correction in plain language, with a concrete cue (e.g., 'Brace your core hard before descending — imagine bracing for a punch')",
  "whatWentWell": "ONE specific thing they did right",
  "watchOuts": ["1-3 secondary things to watch on next set"],
  "safetyFlag": true | false,
  "safetyReason": "If safetyFlag is true, the specific risk in plain language. Empty string otherwise."
}''';

    final data = await _request({
      'model': claudeModel,
      'max_tokens': 1024,
      'messages': [
        {
          'role': 'user',
          'content': [
            ..._imageBlocks(frames),
            {'type': 'text', 'text': prompt},
          ],
        }
      ],
    });

    final json =
        jsonDecode(_extractJson(_firstText(data))) as Map<String, dynamic>;
    return FormCheckResult(
      lift: lift,
      confidence: (json['confidence'] as num?)?.toInt().clamp(0, 100) ?? 0,
      formScore: (json['formScore'] as num?)?.toInt().clamp(0, 100) ?? 0,
      keyCorrection:
          json['keyCorrection'] as String? ?? 'No specific correction returned.',
      whatWentWell: json['whatWentWell'] as String? ?? '',
      watchOuts:
          (json['watchOuts'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      safetyFlag: json['safetyFlag'] as bool? ?? false,
      safetyReason: json['safetyReason'] as String? ?? '',
      timestamp: DateTime.now(),
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
      'model': claudeModel,
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
      'model': claudeModel,
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

  // ---- Program builder ----
  static Future<Map<String, dynamic>> generateProgram(UserProfile profile) async {
    final injuryNote = profile.injuries.isNotEmpty
        ? 'Injuries to work around: ${profile.injuries.join(", ")}. Avoid loading these patterns; substitute safer variants.'
        : 'No reported injuries.';

    final prompt = '''You are a strength coach. Design a weekly program for:
- Goal: ${profile.goal}
- Experience: ${profile.experience}
- Days/week: ${profile.daysPerWeek}
- Equipment available: ${profile.equipment.isEmpty ? "bodyweight only" : profile.equipment.join(", ")}
$injuryNote

Keep it simple, evidence-based, beginner-friendly. Compound lifts first. Sets x reps in plain language.
Respond with ONLY valid JSON (no markdown):
{
  "name": "Short program name",
  "summary": "1-2 sentence summary of focus & progression",
  "days": [
    {
      "day": "Day 1 — name",
      "focus": "Movement pattern focus",
      "exercises": [
        {"name": "Exercise", "sets": "3", "reps": "8-10", "notes": "One-line cue"}
      ]
    }
  ],
  "progressionNote": "One sentence on how to progress week to week"
}''';

    final data = await _request({
      'model': claudeModel,
      'max_tokens': 2400,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt}
          ],
        }
      ],
    });

    return jsonDecode(_extractJson(_firstText(data))) as Map<String, dynamic>;
  }

  static Future<String> chat(
      List<ClaudeMessage> history, String systemPrompt) async {
    final data = await _request({
      'model': claudeModel,
      'max_tokens': 512,
      'system': systemPrompt,
      'messages': history.map((m) => m.toJson()).toList(),
    });
    return _firstText(data);
  }
}
