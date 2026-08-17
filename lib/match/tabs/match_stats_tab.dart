import 'dart:async';

import 'package:flutter/material.dart';

import '../match_data_controller.dart';
import '../match_models.dart';
import '../match_scope.dart';
import '../match_theme.dart';
import '../team_detail_screen.dart';

/// "Stats" tab: top 50 teams by EPA on load, with a search bar. Typing a
/// team number and submitting looks that team up directly (plus a small
/// window of teams ranked around it) instead of scanning a big local
/// list — so search works for any registered team, not just whichever
/// ones happened to be in the top 50. If a team is set, a "Your team"
/// toggle does the same lookup for your own team number; that toggle is
/// hidden entirely when no team is set, since there's nothing to jump to.
class MatchStatsTab extends StatefulWidget {
  const MatchStatsTab({super.key});

  @override
  State<MatchStatsTab> createState() => MatchStatsTabState();
}

enum _StatsView { top, searchResult }

class MatchStatsTabState extends State<MatchStatsTab> {
  Future<List<TeamStats>>? topFuture;
  _StatsView view = _StatsView.top;

  String query = '';
  Timer? _debounce;

  bool searchLoading = false;
  String? searchError;
  TeamStats? searchedTeam;
  List<TeamStats> searchedNearby = [];

  bool showMyTeam = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = MatchScope.of(context);
    topFuture ??= controller.loadTopTeamStats(limit: 50);
    final myTeamNumber = controller.myTeam?.teamNumber;
    final showToggle = myTeamNumber != null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Team Stats', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                view == _StatsView.top
                    ? 'Top 50 by EPA · search any team number'
                    : 'Search result',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: Colors.grey[400], size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              enabled: !showMyTeam,
                              decoration: const InputDecoration(hintText: 'Search team number', border: InputBorder.none),
                              keyboardType: TextInputType.number,
                              onChanged: onQueryChanged,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (showToggle) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => toggleMyTeam(myTeamNumber),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: showMyTeam ? MatchColors.yellor : MatchColors.yellorLight,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'Your team',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: showMyTeam ? Colors.white : MatchColors.yellorDark,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        Expanded(child: body(context, myTeamNumber)),
      ],
    );
  }

  Widget body(BuildContext context, String? myTeamNumber) {
    if (view == _StatsView.searchResult) {
      if (searchLoading) {
        return const Center(child: CircularProgressIndicator(color: MatchColors.yellor));
      }
      if (searchError != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(searchError!, style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
          ),
        );
      }
      if (searchedTeam == null) {
        return const SizedBox.shrink();
      }
      final list = [searchedTeam!, ...searchedNearby.where((t) => t.teamNumber != searchedTeam!.teamNumber)]
        ..sort((a, b) => b.epaTotal.compareTo(a.epaTotal));
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        itemCount: list.length,
        itemBuilder: (ctx, i) => teamRow(context, list[i], list[i].rank, list[i].teamNumber == searchedTeam!.teamNumber),
      );
    }

    return FutureBuilder<List<TeamStats>>(
      future: topFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: MatchColors.yellor));
        }

        final top = snapshot.data ?? [];
        if (top.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Could not load team stats right now.',
                      style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () {
                      final controller = MatchScope.of(context);
                      setState(() => topFuture = controller.loadTopTeamStats(limit: 50));
                    },
                    child: const Text('Try again', style: TextStyle(color: MatchColors.yellor, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          color: MatchColors.yellor,
          onRefresh: () async {
            final controller = MatchScope.of(context);
            final f = controller.loadTopTeamStats(limit: 50);
            setState(() => topFuture = f);
            await f;
          },
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
            itemCount: top.length,
            itemBuilder: (ctx, i) => teamRow(context, top[i], i + 1, top[i].teamNumber == myTeamNumber),
          ),
        );
      },
    );
  }

  void onQueryChanged(String v) {
    query = v.trim();
    _debounce?.cancel();

    if (query.isEmpty) {
      setState(() {
        view = _StatsView.top;
        searchedTeam = null;
        searchedNearby = [];
        searchError = null;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () => runSearch(query));
  }

  Future<void> runSearch(String teamNumber) async {
    if (teamNumber.isEmpty) return;
    setState(() {
      view = _StatsView.searchResult;
      searchLoading = true;
      searchError = null;
    });

    final controller = MatchScope.of(context);
    final result = await controller.loadTeamWithNeighbors(teamNumber, window: 5);

    if (!mounted) return;
    setState(() {
      searchLoading = false;
      if (result == null) {
        searchError = "We don't have stats for team $teamNumber yet.";
        searchedTeam = null;
        searchedNearby = [];
      } else {
        searchedTeam = result.team;
        searchedNearby = result.nearby;
      }
    });
  }

  void toggleMyTeam(String myTeamNumber) {
    setState(() => showMyTeam = !showMyTeam);
    if (showMyTeam) {
      runSearch(myTeamNumber);
    } else {
      setState(() {
        view = _StatsView.top;
        searchedTeam = null;
        searchedNearby = [];
        searchError = null;
      });
    }
  }

  Widget teamRow(BuildContext context, TeamStats team, int position, bool isMine) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TeamDetailScreen(team: team))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isMine ? MatchColors.yellorLight : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isMine ? MatchColors.yellor : Colors.black.withValues(alpha: 0.07), width: isMine ? 1.5 : 1),
        ),
        child: Row(
          children: [
            SizedBox(width: 32, child: Text('$position', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[400]))),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: MatchColors.yellorLight, borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: Text(team.teamNumber, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: MatchColors.yellorDark)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(team.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  Text('Rank ${team.rank} · ${team.wins}-${team.losses}-${team.ties}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(team.epaTotal.toStringAsFixed(1), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: MatchColors.yellorDark)),
                Text('EPA', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
              ],
            ),
          ],
        ),
      ),
    );
  }
}