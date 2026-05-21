import 'package:flutter/material.dart';
import 'workout/workout_screen.dart';
import 'wayfinding/wayfinding_screen.dart';
import 'nutrition/nutrition_screen.dart';
import 'program/program_screen.dart';
import 'history/history_screen.dart';

class NavigationHub extends StatefulWidget {
  const NavigationHub({super.key});

  @override
  State<NavigationHub> createState() => _NavigationHubState();
}

class _NavigationHubState extends State<NavigationHub> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    WorkoutScreen(),
    WayfindingScreen(),
    NutritionScreen(),
    ProgramScreen(),
    HistoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.fitness_center_rounded),
            label: 'AI Coach',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.center_focus_strong_rounded),
            label: 'Gym Scan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.restaurant_menu_rounded),
            label: 'Nutrition',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.auto_awesome_rounded),
            label: 'Program',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_rounded),
            label: 'History',
          ),
        ],
      ),
    );
  }
}
