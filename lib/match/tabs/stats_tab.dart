import 'package:flutter/material.dart';

import '../match_theme.dart';
import '../mock_data.dart';
import '../team_detail_screen.dart';

class StatsTab extends StatefulWidget {
  const StatsTab({super.key});

  @override
  State<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<StatsTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final sorted = [...mockTeams]..sort((a, b) => b.epaTotal.compareTo(a.epaTotal));
    final filtered = _query.isEmpty
        ? sorted
        : sorted.where((t) => t.number.contains(_query) || t.name.toLowerCase().contains(_query.toLowerCase())).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Team Stats', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Ranked by EPA across the event', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.black.withValues(alpha: 0.07))),
                child: Row(
                  children: [
                    Icon(Icons.search, color: Colors.grey[400], size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(hintText: 'Search team number or name', border: InputBorder.none),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) => _teamRow(context, filtered[i], i + 1),
          ),
        ),
      ],
    );
  }

  Widget _teamRow(BuildContext context, MockTeam team, int position) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TeamDetailScreen(teamNumber: team.number))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black.withValues(alpha: 0.07))),
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