import 'dart:async';

import 'package:flutter/material.dart';

import '../match_models.dart';
import '../match_scope.dart';
import '../match_theme.dart';

/// Matchup simulator using RoboLens' global, TBA-derived World Rating.
class MatchSimulatorTab extends StatefulWidget {
  const MatchSimulatorTab({super.key});

  @override
  State<MatchSimulatorTab> createState() => _MatchSimulatorTabState();
}

class _MatchSimulatorTabState extends State<MatchSimulatorTab> {
  final List<TextEditingController> _redCtrls = List.generate(
    3,
    (_) => TextEditingController(),
  );
  final List<TextEditingController> _blueCtrls = List.generate(
    3,
    (_) => TextEditingController(),
  );

  final List<Timer?> _redDebounce = List.generate(3, (_) => null);
  final List<Timer?> _blueDebounce = List.generate(3, (_) => null);

  // team number -> looked-up stats (or null if we already tried and it
  // doesn't exist) so repeated entries don't refetch.
  final Map<String, TeamStats?> _cache = {};
  final Set<String> _loading = {};
  final Set<String> _unavailable = {};

  @override
  void dispose() {
    for (final c in [..._redCtrls, ..._blueCtrls]) {
      c.dispose();
    }
    for (final t in [..._redDebounce, ..._blueDebounce]) {
      t?.cancel();
    }
    super.dispose();
  }

  TeamStats? _resolved(String number) => _cache[number];

  void _onChanged(int i, bool isRed) {
    setState(() {}); // reflect the raw text immediately (e.g. clearing a chip)

    final ctrl = isRed ? _redCtrls[i] : _blueCtrls[i];
    final debounceList = isRed ? _redDebounce : _blueDebounce;
    debounceList[i]?.cancel();

    final number = ctrl.text.trim();
    if (number.isEmpty || _cache.containsKey(number)) return;

    debounceList[i] = Timer(
      const Duration(milliseconds: 450),
      () => _lookup(number),
    );
  }

