import 'package:flutter/material.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import 'coach_chat/coach_chat_screen.dart';
import 'form_check/form_check_screen.dart';
import 'onboarding/onboarding_flow.dart';
import 'profile/profile_screen.dart';
import 'program/program_screen.dart';
import 'wayfinding/wayfinding_screen.dart';

class NavigationHub extends StatefulWidget {
  const NavigationHub({super.key});

  @override
  State<NavigationHub> createState() => _NavigationHubState();
}

class _NavigationHubState extends State<NavigationHub> {
  bool _loading = true;
  bool _onboarded = false;
  int _currentIndex = 2; // start on Coach (center)

  static const _tabs = <_Tab>[
    _Tab('Form', Icons.fitness_center_rounded),
    _Tab('Scan', Icons.qr_code_scanner_rounded),
    _Tab('Coach', Icons.auto_awesome_rounded, center: true),
    _Tab('Plan', Icons.event_note_rounded),
    _Tab('You', Icons.person_rounded),
  ];

  final List<Widget> _screens = const [
    FormCheckScreen(),
    WayfindingScreen(),
    CoachChatScreen(),
    ProgramScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final profile = await ProfileService.load();
    if (!mounted) return;
    setState(() {
      _onboarded = profile.onboardingComplete;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.darkBackground,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.neonLime),
        ),
      );
    }
    if (!_onboarded) {
      return OnboardingFlow(
        onComplete: () => setState(() => _onboarded = true),
      );
    }
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _ModernNavBar(
        tabs: _tabs,
        currentIndex: _currentIndex,
        onChange: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

class _Tab {
  final String label;
  final IconData icon;
  final bool center;
  const _Tab(this.label, this.icon, {this.center = false});
}

class _ModernNavBar extends StatelessWidget {
  final List<_Tab> tabs;
  final int currentIndex;
  final ValueChanged<int> onChange;
  const _ModernNavBar({
    required this.tabs,
    required this.currentIndex,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, bottomInset > 0 ? bottomInset : 12),
      decoration: const BoxDecoration(
        color: AppTheme.darkBackground,
        border: Border(top: BorderSide(color: AppTheme.hairline)),
      ),
      child: SizedBox(
        height: 60,
        child: Row(
          children: List.generate(tabs.length, (i) {
            final t = tabs[i];
            final selected = i == currentIndex;
            return Expanded(
              child: _NavItem(
                tab: t,
                selected: selected,
                onTap: () => onChange(i),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (tab.center) {
      return _CenterAction(
        icon: tab.icon,
        label: tab.label,
        selected: selected,
        onTap: onTap,
      );
    }

    final color = selected ? AppTheme.neonLime : AppTheme.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(tab.icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              tab.label,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CenterAction({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: 64,
          height: 56,
          decoration: BoxDecoration(
            gradient: selected ? AppTheme.limeGradient : null,
            color: selected ? null : AppTheme.cardBgElevated,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AppTheme.neonLime
                  : AppTheme.neonLime.withValues(alpha: 0.4),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppTheme.neonLime.withValues(alpha: 0.45),
                      blurRadius: 18,
                      spreadRadius: -4,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            color:
                selected ? AppTheme.darkBackground : AppTheme.neonLime,
            size: 26,
          ),
        ),
      ),
    );
  }
}
