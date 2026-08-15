import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'push_notifications.dart';

const Yellor = Color(0xFFFFC107);
const YellorLight = Color(0xFFFFF4E5);
const YellorDark = Color(0xFFB38600);
const greenChar = Color(0xFF4CAF50);
const redChar = Color(0xFFD93025);
const blueChar = Color(0xFF1A73E8);
const grayChar = Color(0xFFAAAAAA);

/// One qualification/playoff match on an event's schedule.
class MatchInfo {
  final String key;
  final String compLevel; // qm, qf, sf, f
  final int matchNumber;
  final int setNumber;
  final DateTime? predictedTime;
  final DateTime? actualTime;
  final List<String> redTeams;
  final List<String> blueTeams;
  final int? redScore;
  final int? blueScore;

  MatchInfo({
    required this.key,
    required this.compLevel,
    required this.matchNumber,
    required this.setNumber,
    required this.predictedTime,
    required this.actualTime,
    required this.redTeams,
    required this.blueTeams,
    required this.redScore,
    required this.blueScore,
  });

  bool get isPlayed =>
      redScore != null && redScore! >= 0 && blueScore != null && blueScore! >= 0;

  bool teamOnRed(String teamKey) => redTeams.contains(teamKey);
  bool teamOnBlue(String teamKey) => blueTeams.contains(teamKey);
  bool hasTeam(String teamKey) => teamOnRed(teamKey) || teamOnBlue(teamKey);

  // Best time we have for sorting/countdown: actual (if it happened to be
  // logged) falls back to predicted, since most matches never get an
  // actual_time until they're already done.
  DateTime? get bestTime => predictedTime ?? actualTime;

  String get label {
    switch (compLevel) {
      case 'qm':
        return 'Quals $matchNumber';
      case 'qf':
        return 'Quarters $setNumber-$matchNumber';
      case 'sf':
        return 'Semis $setNumber-$matchNumber';
      case 'f':
        return 'Finals $matchNumber';
      default:
        return '$compLevel $matchNumber';
    }
  }

  factory MatchInfo.fromJson(Map<String, dynamic> json) {
    final alliances = json['alliances'] as Map<String, dynamic>? ?? {};
    final red = alliances['red'] as Map<String, dynamic>? ?? {};
    final blue = alliances['blue'] as Map<String, dynamic>? ?? {};
    final predicted = json['predicted_time'] as int?;
    final actual = json['actual_time'] as int?;
    return MatchInfo(
      key: json['key'] as String? ?? '',
      compLevel: json['comp_level'] as String? ?? 'qm',
      matchNumber: json['match_number'] as int? ?? 0,
      setNumber: json['set_number'] as int? ?? 1,
      predictedTime: predicted != null
          ? DateTime.fromMillisecondsSinceEpoch(predicted * 1000)
          : null,
      actualTime: actual != null
          ? DateTime.fromMillisecondsSinceEpoch(actual * 1000)
          : null,
      redTeams: (red['team_keys'] as List<dynamic>? ?? []).cast<String>(),
      blueTeams: (blue['team_keys'] as List<dynamic>? ?? []).cast<String>(),
      redScore: red['score'] as int?,
      blueScore: blue['score'] as int?,
    );
  }
}

/// Team's ranking/record at a single event.
class TeamStatus {
  final int? rank;
  final int? numTeams;
  final int wins;
  final int losses;
  final int ties;

  TeamStatus({
    this.rank,
    this.numTeams,
    required this.wins,
    required this.losses,
    required this.ties,
  });

  factory TeamStatus.fromJson(Map<String, dynamic>? json) {
    if (json == null) return TeamStatus(wins: 0, losses: 0, ties: 0);
    final qual = json['qual'] as Map<String, dynamic>?;
    final ranking = qual?['ranking'] as Map<String, dynamic>?;
    final record = ranking?['record'] as Map<String, dynamic>?;
    return TeamStatus(
      rank: ranking?['rank'] as int?,
      numTeams: qual?['num_teams'] as int?,
      wins: record?['wins'] as int? ?? 0,
      losses: record?['losses'] as int? ?? 0,
      ties: record?['ties'] as int? ?? 0,
    );
  }
}

