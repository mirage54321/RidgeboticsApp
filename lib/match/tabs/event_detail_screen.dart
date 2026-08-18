import 'package:flutter/material.dart';

import '../match_models.dart';
import '../match_scope.dart';
import '../match_theme.dart';

/// Shown when tapping into a competition from the Events tab. Shows every
/// team competing at the event, plus match results once the event has
/// started (who won, and the score).
class EventDetailScreen extends StatefulWidget {
  final MatchEvent event;
  final bool isMine;

  const EventDetailScreen({super.key, required this.event, required this.isMine});

  @override
  State<EventDetailScreen> createState() => EventDetailScreenState();
}

class EventDetailScreenState extends State<EventDetailScreen> {
  List<EventTeamInfo> competitors = [];
  bool loadingCompetitors = true;
  bool competitorsFailed = false;

  List<MatchInfo> matches = [];
  bool loadingMatches = true;
  bool matchesFailed = false;

  /// No point calling the matches endpoint for an event that hasn't
  /// started yet — there's nothing to show, and it just burns a request.
  bool get eventMayHaveResults {
    final start = widget.event.startDate;
    if (start == null) return true;
    return !start.isAfter(DateTime.now());
  }

  @override
  void initState() {
    super.initState();
    loadCompetitors();
    if (eventMayHaveResults) {
      loadMatches();
    } else {
      loadingMatches = false;
    }
  }

  Future<void> loadCompetitors() async {
    final controller = MatchScope.of(context);
    setState(() {
      loadingCompetitors = true;
      competitorsFailed = false;
    });
    try {
      final loaded = await controller
          .loadEventTeams(widget.event.key)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        competitors = loaded;
        loadingCompetitors = false;
      });
    } catch (e) {
      debugPrint('loadCompetitors timed out or failed: $e');
      // The in-flight request may still be sitting in the controller's
      // cache even though we've given up waiting on it here — evict it
      // so "Try again" (or the next visit to this event) starts a clean
      // request instead of re-awaiting the same stuck one.
      controller.evictEventTeamsCache(widget.event.key);
      if (!mounted) return;
      setState(() {
        loadingCompetitors = false;
        competitorsFailed = true;
      });
    }
  }

  Future<void> loadMatches() async {
    final controller = MatchScope.of(context);
    setState(() {
      loadingMatches = true;
      matchesFailed = false;
    });
    try {
      final loaded = await controller
          .loadEventMatches(widget.event.key)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        matches = loaded;
        loadingMatches = false;
      });
    } catch (e) {
      debugPrint('loadMatches timed out or failed: $e');
      controller.evictEventMatchesCache(widget.event.key);
      if (!mounted) return;
      setState(() {
        loadingMatches = false;
        matchesFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final playedMatches = matches.where((m) => m.isPlayed).toList()
      ..sort((a, b) {
        final at = a.bestTime;
        final bt = b.bestTime;
        if (at == null && bt == null) return b.matchNumber.compareTo(a.matchNumber);
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });

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
                    child: Text(widget.event.name,
                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (eventMayHaveResults) ...[
                    Text('Match results', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                    const SizedBox(height: 10),
                    if (loadingMatches)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator(color: MatchColors.yellor)),
                      )
                    else if (matchesFailed)
                      retryTile('Could not load match results.', loadMatches)
                    else if (playedMatches.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('No results posted yet.', style: TextStyle(color: Colors.grey[500])),
                      )
                    else
                      ...playedMatches.map((m) => matchResultTile(m)),
                    const SizedBox(height: 24),
                  ],
                  Text('Competing teams', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                  const SizedBox(height: 10),
                  if (loadingCompetitors)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator(color: MatchColors.yellor)),
                    )
                  else if (competitorsFailed)
                    retryTile('Could not load the team list.', loadCompetitors)
                  else if (competitors.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('Team list not available yet for this event.', style: TextStyle(color: Colors.grey[500])),
                    )
                  else
                    ...competitors.map((c) => competitorTile(c)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget retryTile(String message, Future<void> Function() onRetry) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onRetry,
            child: const Text('Try again', style: TextStyle(color: MatchColors.yellorDark, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget matchResultTile(MatchInfo m) {
    final winner = m.redScore! > m.blueScore!
        ? 'red'
        : (m.blueScore! > m.redScore! ? 'blue' : 'tie');
    final winnerLabel = winner == 'tie' ? 'TIE' : '${winner.toUpperCase()} WON';
    final winnerColor = winner == 'tie'
        ? Colors.grey[500]!
        : (winner == 'red' ? MatchColors.red : MatchColors.blue);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black.withValues(alpha: 0.07))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(m.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: winnerColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(winnerLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: winnerColor)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          allianceRow('Red', m.redTeams, m.redScore, winner == 'red', MatchColors.red),
          const SizedBox(height: 4),
          allianceRow('Blue', m.blueTeams, m.blueScore, winner == 'blue', MatchColors.blue),
        ],
      ),
    );
  }

  Widget allianceRow(String label, List<String> teamKeys, int? score, bool won, Color color) {
    final numbers = teamKeys.map((k) => k.replaceFirst('frc', '')).join(', ');
    return Row(
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            numbers,
            style: TextStyle(fontSize: 12, fontWeight: won ? FontWeight.w700 : FontWeight.w400, color: won ? color : Colors.grey[700]),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          '${score ?? '-'}',
          style: TextStyle(fontSize: 14, fontWeight: won ? FontWeight.w800 : FontWeight.w500, color: won ? color : Colors.grey[700]),
        ),
      ],
    );
  }

  Widget competitorTile(EventTeamInfo team) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black.withValues(alpha: 0.07))),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: MatchColors.yellorLight, borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: Text(team.teamNumber, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: MatchColors.yellorDark)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(team.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}