import 'package:flutter/material.dart';

import 'match_theme.dart';
import 'mock_data.dart';

class TeamDetailScreen extends StatelessWidget {
  final String teamNumber;

  const TeamDetailScreen({super.key, required this.teamNumber});

  @override
  Widget build(BuildContext context) {
    final team = findMockTeam(teamNumber);
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 248),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: MatchColors.yellorLight, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.arrow_back, color: MatchColors.yellor, size: 17),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('Team $teamNumber', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Expanded(
              child: team == null
                  ? Center(child: Text('No stats found for team $teamNumber', style: TextStyle(color: Colors.grey[600])))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _header(team),
                        const SizedBox(height: 16),
                        _epaCard(team),
                        const SizedBox(height: 16),
                        _recordCard(team),
                        const SizedBox(height: 16),
                        _nextMatchCard(team),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(MockTeam team) {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: MatchColors.yellor, borderRadius: BorderRadius.circular(16)),
          alignment: Alignment.center,
          child: Text(team.number, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(team.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text('Rank ${team.rank} of ${mockTeams.length}', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _epaCard(MockTeam team) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: MatchColors.yellor, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TOTAL EPA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.8), letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(team.epaTotal.toStringAsFixed(1), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 18),
          _epaBreakdownRow('Auto', team.epaAuto, team.epaTotal),
          const SizedBox(height: 10),
          _epaBreakdownRow('Teleop', team.epaTeleop, team.epaTotal),
          const SizedBox(height: 10),
          _epaBreakdownRow('Endgame', team.epaEndgame, team.epaTotal),
        ],
      ),
    );
  }

  Widget _epaBreakdownRow(String label, double value, double total) {
    final fraction = total == 0 ? 0.0 : (value / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
            Text(value.toStringAsFixed(1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: fraction, minHeight: 6, backgroundColor: Colors.white.withValues(alpha: 0.3), valueColor: const AlwaysStoppedAnimation(Colors.white)),
        ),
      ],
    );
  }

  Widget _recordCard(MockTeam team) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black.withValues(alpha: 0.07))),
      child: Row(
        children: [
          _statChip('Wins', '${team.wins}'),
          _statChip('Losses', '${team.losses}'),
          _statChip('Ties', '${team.ties}'),
          _statChip('Rank', '${team.rank}'),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _nextMatchCard(MockTeam team) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: MatchColors.yellorLight, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, color: MatchColors.yellorDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(team.nextMatchLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: MatchColors.yellorDark)),
                Text(team.nextMatchTime, style: TextStyle(fontSize: 12, color: MatchColors.yellorDark.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}