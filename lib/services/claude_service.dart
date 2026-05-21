import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config.dart';

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

  static Future<MachineInfo> identifyMachine(Uint8List imageBytes) async {
    final body = jsonEncode({
      'model': claudeModel,
      'max_tokens': 1024,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': 'image/jpeg',
                'data': base64Encode(imageBytes),
              },
            },
            {
              'type': 'text',
              'text': '''You are an expert gym trainer helping a complete beginner. Identify the gym machine or equipment in this image.
Respond with ONLY valid JSON — no markdown, no explanation, just the JSON object:
{
  "name": "Exact machine name",
  "muscles": "Primary muscles worked",
  "steps": [
    "Step 1 — specific beginner setup instruction",
    "Step 2 — specific beginner setup instruction",
    "Step 3 — execution cue",
    "Step 4 — safety tip or common mistake to avoid"
  ],
  "startingWeight": "Recommended starting resistance for a complete beginner"
}
If this is not gym equipment, use name "This Area" and give helpful gym navigation guidance in the steps.''',
            },
          ],
        }
      ],
    });

    final response = await http.post(Uri.parse(_apiUrl), headers: _headers, body: body);

    if (response.statusCode != 200) {
      throw Exception('API error ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final text = (data['content'] as List).first['text'] as String;
    final json = jsonDecode(_extractJson(text)) as Map<String, dynamic>;

    return MachineInfo(
      name: json['name'] as String? ?? 'Gym Machine',
      muscles: json['muscles'] as String? ?? 'Various muscles',
      steps: (json['steps'] as List?)?.map((e) => e.toString()).toList() ?? [],
      startingWeight: json['startingWeight'] as String? ?? 'Start light and increase gradually',
    );
  }

  static Future<String> chat(List<ClaudeMessage> history, String systemPrompt) async {
    final body = jsonEncode({
      'model': claudeModel,
      'max_tokens': 256,
      'system': systemPrompt,
      'messages': history.map((m) => m.toJson()).toList(),
    });

    final response = await http.post(Uri.parse(_apiUrl), headers: _headers, body: body);

    if (response.statusCode != 200) {
      throw Exception('API error ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['content'] as List).first['text'] as String;
  }

  static String _extractJson(String text) {
    final codeBlock = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(text);
    if (codeBlock != null) return codeBlock.group(1)!;
    final jsonBlock = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (jsonBlock != null) return jsonBlock.group(0)!;
    return text;
  }
}
