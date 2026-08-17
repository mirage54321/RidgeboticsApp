import 'package:flutter/material.dart';

import 'match_scope.dart';
import 'match_theme.dart';

/// Top bar shared by every tab in the match center: back button, this
/// team's number + currently selected event name, the push-notification
/// bell, and the "..." menu for switching which event is active.
class MatchTopBar extends StatelessWidget implements PreferredSizeWidget {
  const MatchTopBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final controller = MatchScope.of(context);
    final team = controller.myTeam;
    final eventName = team?.selectedEvent?.name;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: _iconTile(Icons.arrow_back),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  team != null ? 'Team ${team.teamNumber} match center' : 'Match center',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
                if (eventName != null)
                  Text(eventName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ),
          if (team != null && team.pushState != 'unsupported')
            GestureDetector(
              onTap: team.selectedEventKey == null ? null : () => _togglePush(context),
              child: Container(
                width: 34,
                height: 34,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: team.pushState == 'subscribed'
                      ? MatchColors.yellor
                      : MatchColors.yellorLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: team.pushBusy
                    ? const Padding(
                        padding: EdgeInsets.all(9),
                        child: CircularProgressIndicator(strokeWidth: 2, color: MatchColors.yellor),
                      )
                    : Icon(
                        team.pushState == 'subscribed'
                            ? Icons.notifications_active
                            : Icons.notifications_none,
                        color: team.pushState == 'subscribed' ? Colors.white : MatchColors.yellor,
                        size: 18,
                      ),
              ),
            ),
          GestureDetector(
            onTap: (team == null || team.events.isEmpty) ? null : () => _showEventPicker(context),
            child: _iconTile(Icons.more_horiz),
          ),
        ],
      ),
    );
  }

  Widget _iconTile(IconData icon) => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: MatchColors.yellorLight, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: MatchColors.yellor, size: 17),
      );

  Future<void> _togglePush(BuildContext context) async {
    final controller = MatchScope.of(context);
    final team = controller.myTeam;
    if (team == null) return;
    final wasSubscribed = team.pushState == 'subscribed';
    final ok = await controller.togglePush();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(!ok
          ? (wasSubscribed ? 'Could not disable alerts, try again' : 'Could not enable alerts — check notification permission')
          : (wasSubscribed ? 'Match alerts turned off' : 'Match alerts on for Team ${team.teamNumber}')),
    ));
  }

  void _showEventPicker(BuildContext context) {
    final controller = MatchScope.of(context);
    final team = controller.myTeam;
    if (team == null) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Team ${team.teamNumber} — choose event', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            ...team.events.map((e) => GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    controller.setSelectedEvent(e.key);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      Icon(
                        e.key == team.selectedEventKey
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: e.key == team.selectedEventKey ? MatchColors.yellor : Colors.grey[400],
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(e.name, style: const TextStyle(fontSize: 14))),
                    ]),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

/// Dialog for setting (or replacing) the single team this app follows.
/// Since only one team can be "yours" at a time, this always overwrites
/// whichever team was previously set.
void showTeamPrompt(BuildContext context) {
  final controller = MatchScope.of(context);
  final ctrl = TextEditingController(text: controller.myTeam?.teamNumber ?? '');
  String? error;
  final isReplacing = controller.myTeam != null;
  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(isReplacing ? 'Change your team' : 'Set your team'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Team number',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            errorText: error,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MatchColors.yellor),
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isEmpty) {
                setD(() => error = 'Enter a team number');
                return;
              }
              Navigator.pop(ctx);
              controller.setMyTeam(t);
            },
            child: Text(isReplacing ? 'Save' : 'Add'),
          ),
        ],
      ),
    ),
  );
}