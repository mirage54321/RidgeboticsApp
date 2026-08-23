import 'package:flutter/material.dart';

import '../match_data_controller.dart';
import '../match_models.dart';
import '../match_scope.dart';
import '../match_theme.dart';

/// Full match schedule for an event: every known match, with your team's
/// matches highlighted and a rough "who looks favored" prediction on each,
/// based on event OPRs.
class MatchScheduleScreen extends StatefulWidget {
  final MatchEvent event;

  const MatchScheduleScreen({super.key, required this.event});

  @override
  State<MatchScheduleScreen> createState() => _MatchScheduleScreenState();
}

class _MatchScheduleScreenState extends State<MatchScheduleScreen> {
  List<MatchInfo> matches = [];
  Map<String, double> oprs = {};
  bool loading = true;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final controller = MatchScope.of(context);
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final loadedMatches = await controller
          .loadEventMatches(widget.event.key)
          .timeout(const Duration(seconds: 20));
      // OPRs aren't essential to showing the schedule itself, so a failure
      // here shouldn't block the match list — just fall back to no
      // predictions rather than failing the whole screen.
      List<TeamStats> stats = [];
      try {
        stats = await controller
            .loadEventTeamStatsFor(widget.event.key)
            .timeout(const Duration(seconds: 15));
      } catch (_) {
        stats = [];
      }
      if (!mounted) return;
      final sorted = [...loadedMatches]
        ..sort((a, b) {
          final at = a.bestTime;
          final bt = b.bestTime;
          if (at == null && bt == null) return a.matchNumber.compareTo(b.matchNumber);
          if (at == null) return 1;
          if (bt == null) return -1;
          return at.compareTo(bt);
        });
      setState(() {
        matches = sorted;
        // Only include teams that actually have OPR data yet -- a team
        // with no matches played has opr == null, not 0.0.
        oprs = {
          for (final t in stats)
            if (t.opr != null) 'frc${t.teamNumber}': t.opr!,
        };
        loading = false;
      });
    } catch (e) {
      debugPrint('loadMatchSchedule failed: $e');
      controller.evictEventMatchesCache(widget.event.key);
      if (!mounted) return;
      setState(() {
        loading = false;
        failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final myTeamKey = MatchScope.of(context).myTeam?.teamKey;

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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Match schedule', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        Text(
                          widget.event.name,
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: body(myTeamKey)),
          ],
        ),
      ),
    );
  }

  Widget body(String? myTeamKey) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: MatchColors.yellor));
    }
    if (failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not load the match schedule.', style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: load,
                child: const Text('Try again', style: TextStyle(color: MatchColors.yellorDark, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
    }
    if (matches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('The match schedule has not been posted yet.', style: TextStyle(color: Colors.grey[600])),
        ),
      );
    }
    final showLegend = oprs.isNotEmpty;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: matches.length + (showLegend ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (showLegend && i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Numbers in parentheses are each team\u2019s estimated points (OPR) at this event.',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          );
        }
        final matchIndex = showLegend ? i - 1 : i;
        return matchCard(matches[matchIndex], myTeamKey);
      },
    );
  }

  Widget matchCard(MatchInfo m, String? myTeamKey) {
    final controller = MatchScope.of(context);
    final isMine = myTeamKey != null && m.hasTeam(myTeamKey);
    final prob = controller.winProbabilityBetweenOprs(oprs, m.redTeams, m.blueTeams);

    String? predictionText;
    Color predictionColor = Colors.grey;
    if (prob != null) {
      final redFavored = prob >= 0.5;
      final pct = ((redFavored ? prob : 1 - prob) * 100).round();
      predictionText = '${redFavored ? 'Red' : 'Blue'} favored \u00b7 $pct%';
      predictionColor = redFavored ? MatchColors.red : MatchColors.blue;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isMine ? MatchColors.yellorLight : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMine ? MatchColors.yellor : Colors.black.withValues(alpha: 0.07),
          width: isMine ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(m.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  if (isMine) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.star, color: MatchColors.yellor, size: 14),
                  ],
                ],
              ),
              Text(
                m.bestTime != null ? _dayAndTime(m.bestTime!) : 'Time TBD',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
          const SizedBox(height: 10),
          allianceLine(m.redTeams, MatchColors.red),
          const SizedBox(height: 4),
          allianceLine(m.blueTeams, MatchColors.blue),
          if (predictionText != null || m.isPlayed) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (predictionText != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: predictionColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: Text(predictionText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: predictionColor)),
                  ),
                if (m.isPlayed)
                  Text('Final: ${m.redScore} \u2013 ${m.blueScore}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget allianceLine(List<String> teamKeys, Color color) {
    final label = teamKeys.map((k) {
      final number = k.replaceFirst('frc', '');
      final opr = oprs[k];
      return opr != null ? '$number (${opr.toStringAsFixed(1)})' : number;
    }).join(', ');
    return Row(
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  String _dayAndTime(DateTime t) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.hour >= 12 ? 'PM' : 'AM';
    return '${days[t.weekday - 1]} $hour:$minute $period';
  }
}