class MatchEvent {
  final String key;
  final String name;
  final DateTime? startDate;
  final DateTime? endDate;

  MatchEvent({required this.key, required this.name, this.startDate, this.endDate});

  factory MatchEvent.fromJson(Map<String, dynamic> json) {
    return MatchEvent(
      key: json['key'] as String? ?? '',
      name: json['name'] as String? ?? json['key'] as String? ?? 'Event',
      startDate:
          json['start_date'] != null ? DateTime.tryParse(json['start_date']) : null,
      endDate: json['end_date'] != null ? DateTime.tryParse(json['end_date']) : null,
    );
  }

  bool get isLiveNow {
    final now = DateTime.now();
    if (startDate == null || endDate == null) return false;
    final end = endDate!.add(const Duration(days: 1));
    return now.isAfter(startDate!.subtract(const Duration(days: 1))) && now.isBefore(end);
  }
}

class MatchNotifierScreen extends StatefulWidget {
  const MatchNotifierScreen({super.key});

  @override
  State<MatchNotifierScreen> createState() => _MatchNotifierScreenState();
}

class _MatchNotifierScreenState extends State<MatchNotifierScreen> {
  static const String _base = 'https://ridgeboticsapp.onrender.com';

  String? teamNum;
  List<MatchEvent> _events = [];
  String? _selectedEventKey;

  List<MatchInfo> _matches = [];
  Map<String, double> _oprs = {};
  TeamStatus? _myStatus;

  bool _isLoading = true;
  bool _loadingEvents = false;
  String? _error;

