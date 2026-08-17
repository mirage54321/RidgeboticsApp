import 'package:flutter/material.dart';

import 'match/match_data_controller.dart';
import 'match/match_scope.dart';
import 'match/match_theme.dart';
import 'match/match_top_bar.dart';
import 'match/tabs/match_events_tab.dart';
import 'match/tabs/match_simulator_tab.dart';
import 'match/tabs/match_stats_tab.dart';
import 'match/tabs/my_team_tab.dart';

/// Entry point for the match-center feature. Same class name/constructor
/// as before so existing navigation (Navigator.push(... MatchNotifierScreen())
/// elsewhere in the app) keeps working unchanged.
class MatchNotifierScreen extends StatefulWidget {
  const MatchNotifierScreen({super.key});

  @override
  State<MatchNotifierScreen> createState() => _MatchNotifierScreenState();
}

class _MatchNotifierScreenState extends State<MatchNotifierScreen> {
  late final MatchDataController _controller;
  int _tabIndex = 0;

  static const int _myTeamTab = 0;
  static const int _statsTab = 1;
  static const int _eventsTab = 2;
  static const int _simulatorTab = 3;

  @override
  void initState() {
    super.initState();
    _controller = MatchDataController();
    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MatchScope(
      controller: _controller,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (_controller.isLoading) {
            return const Scaffold(
              backgroundColor: Color.fromARGB(255, 255, 255, 248),
              body: Center(child: CircularProgressIndicator(color: MatchColors.yellor)),
            );
          }

          // Unlike before, there's no separate "add your first team" gate
          // screen for the whole shell — Stats, Events, and the Simulator
          // all work without a team set, so only the My Team tab shows an
          // empty state when one hasn't been picked yet.
          return Scaffold(
            backgroundColor: const Color.fromARGB(255, 255, 255, 248),
            appBar: const MatchTopBar(),
            body: SafeArea(
              top: false,
              child: IndexedStack(
                index: _tabIndex,
                children: const [
                  MyTeamTab(),
                  MatchStatsTab(),
                  MatchEventsTab(),
                  MatchSimulatorTab(),
                ],
              ),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _tabIndex,
              onDestinationSelected: (i) => setState(() => _tabIndex = i),
              backgroundColor: Colors.white,
              indicatorColor: MatchColors.yellorLight,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'My Team'),
                NavigationDestination(icon: Icon(Icons.leaderboard_outlined), selectedIcon: Icon(Icons.leaderboard), label: 'Stats'),
                NavigationDestination(icon: Icon(Icons.event_outlined), selectedIcon: Icon(Icons.event), label: 'Events'),
                NavigationDestination(icon: Icon(Icons.compare_arrows_outlined), selectedIcon: Icon(Icons.compare_arrows), label: 'Sim'),
              ],
            ),
          );
        },
      ),
    );
  }
}