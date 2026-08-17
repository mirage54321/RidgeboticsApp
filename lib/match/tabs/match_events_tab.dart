import 'package:flutter/material.dart';

import '../match_models.dart';
import '../match_scope.dart';
import '../match_theme.dart';
import 'event_detail_screen.dart';

/// "Events" tab: every FRC event from about six months ago through six
/// months from now, with the ones your team is registered for
/// highlighted. Tap an event to see who's scheduled to go.
class MatchEventsTab extends StatefulWidget {
  const MatchEventsTab({super.key});

  @override
  State<MatchEventsTab> createState() => _MatchEventsTabState();
}

class _MatchEventsTabState extends State<MatchEventsTab> {
  Future<List<MatchEvent>>? _future;

  @override
  Widget build(BuildContext context) {
    final controller = MatchScope.of(context);
    _future ??= controller.loadGlobalEvents();
    final myEventKeys = controller.myTeam?.events.map((e) => e.key).toSet() ?? <String>{};

    return FutureBuilder<List<MatchEvent>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: MatchColors.yellor));
        }
        final events = snapshot.data ?? [];
        if (events.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load events right now.', style: TextStyle(color: Colors.grey[600])),
            ),
          );
        }

        final now = DateTime.now();
        final upcoming = events.where((e) => e.endDate == null || !e.endDate!.isBefore(now)).toList();
        final past = events.where((e) => e.endDate != null && e.endDate!.isBefore(now)).toList().reversed.toList();

        return RefreshIndicator(
          color: MatchColors.yellor,
          onRefresh: () async {
            final f = controller.loadGlobalEvents();
            setState(() => _future = f);
            await f;
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Events', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Your events are highlighted', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 16),
              if (upcoming.isNotEmpty) ...[
                _sectionLabel('Upcoming & live'),
                ...upcoming.map((e) => _eventCard(context, e, myEventKeys.contains(e.key))),
              ],
              if (past.isNotEmpty) ...[
                const SizedBox(height: 12),
                _sectionLabel('Past'),
                ...past.map((e) => _eventCard(context, e, myEventKeys.contains(e.key))),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _sectionLabel(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[600])),
      );

  Widget _eventCard(BuildContext context, MatchEvent e, bool isMine) {
    final isLive = e.isLiveNow;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EventDetailScreen(event: e, isMine: isMine))),
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
            isLive
                ? const Icon(Icons.circle, size: 10, color: MatchColors.green)
                : const Icon(Icons.event_outlined, size: 18, color: MatchColors.yellorDark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  Text(_dateRange(e), style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
            if (isMine)
              const Icon(Icons.star, color: MatchColors.yellor, size: 18)
            else
              Icon(Icons.chevron_right, color: Colors.grey[400], size: 18),
          ],
        ),
      ),
    );
  }

  String _dateRange(MatchEvent e) {
    if (e.startDate == null) return '';
    final s = e.startDate!;
    String fmt(DateTime d) => '${_month(d.month)} ${d.day}';
    if (e.endDate == null) return fmt(s);
    return '${fmt(s)} \u2013 ${fmt(e.endDate!)}, ${e.endDate!.year}';
  }

  String _month(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m - 1];
}