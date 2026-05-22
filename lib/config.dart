import 'package:flutter_dotenv/flutter_dotenv.dart';

String get aiCoachApiKey =>
    dotenv.env['AI_COACH_API_KEY'] ?? dotenv.env['CLAUDE_API_KEY'] ?? '';

String get aiPrimaryModel =>
    dotenv.env['AI_PRIMARY_MODEL'] ??
    dotenv.env['CLAUDE_MODEL'] ??
    'claude-haiku-4-5-20251001';

String get aiAnalysisModel =>
    dotenv.env['AI_ANALYSIS_MODEL'] ??
    dotenv.env['CLAUDE_ANALYSIS_MODEL'] ??
    'claude-sonnet-4-6';
