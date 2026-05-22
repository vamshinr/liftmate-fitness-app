import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/ai_coach_service.dart';
import '../../services/profile_service.dart';
import '../../theme.dart';
import '../../widgets/trainer_network_card.dart';
import '../trainers/trainer_network_screen.dart';

/// AI Coach chatbot with RAG over Firestore + local profile.
/// Every turn re-fetches a fresh summary of the user's recent activity and
/// prepends it to the system prompt — keeps responses grounded in what
/// the user actually did, not generic gym advice.
class CoachChatScreen extends StatefulWidget {
  const CoachChatScreen({super.key});

  @override
  State<CoachChatScreen> createState() => _CoachChatScreenState();
}

class _CoachChatScreenState extends State<CoachChatScreen> {
  static const _historyKey = 'coach_chat_history_v1';

  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<_DisplayMsg> _display = [];
  final List<AIMessage> _api = [];

  bool _sending = false;
  bool _loadingThread = true;

  static const _suggestions = <String>[
    'How is my form trending?',
    'What should I focus on this week?',
    'Suggest a quick recovery day',
    'Where am I behind on protein?',
    'What\'s next in my program?',
  ];

  @override
  void initState() {
    super.initState();
    _loadThread();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadThread() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        for (final m in list) {
          final role = m['role'] as String? ?? 'assistant';
          final text = m['text'] as String? ?? '';
          _display.add(_DisplayMsg(role: role, text: text));
          _api.add(AIMessage(role: role, content: text));
        }
      } catch (_) {}
    }
    if (_display.isEmpty) {
      final greeting = _initialGreeting();
      _display.add(_DisplayMsg(role: 'assistant', text: greeting));
      _api.add(AIMessage(role: 'assistant', content: greeting));
    }
    if (mounted) setState(() => _loadingThread = false);
    _scrollToBottom();
  }

  String _initialGreeting() {
    final p = ProfileService.current;
    final name = p.goal.isEmpty ? 'training' : p.goal.toLowerCase();
    return "Hey — I'm your AI coach. I've got your $name profile and recent history on tap, so ask me anything: what's next, why a lift felt off, what to eat today, when to back off.";
  }

  Future<void> _persistThread() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(
          _display.map((m) => {'role': m.role, 'text': m.text}).toList()),
    );
  }

  Future<String> _buildRagContext() async {
    final p = ProfileService.current;
    final buf = StringBuffer();
    buf.writeln('USER PROFILE:');
    buf.writeln('- Goal: ${p.goal}');
    buf.writeln('- Experience: ${p.experience}');
    buf.writeln('- Days/week: ${p.daysPerWeek}');
    if (p.bodyweightKg != null) {
      buf.writeln('- Bodyweight: ${p.bodyweightKg} kg');
    }
    if (p.injuries.isNotEmpty) {
      buf.writeln('- Injuries: ${p.injuries.join(', ')}');
    }
    if (p.equipment.isNotEmpty) {
      buf.writeln('- Equipment: ${p.equipment.join(', ')}');
    }
    buf.writeln('- Diet: ${p.dietaryPreference}');
    final cals = p.estimatedDailyCalories();
    if (cals != null) {
      buf.writeln(
          '- Targets: ${cals} kcal / ${p.proteinTargetGrams() ?? 0}g protein/day');
    }

    try {
      final fs = FirebaseFirestore.instance;
      final fc = await fs
          .collection('form_checks')
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();
      if (fc.docs.isNotEmpty) {
        buf.writeln('\nRECENT FORM CHECKS (newest first):');
        for (final d in fc.docs) {
          final data = d.data();
          final lift = data['lift'] ?? '?';
          final score = data['formScore'] ?? '?';
          final key = data['keyCorrection'] ?? '';
          final safety = data['safetyFlag'] == true ? ' [SAFETY FLAG]' : '';
          final ts = data['createdAt'];
          String when = '';
          if (ts is Timestamp) {
            when = DateFormat('MMM d').format(ts.toDate());
          }
          buf.writeln(
              '- $when $lift: score $score$safety — ${_truncate(key, 120)}');
        }
      }

      final ml = await fs
          .collection('meal_logs')
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();
      if (ml.docs.isNotEmpty) {
        buf.writeln('\nRECENT MEAL LOGS:');
        for (final d in ml.docs) {
          final data = d.data();
          final desc = data['description'] ?? '?';
          final cals = data['approxCalories'] ?? '?';
          final pg = data['approxProteinGrams'] ?? '?';
          buf.writeln('- $desc — ${cals} kcal, ${pg}g protein');
        }
      }

      final prog = await fs
          .collection('programs')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();
      if (prog.docs.isNotEmpty) {
        final data = prog.docs.first.data();
        final title = data['programTitle'] ?? 'Current program';
        final goal = data['goal'] ?? '';
        buf.writeln('\nCURRENT PROGRAM: $title ($goal)');
      }
    } catch (_) {
      // offline — no history available; respond based on profile alone
    }

    return buf.toString();
  }

  String _truncate(String s, int n) =>
      s.length > n ? '${s.substring(0, n - 1).trim()}…' : s;

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String input) async {
    final text = input.trim();
    if (text.isEmpty || _sending) return;
    _textCtrl.clear();
    setState(() {
      _display.add(_DisplayMsg(role: 'user', text: text));
      _api.add(AIMessage(role: 'user', content: text));
      _sending = true;
    });
    _scrollToBottom();

    try {
      final ragContext = await _buildRagContext();
      final p = ProfileService.current;
      final isBeginner = p.experience.toLowerCase().contains('begin') ||
          p.experience.toLowerCase().contains('brand new');
      final warmupRule = isBeginner
          ? 'WARM-UP DIRECTIVE (this user is a beginner): if your answer relates to a training session, lift, soreness, or a niggle, mention warming up first — 2 min light cardio → dynamic mobility → 2 ramp-up sets. Never recommend going straight into working sets.'
          : 'WARM-UP DIRECTIVE: if you recommend a specific lift or session, remind the user to warm up properly (light cardio + dynamic mobility + ramp-up sets) — especially after rest days.';

      final system =
          'You are LiftMate AI, the user\'s on-call gym, form, and nutrition coach. '
          'Speak in plain English, max 4 short sentences unless they ask for detail. '
          'Be specific to THEIR data below. Never invent activity they didn\'t do; if you don\'t see it, say so and ask. '
          'If they report pain or red-flag symptoms (chest pain, dizziness, "MD said no"), tell them to stop and see a clinician — never coach around it.\n\n'
          '$warmupRule\n\n'
          '$ragContext';

      final reply = await AICoachService.chat(_api, system);
      if (!mounted) return;
      setState(() {
        _display.add(_DisplayMsg(role: 'assistant', text: reply));
        _api.add(AIMessage(role: 'assistant', content: reply));
        _sending = false;
      });
      _scrollToBottom();
      _persistThread();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _display.add(_DisplayMsg(
            role: 'assistant',
            text:
                "I couldn't reach the coach service — check connection and try again."));
        _sending = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _clearThread() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear conversation?'),
        content: const Text(
            'The whole chat history is wiped. The AI keeps your training history (form checks, meals) — only the chat thread resets.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    setState(() {
      _display.clear();
      _api.clear();
      final g = _initialGreeting();
      _display.add(_DisplayMsg(role: 'assistant', text: g));
      _api.add(AIMessage(role: 'assistant', content: g));
    });
  }

  bool get _keyboardOpen => MediaQuery.of(context).viewInsets.bottom > 0;

  void _dismissKeyboard() => FocusScope.of(context).unfocus();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: AppTheme.limeGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  size: 16, color: AppTheme.darkBackground),
            ),
            const SizedBox(width: 10),
            const Text('AI Coach'),
          ],
        ),
        actions: [
          if (_keyboardOpen)
            IconButton(
              tooltip: 'Dismiss keyboard',
              icon: const Icon(Icons.keyboard_hide_rounded),
              onPressed: _dismissKeyboard,
            ),
          IconButton(
            tooltip: 'Talk to a human coach',
            icon: const Icon(Icons.support_agent_rounded,
                color: AppTheme.neonCyan),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const TrainerNetworkScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Clear chat',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _clearThread,
          ),
        ],
      ),
      // Tap anywhere outside the input to dismiss the keyboard.
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dismissKeyboard,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _loadingThread
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: AppTheme.neonLime),
                      )
                    : _ChatList(
                        scrollCtrl: _scrollCtrl,
                        messages: _display,
                        pending: _sending,
                      ),
              ),
              if (_display.length <= 1) ...[
                _TrainerStripBanner(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const TrainerNetworkScreen()),
                  ),
                ),
                _SuggestionStrip(
                  suggestions: _suggestions,
                  onPick: _send,
                ),
              ],
              _ChatInput(
                controller: _textCtrl,
                sending: _sending,
                onSend: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisplayMsg {
  final String role;
  final String text;
  const _DisplayMsg({required this.role, required this.text});
}

class _ChatList extends StatelessWidget {
  final ScrollController scrollCtrl;
  final List<_DisplayMsg> messages;
  final bool pending;
  const _ChatList({
    required this.scrollCtrl,
    required this.messages,
    required this.pending,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      // Scrolling drops the keyboard — natural chat-app behavior.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: messages.length + (pending ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= messages.length) {
          return const _TypingBubble();
        }
        return _Bubble(message: messages[i]);
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  final _DisplayMsg message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: isUser
              ? AppTheme.neonLime.withValues(alpha: 0.14)
              : AppTheme.cardBg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          border: Border.all(
            color: isUser
                ? AppTheme.neonLime.withValues(alpha: 0.4)
                : AppTheme.hairline,
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14.5,
            height: 1.5,
            fontWeight: isUser ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.hairline),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.neonLime),
            ),
            SizedBox(width: 10),
            Text('Thinking…',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _SuggestionStrip extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String> onPick;
  const _SuggestionStrip({required this.suggestions, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: suggestions.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final s = suggestions[i];
            return InkWell(
              onTap: () => onPick(s),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: AppTheme.neonLime.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bolt_rounded,
                        size: 13, color: AppTheme.neonLime),
                    const SizedBox(width: 6),
                    Text(s,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ChatInput extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final ValueChanged<String> onSend;
  const _ChatInput({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        MediaQuery.of(context).viewInsets.bottom + 10,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.darkBackground,
        border: Border(top: BorderSide(color: AppTheme.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
              decoration: const InputDecoration(
                hintText: 'Ask anything about your training, form, nutrition…',
                isDense: true,
              ),
              onSubmitted: onSend,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: sending ? null : () => onSend(controller.text),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: sending
                    ? null
                    : AppTheme.limeGradient,
                color: sending ? AppTheme.cardBgElevated : null,
                shape: BoxShape.circle,
              ),
              child: sending
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.textSecondary),
                    )
                  : const Icon(Icons.send_rounded,
                      color: AppTheme.darkBackground, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact pre-conversation banner pointing at the trainer marketplace.
/// Shown on the empty/initial chat so users discover the human-coach option
/// before they ever ask the AI a question.
class _TrainerStripBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _TrainerStripBanner({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.neonCyan.withValues(alpha: 0.14),
                  AppTheme.neonLime.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(
                  color: AppTheme.neonCyan.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppTheme.neonCyan.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.support_agent_rounded,
                      color: AppTheme.neonCyan, size: 16),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Talk to a human coach',
                          style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                      Text('Vetted, \$9 per review, <24h reply',
                          style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11.5)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded,
                    color: AppTheme.neonCyan, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Kept exported in case external surfaces want the bigger card layout.
class CoachTrainerFallback extends StatelessWidget {
  final VoidCallback onTap;
  const CoachTrainerFallback({super.key, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: TrainerNetworkCard(
        compact: true,
        ctaLabel: 'Request a human review · \$9',
        onTap: onTap,
      ),
    );
  }
}
