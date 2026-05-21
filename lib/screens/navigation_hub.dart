import 'package:flutter/material.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import 'form_check/form_check_screen.dart';
import 'history/history_screen.dart';
import 'nutrition/nutrition_screen.dart';
import 'onboarding/onboarding_flow.dart';
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
  int _currentIndex = 0;

  static const _tabs = <_Tab>[
    _Tab('Form Check', Icons.fitness_center_rounded),
    _Tab('Gym Scan', Icons.center_focus_strong_rounded),
    _Tab('Nutrition', Icons.restaurant_menu_rounded),
    _Tab('Program', Icons.auto_awesome_rounded),
    _Tab('History', Icons.history_rounded),
  ];

  final List<Widget> _screens = const [
    FormCheckScreen(),
    WayfindingScreen(),
    NutritionScreen(),
    ProgramScreen(),
    HistoryScreen(),
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: _tabs
            .map((t) => BottomNavigationBarItem(
                  icon: Icon(t.icon),
                  label: t.label,
                ))
            .toList(),
      ),
    );
  }
}

class _Tab {
  final String label;
  final IconData icon;
  const _Tab(this.label, this.icon);
}
