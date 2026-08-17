import 'package:flutter/material.dart';

import '../match_models.dart';
import '../match_scope.dart';
import '../match_theme.dart';
import '../team_detail_screen.dart';

/// "Stats" tab: every team's stats for the season, ranked by EPA, with a
/// search bar. If a team is set, a "Your team" toggle jumps to your
/// team's ranking and the teams just above/below it — that toggle is
/// hidden entirely when no team is set, since there's nothing to jump to.
class MatchStatsTab extends StatefulWidget {
  const MatchStatsTab({super.key});

  @override
  State<MatchStatsTab> createState() => MatchStatsTabState();
}

class MatchStatsTabState extends State<MatchStatsTab> {
  Future<List<TeamStats>>? future;
  String query = '';
  bool showMyTeam = false;

  @override
  Widget build(BuildContext context) {
    final controller = MatchScope.of(context);
    future ??= controller.loadAllTeamStats();
    final myTeamNumber = controller.myTeam?.teamNumber;

    return FutureBuilder<List<TeamStats>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: MatchColors.yellor));
        }

        final all = snapshot.data ?? [];
        if (all.isEmpty) {
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
                    onTap: () => setState(() => future = controller.loadAllTeamStats()),
                    child: const Text('Try again', style: TextStyle(color: MatchColors.yellor, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
          );
        }

        final sorted = [...all]..sort((a, b) => b.epaTotal.compareTo(a.epaTotal));
        final showToggle = myTeamNumber != null;

        List<TeamStats> visible;
        if (showMyTeam && showToggle) {
          final myIndex = sorted.indexWhere((t) => t.teamNumber == myTeamNumber);
          if (myIndex == -1) {
            visible = [];
          } else {
            final start = (myIndex - 3).clamp(0, sorted.length);
            final end = (myIndex + 4).clamp(0, sorted.length);
            visible = sorted.sublist(start, end);
          }
        } else {
          visible = query.isEmpty
              ? sorted
              : sorted
                  .where((t) =>
                      t.teamNumber.contains(query) || t.name.toLowerCase().contains(query.toLowerCase()))
                  .toList();
        }

        return RefreshIndicator(
          color: MatchColors.yellor,
          onRefresh: () async {
            final f = controller.loadAllTeamStats();
            setState(() => future = f);
            await f;
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Team Stats', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Ranked by EPA · ${sorted.length} teams', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
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
                                    decoration: const InputDecoration(hintText: 'Search team number or name', border: InputBorder.none),
                                    onChanged: (v) => setState(() => query = v),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (showToggle) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => setState(() => showMyTeam = !showMyTeam),
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
              if (showMyTeam && showToggle && visible.isEmpty)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text("We don't have stats for team $myTeamNumber yet.",
                          style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
                    ),
                  ),
                )
              else if (visible.isEmpty)
                Expanded(
                  child: Center(child: Text('No teams match "$query"', style: TextStyle(color: Colors.grey[600]))),
                )
              else
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                    itemCount: visible.length,
                    itemBuilder: (ctx, i) =>
                        teamRow(context, visible[i], sorted.indexOf(visible[i]) + 1, visible[i].teamNumber == myTeamNumber),
                  ),
                ),
            ],
          ),
        );
      },
    );
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