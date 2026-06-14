import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'rules_screen.dart';

void main() => runApp(const RoboLensApp());

const kBrand      = Color(0xFF00B3AC);
const kBrandLight = Color(0xFFE0F7F6);
const kPink       = Color(0xFFCF2879);

class RoboLensApp extends StatelessWidget {
  const RoboLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoboLens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF00B3AC),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FFFE),
      ),
      home: const MainNav(),
    );
  }
}

class MainNav extends StatefulWidget {
  const MainNav({super.key});

  @override
  State<MainNav> createState() => _MainNavState();
}

class _MainNavState extends State<MainNav> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const RulesScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      // bottomNavigationBar: NavigationBar(
      //   selectedIndex: _currentIndex,
      //   onDestinationSelected: (i) => setState(() => _currentIndex = i),
      //   backgroundColor: Colors.white,
      //   indicatorColor: kBrandLight,
      //   destinations: const [
      //     NavigationDestination(
      //       icon: Icon(Icons.search_outlined),
      //       selectedIcon: Icon(Icons.search, color: kBrand),
      //       label: 'Inspect',
      //     ),
      //     NavigationDestination(
      //       icon: Icon(Icons.rule_outlined),
      //       selectedIcon: Icon(Icons.rule, color: kPink),
      //       label: 'Rules',
      //     ),
        // ],
      // ),
    );
  }
}