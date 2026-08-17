import 'package:flutter/material.dart';

import '../match_data_controller.dart';
import '../match_models.dart';
import '../match_scope.dart';
import '../match_theme.dart';
import '../match_top_bar.dart';

/// "My Team" tab: the single team this app follows. This replaces the old
/// separate Teams tab and Overview tab — you set your team here, and see
/// its next match countdown here too.
///
/// Match-finding logic:
///  1. If there's an unplayed match at the currently selected event, show
///     its countdown.
///  2. Otherwise, if there's a future event on the schedule (matches just
///     haven't been posted yet), say so.
///  3. Otherwise, there's nothing left this season — show a "waiting for
///     next year's game" message instead of an empty screen.
class MyTeamTab extends StatelessWidget {
  const MyTeamTab({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = MatchScope.of(context);
    final team = controller.myTeam;

    if (team == null) {
      return _noTeamState(context);
    }
    if (team.isLoading && team.events.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: MatchColors.yellor));
    }
    if (team.error != null && team.events.isEmpty) {
      return _errorState(context, controller, team);
    }

    return RefreshIndicator(
      color: MatchColors.yellor,
      onRefresh: controller.refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _teamHeader(context, controller, team),
          const SizedBox(height: 12),
          _pushCard(controller, team),
          const SizedBox(height: 12),
          _matchOrWaitingCard(controller, team),
          if (team.nextMatch != null) ...[
            const SizedBox(height: 10),
            _suggestionsCard(controller, team, team.nextMatch!),
          ],
        ],
      ),
    );
  }

  Widget _noTeamState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: MatchColors.yellorLight, borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.groups_outlined, color: MatchColors.yellorDark, size: 30),
            ),
            const SizedBox(height: 16),
            const Text('Set your team', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Add your team number to see its schedule, get match alerts, and track upcoming competitions.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: MatchColors.yellor),
              onPressed: () => showTeamPrompt(context),
              child: const Text('Set your team'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState(BuildContext context, MatchDataController controller, MyTeam team) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(team.error!, style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: controller.refreshEvents,
              child: const Text('Try again', style: TextStyle(color: MatchColors.yellor, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _teamHeader(BuildContext context, MatchDataController controller, MyTeam team) {
    final status = team.myStatus;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: MatchColors.yellorLight, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Text(team.teamNumber, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MatchColors.yellorDark)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Team ${team.teamNumber}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(
                  team.loadingEvents
                      ? 'Loading…'
                      : (status != null
                          ? 'Rank ${status.rank ?? '—'}${status.numTeams != null ? '/${status.numTeams}' : ''} · ${status.wins}-${status.losses}-${status.ties}'
                          : (team.selectedEvent?.name ?? 'No event selected')),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => showTeamPrompt(context),
            child: Icon(Icons.edit_outlined, size: 18, color: Colors.grey[400]),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _confirmStop(context, controller, team),
            child: Icon(Icons.close, size: 18, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  void _confirmStop(BuildContext context, MatchDataController controller, MyTeam team) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stop following Team ${team.teamNumber}?'),
        content: const Text("You'll stop getting its match alerts."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              controller.clearMyTeam();
            },
            child: const Text('Remove', style: TextStyle(color: MatchColors.red)),
          ),
        ],
      ),
    );
  }

  Widget _pushCard(MatchDataController controller, MyTeam team) {
    if (team.pushState == 'unsupported') return const SizedBox.shrink();
    final subscribed = team.pushState == 'subscribed';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: subscribed ? MatchColors.yellor : MatchColors.yellorLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(subscribed ? Icons.notifications_active : Icons.notifications_none,
                color: subscribed ? Colors.white : MatchColors.yellor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subscribed ? 'Match alerts on' : 'Get match alerts',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  subscribed
                      ? "You'll get a push notification before Team ${team.teamNumber}'s matches."
                      : 'Turn on the bell up top to get notified before matches start.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _matchOrWaitingCard(MatchDataController controller, MyTeam team) {
    final next = team.nextMatch;
    if (next != null) return _countdownCard(controller, team, next);

    final upcomingEvent = team.nextUpcomingEvent;
    if (upcomingEvent != null) {
      return _upcomingEventCard(upcomingEvent);
    }

    final nextSeasonYear = DateTime.now().year + 1;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: MatchColors.yellorLight, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          const Icon(Icons.hourglass_empty, color: MatchColors.yellorDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No upcoming matches on the schedule for Team ${team.teamNumber} — waiting for the $nextSeasonYear game release.',
              style: const TextStyle(fontSize: 13, color: MatchColors.yellorDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _upcomingEventCard(MatchEvent event) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: MatchColors.yellorLight, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          const Icon(Icons.event_outlined, color: MatchColors.yellorDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('No matches scheduled yet', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: MatchColors.yellorDark)),
                const SizedBox(height: 2),
                Text('Next up: ${event.name}', style: const TextStyle(fontSize: 12, color: MatchColors.yellorDark)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _countdownCard(MatchDataController controller, MyTeam team, MatchInfo next) {
    final time = next.bestTime;
    final timeUntil = time != null ? time.difference(DateTime.now()) : null;
    final winProb = controller.winProbabilityFor(team, next);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: MatchColors.yellor, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NEXT MATCH',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.8),
                  letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(next.label, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 6),
          Text(
            timeUntil == null
                ? 'Time not posted yet'
                : (timeUntil.isNegative ? 'Should be on the field now' : 'in ${controller.formatDuration(timeUntil)}'),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          if (time != null) ...[
            const SizedBox(height: 2),
            Text(_clockLabel(time), style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.9))),
          ],
          if (winProb != null) ...[
            const SizedBox(height: 14),
            _winBar(winProb),
          ],
        ],
      ),
    );
  }

  Widget _winBar(double winProb) {
    final pct = (winProb * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Est. win chance', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
            Text('$pct%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
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

  Widget _suggestionsCard(MatchDataController controller, MyTeam team, MatchInfo next) {
    final time = next.bestTime;
    final timeUntil = time != null ? time.difference(DateTime.now()) : Duration.zero;
    final winProb = controller.winProbabilityFor(team, next);
    final tips = controller.suggestionsFor(team, next, timeUntil, winProb);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.lightbulb_outline, color: MatchColors.yellorDark, size: 18),
            SizedBox(width: 8),
            Text('Before this match',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: MatchColors.yellorDark)),
          ]),
          const SizedBox(height: 10),
          ...tips.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('•  $t', style: const TextStyle(fontSize: 13)),
              )),
        ],
      ),
    );
  }

  String _clockLabel(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}