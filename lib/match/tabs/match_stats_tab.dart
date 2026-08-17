import 'package:flutter/material.dart';

import '../match_scope.dart';
import '../match_theme.dart';
import '../mock_data.dart';
import '../team_detail_screen.dart';

/// "Stats" tab: every team's stats, ranked by EPA, with a search bar and
/// a "Your team" toggle up top that jumps to your team's global ranking
/// and the teams just above/below it.
class MatchStatsTab extends StatefulWidget {
  const MatchStatsTab({super.key});

  @override
  State<MatchStatsTab> createState() => _MatchStatsTabState();
}

class _MatchStatsTabState extends State<MatchStatsTab> {
  String _query = '';
  bool _showMyTeam = false;

  @override
  Widget build(BuildContext context) {
    final controller = MatchScope.of(context);
    final myTeamNumber = controller.myTeam?.teamNumber;

    final sorted = [...mockTeams]..sort((a, b) => b.epaTotal.compareTo(a.epaTotal));

    List<MockTeam> visible;
    if (_showMyTeam) {
      final myIndex = sorted.indexWhere((t) => t.number == myTeamNumber);
      if (myIndex == -1) {
        visible = [];
      } else {
        final start = (myIndex - 3).clamp(0, sorted.length);
        final end = (myIndex + 4).clamp(0, sorted.length);
        visible = sorted.sublist(start, end);
      }
    } else {
      visible = _query.isEmpty
          ? sorted
          : sorted
              .where((t) => t.number.contains(_query) || t.name.toLowerCase().contains(_query.toLowerCase()))
              .toList();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Team Stats', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Ranked by EPA', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
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
                              enabled: !_showMyTeam,
                              decoration: const InputDecoration(hintText: 'Search team number or name', border: InputBorder.none),
                              onChanged: (v) => setState(() => _query = v),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: myTeamNumber == null ? null : () => setState(() => _showMyTeam = !_showMyTeam),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: _showMyTeam ? MatchColors.yellor : MatchColors.yellorLight,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        'Your team',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _showMyTeam ? Colors.white : MatchColors.yellorDark,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_showMyTeam && visible.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  myTeamNumber == null
                      ? 'Set your team on the My Team tab first.'
                      : "We don't have stats for team $myTeamNumber yet.",
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
              itemCount: visible.length,
              itemBuilder: (ctx, i) =>
                  _teamRow(context, visible[i], sorted.indexOf(visible[i]) + 1, visible[i].number == myTeamNumber),
            ),
          ),
      ],
    );
  }

  Widget _teamRow(BuildContext context, MockTeam team, int position, bool isMine) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TeamDetailScreen(teamNumber: team.number))),
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
            SizedBox(width: 24, child: Text('$position', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[400]))),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: MatchColors.yellorLight, borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: Text(team.number, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: MatchColors.yellorDark)),
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