  Future<void> _lookup(String number) async {
    if (_cache.containsKey(number) || _loading.contains(number)) return;
    setState(() => _loading.add(number));

    try {
      final stats = await MatchScope.of(context).loadWorldTeamStats();
      final team = stats.where((team) => team.teamNumber == number).firstOrNull;
      if (!mounted) return;
      setState(() {
        _loading.remove(number);
        _cache[number] = team; // null means "not competing at this event"
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading.remove(number);
        _unavailable.add(number);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final red = _redCtrls
        .map((c) => _resolved(c.text.trim()))
        .whereType<TeamStats>()
        .toList()..sort((a, b) => b.opr.compareTo(a.opr));
    final blue = _blueCtrls
        .map((c) => _resolved(c.text.trim()))
        .whereType<TeamStats>()
        .toList()..sort((a, b) => b.opr.compareTo(a.opr));
    final redScore = red.fold(0.0, (s, t) => s + t.opr);
    final blueScore = blue.fold(0.0, (s, t) => s + t.opr);
    final showResult = red.isNotEmpty || blue.isNotEmpty;
    final winProb = (redScore + blueScore) == 0
        ? null
        : redScore / (redScore + blueScore);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        const Text(
          'Matchup Simulator',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Add team numbers to place robots on the field and compare World Ratings',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 18),
        _allianceInputs(
          'Red Alliance',
          MatchColors.red,
          _redCtrls,
          red,
          isRed: true,
        ),
        const SizedBox(height: 12),
        _allianceInputs(
          'Blue Alliance',
          MatchColors.blue,
          _blueCtrls,
          blue,
          isRed: false,
        ),
        const SizedBox(height: 16),
        _field(red, blue),
        if (showResult) ...[
          const SizedBox(height: 16),
        _resultCard(red, blue, redScore, blueScore, winProb),
        ],
      ],
    );
  }

  Widget _allianceInputs(
    String title,
    Color color,
    List<TextEditingController> ctrls,
    List<TeamStats> resolved, {
    required bool isRed,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(3, (i) {
              final number = ctrls[i].text.trim();
              final hasText = number.isNotEmpty;
              final isLoading = hasText && _loading.contains(number);
              final unavailable =
                  hasText && !isLoading && _unavailable.contains(number);
              final notFound =
                  hasText &&
                  !isLoading &&
                  !unavailable &&
                  _cache.containsKey(number) &&
                  _cache[number] == null;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                  child: TextField(
                    controller: ctrls[i],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    onChanged: (_) => _onChanged(i, isRed),
                    decoration: InputDecoration(
                      hintText: 'Team',
                      filled: true,
                      fillColor: MatchColors.yellorLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      suffixIcon: isLoading
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: MatchColors.yellor,
                                ),
                              ),
                            )
                          : unavailable
                          ? Icon(
                              Icons.error_outline,
                              size: 16,
                              color: Colors.red[400],
                            )
                          : notFound
                          ? Icon(
                              Icons.help_outline,
                              size: 16,
                              color: Colors.grey[400],
                            )
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
                  .map(
                    (t) => Chip(
                      label: Text(
                        '${t.teamNumber} · OPR ${t.opr.toStringAsFixed(1)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      backgroundColor: color.withValues(alpha: 0.1),
                      side: BorderSide.none,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(List<TeamStats> red, List<TeamStats> blue) {
    Widget robot(TeamStats team, Color color) => Container(
      width: 42, height: 34, alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white, width: 2)),
      child: Text(team.teamNumber, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700)),
    );
    return Container(
      height: 210,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xffD6C49B), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xff947C47), width: 3)),
      child: Stack(children: [
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: Colors.white.withValues(alpha: .8), width: 2), borderRadius: BorderRadius.circular(8)))),
        Align(alignment: Alignment.center, child: Container(width: 2, color: Colors.white.withValues(alpha: .9))),
        const Align(alignment: Alignment.topCenter, child: Padding(padding: EdgeInsets.only(top: 8), child: Text('FIELD', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xff5B4827), letterSpacing: 1.5)))),
        Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(left: 10), child: Wrap(spacing: 4, runSpacing: 4, children: red.map((t) => robot(t, MatchColors.red)).toList()))),
        Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(right: 10), child: Wrap(spacing: 4, runSpacing: 4, children: blue.map((t) => robot(t, MatchColors.blue)).toList()))),
        if (red.isEmpty) const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(left: 8), child: Text('RED', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)))),
        if (blue.isEmpty) const Align(alignment: Alignment.centerRight, child: Padding(padding: EdgeInsets.only(right: 8), child: Text('BLUE', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)))),
      ]),
    );
  }

  Widget _resultCard(
    List<TeamStats> red,
    List<TeamStats> blue,
    double redScore,
    double blueScore,
    double? winProb,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MatchColors.yellor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PREDICTED RESULT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.8),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _scoreColumn('Red', redScore, red.isEmpty),
              const Text(
                'vs',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              _scoreColumn('Blue', blueScore, blue.isEmpty),
            ],
          ),
          if (winProb != null) ...[
            const SizedBox(height: 16),
            _probabilityBar(winProb),
            const SizedBox(height: 14),
            ..._scoutingNotes(red, blue, redScore, blueScore).map((note) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(note, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: .95))),
            )),
          ],
        ],
      ),
    );
  }

  List<String> _scoutingNotes(List<TeamStats> red, List<TeamStats> blue, double redScore, double blueScore) {
    if (red.isEmpty || blue.isEmpty) return ['Add all six teams for a complete prediction.'];
    final favoredRed = redScore >= blueScore;
    final favored = favoredRed ? 'Red' : 'Blue';
    final underdog = favoredRed ? 'Blue' : 'Red';
    final leaders = favoredRed ? red : blue;
    final other = favoredRed ? blue : red;
    return [
      '$favored is predicted to win based on overall World Rating.',
      '$favored lead contributor: Team ${leaders.first.teamNumber}. Put them on the high-value opening task in auto.',
      '$underdog best chance: let Team ${other.first.teamNumber} focus on a reliable auto, then avoid traffic and missed cycles.',
    ];
  }

  Widget _scoreColumn(String label, double score, bool empty) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          empty ? '-' : score.round().toString(),
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
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
            Text(
              'Red $redPct%',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Text(
              'Blue ${100 - redPct}%',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
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
