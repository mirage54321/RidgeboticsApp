import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../push_notifications.dart';
import 'match_models.dart';

/// All the state for the single team this app follows: its events for the
/// season, which event is currently selected, that event's match
/// schedule/OPRs/status, and push-notification state.
class MyTeam {
  final String teamNumber;

  List<MatchEvent> events = [];
  String? selectedEventKey;

  List<MatchInfo> matches = [];
  Map<String, double> oprs = {};
  TeamStatus? myStatus;

  bool isLoading = false;
  bool loadingEvents = false;
  String? error;

  /// 'unsupported' | 'unsubscribed' | 'subscribed'
  String pushState = 'unsupported';
  bool pushBusy = false;

  MyTeam(this.teamNumber);

  String get teamKey => 'frc$teamNumber';

  MatchEvent? get selectedEvent =>
      events.where((e) => e.key == selectedEventKey).firstOrNull;

  List<MatchInfo> get myMatches => matches.where((m) => m.hasTeam(teamKey)).toList();

  MatchInfo? get nextMatch {
    final upcoming = myMatches.where((m) => !m.isPlayed).toList();
    return upcoming.isEmpty ? null : upcoming.first;
  }

  /// The next event (by start date) that hasn't ended yet — used so the
  /// "My Team" tab can say "here's what's next" even before matches for
  /// that event are posted.
  MatchEvent? get nextUpcomingEvent {
    final now = DateTime.now();
    final upcoming = events.where((e) => e.endDate == null || !e.endDate!.isBefore(now)).toList()
      ..sort((a, b) => (a.startDate ?? DateTime(2100)).compareTo(b.startDate ?? DateTime(2100)));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  /// Every team seen in the currently-loaded OPR map, sorted by OPR
  /// descending. Powers the "who's at this event" style lookups.
  List<EventTeam> get eventTeams {
    final teams = oprs.entries.map((e) => EventTeam(teamKey: e.key, opr: e.value)).toList();
    teams.sort((a, b) => b.opr.compareTo(a.opr));
    return teams;
  }
}

/// Owns the single team the person follows, plus feature-level helpers
/// (global events list, per-event roster, matchup math) shared across
/// tabs via `MatchScope`.
class MatchDataController extends ChangeNotifier {
  static const String backendBase = 'https://ridgeboticsapp.onrender.com';

  MyTeam? myTeam;

  /// True only while the app is doing its first-launch load.
  bool isLoading = true;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('my_team_number');

    if (stored == null || stored.isEmpty) {
      isLoading = false;
      notifyListeners();
      return;
    }

    myTeam = MyTeam(stored);
    notifyListeners();

    await _bootstrap(myTeam!);
    isLoading = false;
    notifyListeners();
  }

  /// Sets (or replaces) the single team this app follows.
  Future<void> setMyTeam(String teamNumber) async {
    final number = teamNumber.trim();
    if (number.isEmpty) return;

    myTeam = MyTeam(number);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('my_team_number', number);

    await _bootstrap(myTeam!);
    notifyListeners();
  }

  Future<void> clearMyTeam() async {
    myTeam = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('my_team_number');
    notifyListeners();
  }

  Future<void> _bootstrap(MyTeam t) async {
    await _loadEventsFor(t, silent: true);
    if (t.events.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final savedEvent = prefs.getString('my_team_event_${t.teamNumber}');
    t.selectedEventKey = (savedEvent != null && t.events.any((e) => e.key == savedEvent))
        ? savedEvent
        : t.events.firstWhere((e) => e.isLiveNow, orElse: () => t.events.last).key;

    await _loadEventDataFor(t);
    await _refreshPushState(t);
  }

  Future<void> setSelectedEvent(String eventKey) async {
    final t = myTeam;
    if (t == null) return;
    t.selectedEventKey = eventKey;
    notifyListeners();

    await _loadEventDataFor(t);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('my_team_event_${t.teamNumber}', eventKey);

    await _refreshPushState(t);
    notifyListeners();
  }

  Future<void> refresh() async {
    final t = myTeam;
    if (t == null) return;
    await _loadEventDataFor(t);
  }

  Future<void> refreshEvents() async {
    final t = myTeam;
    if (t == null) return;
    await _loadEventsFor(t);
  }

  Future<void> _loadEventsFor(MyTeam t, {bool silent = false}) async {
    t.loadingEvents = true;
    t.error = null;
    if (!silent) notifyListeners();

    try {
      final year = DateTime.now().year;
      final uri = Uri.parse('$backendBase/match/events?teamNumber=${t.teamNumber}&year=$year');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        t.error = 'Could not load events for that team';
        t.loadingEvents = false;
        notifyListeners();
        return;
      }
      final list = jsonDecode(res.body) as List<dynamic>;
      final loaded = list.map((e) => MatchEvent.fromJson(e as Map<String, dynamic>)).toList();
      loaded.sort((a, b) => (a.startDate ?? DateTime(2000)).compareTo(b.startDate ?? DateTime(2000)));
      t.events = loaded;
      t.error = loaded.isEmpty ? 'No events found for team ${t.teamNumber} this season' : null;
      t.loadingEvents = false;
      notifyListeners();
    } catch (_) {
      t.error = 'Could not connect, try again';
      t.loadingEvents = false;
      notifyListeners();
    }
  }

