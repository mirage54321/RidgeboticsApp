import 'package:flutter/material.dart';

import '../match_models.dart';
import '../match_scope.dart';
import '../match_theme.dart';

/// Matchup simulator: type in any team numbers and get a predicted score.
/// Deliberately independent of whichever competition/event is currently
/// selected on the My Team tab — it's just a calculator.
///
/// Team lookups come from the same season-wide TeamStats list the Stats
/// tab uses (controller.loadAllTeamStats()), so every registered team
/// works here — not just the handful that used to be hardcoded in
/// mock_data.dart.
class MatchSimulatorTab extends StatefulWidget {
  const MatchSimulatorTab({super.key});

  @override
  State<MatchSimulatorTab> createState() => _MatchSimulatorTabState();
}

class _MatchSimulatorTabState extends State<MatchSimulatorTab> {
  final List<TextEditingController> _redCtrls = List.generate(3, (_) => TextEditingController());
  final List<TextEditingController> _blueCtrls = List.generate(3, (_) => TextEditingController());

  Future<List<TeamStats>>? _future;

  @override
  void dispose() {
    for (final c in [..._redCtrls, ..._blueCtrls]) {
      c.dispose();
    }
    super.dispose();
  }

  TeamStats? _findTeam(List<TeamStats> all, String number) {
    if (number.isEmpty) return null;
    for (final t in all) {
      if (t.teamNumber == number) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = MatchScope.of(context);
    _future ??= controller.loadAllTeamStats();

    return FutureBuilder<List<TeamStats>>(
      future: _future,
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
                  Text('Could not load team data right now.',
                      style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => setState(() => _future = controller.loadAllTeamStats()),
                    child: const Text('Try again', style: TextStyle(color: MatchColors.yellor, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
          );
        }

        final red = _redCtrls.map((c) => _findTeam(all, c.text.trim())).whereType<TeamStats>().toList();
        final blue = _blueCtrls.map((c) => _findTeam(all, c.text.trim())).whereType<TeamStats>().toList();
        final redScore = red.fold(0.0, (s, t) => s + t.epaTotal);
        final blueScore = blue.fold(0.0, (s, t) => s + t.epaTotal);
        final showResult = red.isNotEmpty || blue.isNotEmpty;
        final winProb = (redScore + blueScore) == 0 ? null : redScore / (redScore + blueScore);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          children: [
            const Text('Matchup Simulator', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Type in team numbers to preview a matchup', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 18),
            _allianceInputs('Red Alliance', MatchColors.red, _redCtrls, red, all),
            const SizedBox(height: 12),
            _allianceInputs('Blue Alliance', MatchColors.blue, _blueCtrls, blue, all),
            if (showResult) ...[
              const SizedBox(height: 16),
              _resultCard(red, blue, redScore, blueScore, winProb),
            ],
          ],
        );
      },
    );
  }

  Widget _allianceInputs(String title, Color color, List<TextEditingController> ctrls, List<TeamStats> resolved, List<TeamStats> all) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black.withValues(alpha: 0.07))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(3, (i) {
              final hasText = ctrls[i].text.trim().isNotEmpty;
              final resolvedThis = hasText && _findTeam(all, ctrls[i].text.trim()) != null;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                  child: TextField(
                    controller: ctrls[i],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Team',
                      filled: true,
                      fillColor: MatchColors.yellorLight,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      // Subtle hint if a number was typed but doesn't
                      // match any known team, instead of silently
                      // dropping it with no feedback.
                      suffixIcon: hasText && !resolvedThis
                          ? Icon(Icons.help_outline, size: 16, color: Colors.grey[400])
                          : null,
                    ),
                  ),
                ),
              );
            }),
          ),
          if (resolved.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: resolved
                  .map((t) => Chip(
                        label: Text('${t.teamNumber} · EPA ${t.epaTotal.toStringAsFixed(1)}', style: const TextStyle(fontSize: 11)),
                        backgroundColor: color.withValues(alpha: 0.1),
                        side: BorderSide.none,
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultCard(List<TeamStats> red, List<TeamStats> blue, double redScore, double blueScore, double? winProb) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: MatchColors.yellor, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PREDICTED RESULT',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.8), letterSpacing: 0.5)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _scoreColumn('Red', redScore, red.isEmpty),
              const Text('vs', style: TextStyle(color: Colors.white, fontSize: 14)),
              _scoreColumn('Blue', blueScore, blue.isEmpty),
            ],
          ),
          if (winProb != null) ...[
            const SizedBox(height: 16),
            _probabilityBar(winProb),
          ],
        ],
      ),
    );
  }

  Widget _scoreColumn(String label, double score, bool empty) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
        const SizedBox(height: 2),
        Text(empty ? '—' : score.round().toString(), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white)),
      ],
    );
  }

  Widget _probabilityBar(double winProb) {
    final redPct = (winProb * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Red $redPct%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
            Text('Blue ${100 - redPct}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: winProb.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: Colors.white.withValues(alpha: 0.3),
            valueColor: const AlwaysStoppedAnimation(Colors.white),
          ),
        ),
      ],
    );
  }
}