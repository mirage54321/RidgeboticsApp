import 'package:flutter/material.dart';

import '../match_models.dart';
import '../match_scope.dart';
import '../match_theme.dart';

/// Shown when tapping into a competition from the Events tab. Shows every
/// team competing at the event, and (if it's your team's event) the
/// people from your team scheduled to attend it. Only your own team can
/// add/remove names (needs the team passcode), same as the battery
/// feature's login.
class EventDetailScreen extends StatefulWidget {
  final MatchEvent event;
  final bool isMine;

  const EventDetailScreen({super.key, required this.event, required this.isMine});

  @override
  State<EventDetailScreen> createState() => EventDetailScreenState();
}

class EventDetailScreenState extends State<EventDetailScreen> {
  List<String> people = [];
  bool loadingPeople = true;

  List<EventTeamInfo> competitors = [];
  bool loadingCompetitors = true;

  @override
  void initState() {
    super.initState();
    loadPeople();
    loadCompetitors();
  }

  Future<void> loadPeople() async {
    final controller = MatchScope.of(context);
    final teamNumber = controller.myTeam?.teamNumber;
    if (teamNumber == null) {
      setState(() => loadingPeople = false);
      return;
    }
    final loaded = await controller.loadRoster(teamNumber, widget.event.key);
    if (!mounted) return;
    setState(() {
      people = loaded;
      loadingPeople = false;
    });
  }

  Future<void> loadCompetitors() async {
    final controller = MatchScope.of(context);
    final loaded = await controller.loadEventTeams(widget.event.key);
    if (!mounted) return;
    setState(() {
      competitors = loaded;
      loadingCompetitors = false;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                  if (widget.isMine) ...[
                    Text('Scheduled to attend', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                    const SizedBox(height: 10),
                    if (loadingPeople)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator(color: MatchColors.yellor)),
                      )
                    else if (people.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('No one has signed up yet.', style: TextStyle(color: Colors.grey[500])),
                      )
                    else
                      ...people.map((p) => personTile(p)),
                    const SizedBox(height: 12),
                    addPersonButton(),
                    const SizedBox(height: 24),
                  ],
                  Text('Competing teams', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                  const SizedBox(height: 10),
                  if (loadingCompetitors)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator(color: MatchColors.yellor)),
                    )
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

  Widget personTile(String name) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black.withValues(alpha: 0.07))),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 18, color: MatchColors.yellorDark),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
          GestureDetector(onTap: () => removePerson(name), child: Icon(Icons.close, size: 16, color: Colors.grey[400])),
        ],
      ),
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

  Widget addPersonButton() {
    return GestureDetector(
      onTap: addPerson,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: MatchColors.yellor.withValues(alpha: 0.4))),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: MatchColors.yellorDark, size: 18),
            SizedBox(width: 8),
            Text('Add someone', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: MatchColors.yellorDark)),
          ],
        ),
      ),
    );
  }

  Future<void> addPerson() async {
    final result = await promptNameAndPasscode(title: 'Add someone');
    if (result == null) return;
    final controller = MatchScope.of(context);
    final teamNumber = controller.myTeam!.teamNumber;
    final ok = await controller.addToRoster(teamNumber, result.passcode, widget.event.key, result.name);
    if (!mounted) return;
    if (ok) {
      setState(() => people = [...people, result.name]);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not add — check your team passcode')));
    }
  }

  Future<void> removePerson(String name) async {
    final passcode = await promptPasscodeOnly(title: 'Remove $name');
    if (passcode == null) return;
    final controller = MatchScope.of(context);
    final teamNumber = controller.myTeam!.teamNumber;
    final ok = await controller.removeFromRoster(teamNumber, passcode, widget.event.key, name);
    if (!mounted) return;
    if (ok) {
      setState(() => people = people.where((p) => p != name).toList());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not remove — check your team passcode')));
    }
  }

  Future<NamePasscode?> promptNameAndPasscode({required String title}) {
    final nameCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    return showDialog<NamePasscode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(labelText: 'Name', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: InputDecoration(labelText: 'Team passcode', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MatchColors.yellor),
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty || passCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, NamePasscode(nameCtrl.text.trim(), passCtrl.text.trim()));
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<String?> promptPasscodeOnly({required String title}) {
    final passCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: passCtrl,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(labelText: 'Team passcode', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MatchColors.red),
            onPressed: () {
              if (passCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, passCtrl.text.trim());
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

class NamePasscode {
  final String name;
  final String passcode;
  NamePasscode(this.name, this.passcode);
}