  // 'unsupported' | 'unsubscribed' | 'subscribed'
  String _pushState = 'unsupported';
  bool _pushBusy = false;

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _init();
    _refreshPushState();
    // Tick every second so the "time before match" countdown feels live.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _refreshPushState() async {
    final state = await PushNotifications.subscriptionState();
    if (mounted) setState(() => _pushState = state);
  }

  Future<void> _togglePush() async {
    if (_pushBusy || teamNum == null || _selectedEventKey == null) return;
    setState(() => _pushBusy = true);
    bool ok;
    if (_pushState == 'subscribed') {
      ok = await PushNotifications.unsubscribe();
    } else {
      ok = await PushNotifications.subscribe(teamNum!, _selectedEventKey!);
    }
    await _refreshPushState();
    if (!mounted) return;
    setState(() => _pushBusy = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_pushState == 'subscribed'
              ? 'Could not enable alerts — check notification permission'
              : 'Could not disable alerts, try again')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_pushState == 'subscribed'
              ? 'Match alerts on for Team $teamNum'
              : 'Match alerts turned off')));
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _teamKey => 'frc$teamNum';

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final team = prefs.getString('match_team');
    final event = prefs.getString('match_event');
    if (team == null) {
      setState(() => _isLoading = false);
      _showTeamPrompt(firstTime: true);
      return;
    }
    teamNum = team;
    await _loadEvents(silent: true);
    if (_events.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'No events found for team $teamNum this season';
      });
      return;
    }
    _selectedEventKey = event != null && _events.any((e) => e.key == event)
        ? event
        : (_events.firstWhere((e) => e.isLiveNow, orElse: () => _events.last)).key;
    await _loadEventData();
  }

  Future<void> _loadEvents({bool silent = false}) async {
    if (teamNum == null) return;
    setState(() {
      if (!silent) _isLoading = true;
      _loadingEvents = true;
      _error = null;
    });
    try {
      final year = DateTime.now().year;
      final uri = Uri.parse('$_base/match/events?teamNumber=$teamNum&year=$year');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        setState(() {
          _error = 'Could not load events for that team';
          _isLoading = false;
          _loadingEvents = false;
        });
        return;
      }
      final list = jsonDecode(res.body) as List<dynamic>;
      final loaded = list.map((e) => MatchEvent.fromJson(e as Map<String, dynamic>)).toList();
      loaded.sort((a, b) => (a.startDate ?? DateTime(2000)).compareTo(b.startDate ?? DateTime(2000)));
      setState(() {
        _events = loaded;
        _loadingEvents = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not connect, try again';
        _isLoading = false;
        _loadingEvents = false;
      });
    }
  }

  Future<void> _loadEventData() async {
    if (teamNum == null || _selectedEventKey == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('match_team', teamNum!);
      await prefs.setString('match_event', _selectedEventKey!);

      final uri = Uri.parse(
          '$_base/match/data?teamNumber=$teamNum&eventKey=$_selectedEventKey');
      final res = await http.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        setState(() {
          _error = 'Could not load match data';
          _isLoading = false;
        });
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;

      final matchesJson = data['matches'] as List<dynamic>? ?? [];
      final loadedMatches =
          matchesJson.map((m) => MatchInfo.fromJson(m as Map<String, dynamic>)).toList();
      loadedMatches.sort((a, b) {
        final at = a.bestTime;
        final bt = b.bestTime;
        if (at == null && bt == null) return a.matchNumber.compareTo(b.matchNumber);
        if (at == null) return 1;
        if (bt == null) return -1;
        return at.compareTo(bt);
      });

      final oprsJson = data['oprs'] as Map<String, dynamic>? ?? {};
      final loadedOprs = oprsJson.map((k, v) => MapEntry(k, (v as num).toDouble()));

      setState(() {
        _matches = loadedMatches;
        _oprs = loadedOprs;
        _myStatus = TeamStatus.fromJson(data['status'] as Map<String, dynamic>?);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not connect, try again';
        _isLoading = false;
      });
    }
  }

  // ---- derived data ----------------------------------------------------

  MatchInfo? get _nextMatch {
    final upcoming = _matches.where((m) => !m.isPlayed && m.hasTeam(_teamKey)).toList();
    if (upcoming.isEmpty) return null;
    return upcoming.first;
  }

  List<MatchInfo> get _myMatches => _matches.where((m) => m.hasTeam(_teamKey)).toList();

  double? _winProbability(MatchInfo m) {
    if (_oprs.isEmpty) return null;
    final onRed = m.teamOnRed(_teamKey);
    final myAlliance = onRed ? m.redTeams : m.blueTeams;
    final oppAlliance = onRed ? m.blueTeams : m.redTeams;
    double sum(List<String> teams) =>
        teams.fold(0.0, (s, t) => s + (_oprs[t] ?? 0));
    final myScore = sum(myAlliance);
    final oppScore = sum(oppAlliance);
    if (myScore == 0 && oppScore == 0) return null;
    // Simple logistic on OPR-sum difference. Not a real prediction model,
    // just a rough "who looks stronger on paper" estimate.
    final diff = myScore - oppScore;
    return 1 / (1 + math.exp(-diff / 15));
  }

  List<String> _suggestions(MatchInfo m, Duration timeUntil, double? winProb) {
    final tips = <String>[];
    if (!timeUntil.isNegative && timeUntil.inMinutes <= 20) {
      tips.add(
          'Match is coming up soon — get your drive team and a fully charged battery to the queue.');
    } else if (!timeUntil.isNegative) {
      tips.add(
          'You have about ${_formatDuration(timeUntil)} — good time to scout upcoming opponents or double check the robot.');
    }
    if (winProb != null) {
      if (winProb >= 0.62) {
        tips.add('Your alliance looks stronger on paper (OPR-based) — stick to your normal game plan.');
      } else if (winProb <= 0.38) {
        tips.add('This alliance looks tougher on paper — talk through how to maximize your role before the match.');
      } else {
        tips.add('This looks like a close matchup — small mistakes could decide it.');
      }
    } else {
      tips.add('Not enough ranking data yet to estimate this matchup — check back once more matches are played.');
    }
    final onRed = m.teamOnRed(_teamKey);
    final partners = (onRed ? m.redTeams : m.blueTeams)
        .where((t) => t != _teamKey)
        .map((t) => t.replaceFirst('frc', ''))
        .join(', ');
    final opponents = (onRed ? m.blueTeams : m.redTeams)
        .map((t) => t.replaceFirst('frc', ''))
        .join(', ');
    if (partners.isNotEmpty) tips.add('Alliance partner(s): $partners');
    tips.add('Opponents: $opponents');
    return tips;
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) return 'starting now';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  // ---- team / event switching -------------------------------------------

  void _showTeamPrompt({bool firstTime = false}) {
    final ctrl = TextEditingController(text: teamNum ?? '');
    String? error;
    showDialog(
      context: context,
      barrierDismissible: !firstTime,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(firstTime ? 'Track a team' : 'Change team'),
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
            if (!firstTime)
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Yellor),
              onPressed: () async {
                final t = ctrl.text.trim();
                if (t.isEmpty) {
                  setD(() => error = 'Enter a team number');
                  return;
                }
                Navigator.pop(ctx);
                setState(() {
                  teamNum = t;
                  _events = [];
                  _selectedEventKey = null;
                  _matches = [];
                });
                await _loadEvents();
                if (_events.isNotEmpty) {
                  _selectedEventKey =
                      _events.firstWhere((e) => e.isLiveNow, orElse: () => _events.last).key;
                  await _loadEventData();
                } else {
                  setState(() {
                    _isLoading = false;
                    _error = 'No events found for team $t this season';
                  });
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEventPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Choose event', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            ..._events.map((e) => GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _selectedEventKey = e.key);
                    _loadEventData();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      Icon(
                        e.key == _selectedEventKey ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        size: 18,
                        color: e.key == _selectedEventKey ? Yellor : Colors.grey[400],
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(e.name, style: const TextStyle(fontSize: 14))),
                    ]),
                  ),
                )),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                _showTeamPrompt();
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  Icon(Icons.swap_horiz, size: 18, color: Yellor),
                  SizedBox(width: 10),
                  Text('Track a different team', style: TextStyle(fontSize: 14, color: YellorDark)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 248),
      body: SafeArea(
        child: Column(children: [_topBar(), Expanded(child: _body())]),
      ),
    );
  }

  Widget _topBar() {
    final eventName = _events.where((e) => e.key == _selectedEventKey).map((e) => e.name).firstOrNull;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: YellorLight, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.arrow_back, color: Yellor, size: 17),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(teamNum != null ? 'Team $teamNum match notifier' : 'Match notifier',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              if (eventName != null)
                Text(eventName, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ]),
          ),
          if (_pushState != 'unsupported') ...[
            GestureDetector(
              onTap: _selectedEventKey == null ? null : _togglePush,
              child: Container(
                width: 34,
                height: 34,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: _pushState == 'subscribed' ? Yellor : YellorLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _pushBusy
                    ? const Padding(
                        padding: EdgeInsets.all(9),
                        child: CircularProgressIndicator(strokeWidth: 2, color: Yellor),
                      )
                    : Icon(
                        _pushState == 'subscribed'
                            ? Icons.notifications_active
                            : Icons.notifications_none,
                        color: _pushState == 'subscribed' ? Colors.white : Yellor,
                        size: 18,
                      ),
              ),
            ),
          ],
          GestureDetector(
            onTap: _events.isEmpty ? null : _showEventPicker,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: YellorLight, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.more_horiz, color: Yellor, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Yellor));
    if (_error != null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_error!, style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => teamNum == null ? _showTeamPrompt(firstTime: true) : _loadEventData(),
            child: const Text('Try again', style: TextStyle(color: Yellor, fontWeight: FontWeight.w500)),
          ),
        ]),
      );
    }
    if (_myMatches.isEmpty) {
      return Center(
        child: Text('No matches found for this event yet.', style: TextStyle(color: Colors.grey[600])),
      );
    }
    return RefreshIndicator(color: Yellor, onRefresh: _loadEventData, child: _list());
  }

  Widget _list() {
    final next = _nextMatch;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (next != null) ...[
          _countdownCard(next),
          const SizedBox(height: 10),
          _suggestionsCard(next),
          const SizedBox(height: 16),
        ] else
          _doneCard(),
        _statusCard(),
        const SizedBox(height: 16),
        Text('Match schedule', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey[600])),
        const SizedBox(height: 8),
        ..._myMatches.map(_matchTile),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _countdownCard(MatchInfo m) {
    final time = m.bestTime;
    final timeUntil = time != null ? time.difference(DateTime.now()) : null;
    final winProb = _winProbability(m);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Yellor, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NEXT MATCH',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.8), letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(m.label, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 6),
          Text(
            timeUntil == null
                ? 'Time not posted yet'
                : (timeUntil.isNegative ? 'Should be on the field now' : 'in ${_formatDuration(timeUntil)}'),
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

  Widget _suggestionsCard(MatchInfo m) {
    final time = m.bestTime;
    final timeUntil = time != null ? time.difference(DateTime.now()) : Duration.zero;
    final winProb = _winProbability(m);
    final tips = _suggestions(m, timeUntil, winProb);
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
            Icon(Icons.lightbulb_outline, color: YellorDark, size: 18),
            SizedBox(width: 8),
            Text('Before this match', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: YellorDark)),
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

  Widget _doneCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: YellorLight, borderRadius: BorderRadius.circular(20)),
      child: const Row(children: [
        Icon(Icons.check_circle_outline, color: YellorDark),
        SizedBox(width: 10),
        Expanded(child: Text('No more matches on the schedule for this event yet.',
            style: TextStyle(fontSize: 13, color: YellorDark))),
      ]),
    );
  }

  Widget _statusCard() {
    final s = _myStatus;
    if (s == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          _statChip('Rank', s.rank != null ? '${s.rank}${s.numTeams != null ? '/${s.numTeams}' : ''}' : '—'),
          _statChip('Record', '${s.wins}-${s.losses}-${s.ties}'),
          _statChip('Matches left', '${_myMatches.where((m) => !m.isPlayed).length}'),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value) {
    return Expanded(
      child: Column(children: [
        Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ]),
    );
  }

  Widget _matchTile(MatchInfo m) {
    final onRed = m.teamOnRed(_teamKey);
    final won = m.isPlayed
        ? ((onRed && m.redScore! > m.blueScore!) || (!onRed && m.blueScore! > m.redScore!))
        : null;
    final tied = m.isPlayed && m.redScore == m.blueScore;
    final statusColor = !m.isPlayed
        ? grayChar
        : (tied ? Colors.orange : (won == true ? greenChar : redChar));
    final statusText = !m.isPlayed
        ? (m.bestTime != null ? _clockLabel(m.bestTime!) : 'Not scheduled')
        : (tied ? 'TIE ${m.redScore}-${m.blueScore}' : (won == true ? 'WON' : 'LOST') + ' ${onRed ? m.redScore : m.blueScore}-${onRed ? m.blueScore : m.redScore}');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07), width: 0.5),
      ),
      child: Row(children: [
        Container(
          width: 10,
          height: 40,
          decoration: BoxDecoration(color: onRed ? redChar : blueChar, borderRadius: BorderRadius.circular(6)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(statusText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor)),
          ]),
        ),
      ]),
    );
  }

  String _clockLabel(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}