  Future<void> _loadEventDataFor(MyTeam t) async {
    if (t.selectedEventKey == null) return;
    t.isLoading = true;
    t.error = null;
    notifyListeners();

    try {
      final uri = Uri.parse(
          '$backendBase/match/data?teamNumber=${t.teamNumber}&eventKey=${t.selectedEventKey}');
      final res = await http.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        t.error = 'Could not load match data';
        t.isLoading = false;
        notifyListeners();
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

      t.matches = loadedMatches;
      t.oprs = loadedOprs;
      t.myStatus = TeamStatus.fromJson(data['status'] as Map<String, dynamic>?);
      t.isLoading = false;
      notifyListeners();
    } catch (_) {
      t.error = 'Could not connect, try again';
      t.isLoading = false;
      notifyListeners();
    }
  }

  // ---- win probability / suggestions -------------------------------------

  double? winProbabilityFor(MyTeam t, MatchInfo m) {
    final onRed = m.teamOnRed(t.teamKey);
    final myAlliance = onRed ? m.redTeams : m.blueTeams;
    final oppAlliance = onRed ? m.blueTeams : m.redTeams;
    return winProbabilityBetween(t, myAlliance, oppAlliance);
  }

  /// Logistic curve on summed-OPR difference. This is a rough "who looks
  /// stronger on paper" estimate, not a real predictive model — FRC
  /// doesn't publish true win probabilities.
  double? winProbabilityBetween(MyTeam t, List<String> allianceA, List<String> allianceB) {
    if (t.oprs.isEmpty) return null;
    double sum(List<String> teamKeys) => teamKeys.fold(0.0, (s, k) => s + (t.oprs[k] ?? 0));
    final a = sum(allianceA);
    final b = sum(allianceB);
    if (a == 0 && b == 0) return null;
    final diff = a - b;
    return 1 / (1 + math.exp(-diff / 15));
  }

  List<String> suggestionsFor(MyTeam t, MatchInfo m, Duration timeUntil, double? winProb) {
    final tips = <String>[];
    if (!timeUntil.isNegative && timeUntil.inMinutes <= 20) {
      tips.add('Match is coming up soon — get your drive team and a fully charged battery to the queue.');
    } else if (!timeUntil.isNegative) {
      tips.add('You have about ${formatDuration(timeUntil)} — good time to scout upcoming opponents or double check the robot.');
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
    final onRed = m.teamOnRed(t.teamKey);
    final partners = (onRed ? m.redTeams : m.blueTeams)
        .where((k) => k != t.teamKey)
        .map((k) => k.replaceFirst('frc', ''))
        .join(', ');
    final opponents =
        (onRed ? m.blueTeams : m.redTeams).map((k) => k.replaceFirst('frc', '')).join(', ');
    if (partners.isNotEmpty) tips.add('Alliance partner(s): $partners');
    tips.add('Opponents: $opponents');
    return tips;
  }

  String formatDuration(Duration d) {
    if (d.isNegative) return 'starting now';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  // ---- global events (for the Events tab) ---------------------------------

  /// Every FRC event roughly six months back through six months forward,
  /// across whichever season years overlap that window.
  Future<List<MatchEvent>> loadGlobalEvents() async {
    final now = DateTime.now();
    final years = {now.year - 1, now.year, now.year + 1};
    final all = <MatchEvent>[];

    for (final y in years) {
      try {
        final uri = Uri.parse('$backendBase/events?year=$y');
        final res = await http.get(uri).timeout(const Duration(seconds: 20));
        if (res.statusCode == 200) {
          final list = jsonDecode(res.body) as List<dynamic>;
          all.addAll(list.map((e) => MatchEvent.fromJson(e as Map<String, dynamic>)));
        }
      } catch (_) {
        // Skip that year on failure — the others may still load fine.
      }
    }

    final from = now.subtract(const Duration(days: 182));
    final to = now.add(const Duration(days: 182));
    final inRange = all.where((e) {
      final s = e.startDate;
      final en = e.endDate ?? s;
      if (s == null || en == null) return false;
      return !en.isBefore(from) && !s.isAfter(to);
    }).toList();

    inRange.sort((a, b) => (a.startDate ?? DateTime(2100)).compareTo(b.startDate ?? DateTime(2100)));
    return inRange;
  }

  // ---- event roster ("people scheduled for it") ---------------------------

  Future<List<String>> loadRoster(String teamNumber, String eventKey) async {
    try {
      final uri = Uri.parse('$backendBase/event/roster?teamNumber=$teamNumber&eventKey=$eventKey');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['people'] as List<dynamic>? ?? []).cast<String>();
    } catch (_) {
      return [];
    }
  }

  Future<bool> addToRoster(String teamNumber, String passcode, String eventKey, String name) async {
    try {
      final uri = Uri.parse('$backendBase/event/roster/add');
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'teamNumber': teamNumber,
              'passcode': passcode,
              'eventKey': eventKey,
              'name': name,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeFromRoster(String teamNumber, String passcode, String eventKey, String name) async {
    try {
      final uri = Uri.parse('$backendBase/event/roster/remove');
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'teamNumber': teamNumber,
              'passcode': passcode,
              'eventKey': eventKey,
              'name': name,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ---- push notifications --------------------------------------------------

  Future<void> _refreshPushState(MyTeam t) async {
    t.pushState = await PushNotifications.subscriptionState();
    notifyListeners();
  }

  Future<bool> togglePush() async {
    final t = myTeam;
    if (t == null || t.pushBusy || t.selectedEventKey == null) return false;
    t.pushBusy = true;
    notifyListeners();

    final wasSubscribed = t.pushState == 'subscribed';
    final ok = wasSubscribed
        ? await PushNotifications.unsubscribe()
        : await PushNotifications.subscribe(t.teamNumber, t.selectedEventKey!);

    await _refreshPushState(t);
    t.pushBusy = false;
    notifyListeners();
    return ok;
  }
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}