import 'package:flutter_dotenv/flutter_dotenv.dart';

String get claudeApiKey => dotenv.env['CLAUDE_API_KEY'] ?? '';
String get claudeModel => dotenv.env['CLAUDE_MODEL'] ?? 'claude-haiku-4-5-20251001';
