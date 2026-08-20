// Data models for the match notifier feature. These map directly onto
// The Blue Alliance's API shape (proxied through our backend's
// /match/events and /match/data routes) so parsing stays in one place.

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

  const MatchInfo({
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
      redScore != null &&
      redScore! >= 0 &&
      blueScore != null &&
      blueScore! >= 0;

  bool teamOnRed(String teamKey) => redTeams.contains(teamKey);
  bool teamOnBlue(String teamKey) => blueTeams.contains(teamKey);
  bool hasTeam(String teamKey) => teamOnRed(teamKey) || teamOnBlue(teamKey);

  /// Best time available for sorting/countdown purposes: predicted time
  /// falls back to actual time, since most matches never get an
  /// actual_time posted until after they're already done.
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

/// A team's ranking/record at a single event.
class TeamStatus {
  final int? rank;
  final int? numTeams;
  final int wins;
  final int losses;
  final int ties;

  const TeamStatus({
    this.rank,
    this.numTeams,
    required this.wins,
    required this.losses,
    required this.ties,
  });

  factory TeamStatus.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const TeamStatus(wins: 0, losses: 0, ties: 0);
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

/// A playoff alliance at an event: its picks in draft order (captain
/// first) and whether it won the whole event. Powers the event-winner
/// summary on the events page for past competitions.
class EventAlliance {
  final List<String> picks;
  final bool won;
  final String? level;

  const EventAlliance({required this.picks, required this.won, this.level});

  /// Reached the finals level but didn't win — the event's 2nd place
  /// alliance.
  bool get isRunnerUp => level == 'f' && !won;

  factory EventAlliance.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as Map<String, dynamic>?;
    return EventAlliance(
      picks: (json['picks'] as List<dynamic>? ?? []).cast<String>(),
      won: (status?['status'] as String?) == 'won',
      level: status?['level'] as String?,
    );
  }
}

class MatchEvent {
  final String key;
  final String name;
  final DateTime? startDate;
  final DateTime? endDate;
  final String location;

  const MatchEvent({
    required this.key,
    required this.name,
    this.startDate,
    this.endDate,
    this.location = '',
  });

  factory MatchEvent.fromJson(Map<String, dynamic> json) {
    return MatchEvent(
      key: json['key'] as String? ?? '',
      name: json['name'] as String? ?? json['key'] as String? ?? 'Event',
      startDate: json['start_date'] != null
          ? DateTime.tryParse(json['start_date'])
          : null,
      endDate: json['end_date'] != null
          ? DateTime.tryParse(json['end_date'])
          : null,
      location: [json['city'], json['state_prov'], json['country']]
          .whereType<String>()
          .where((part) => part.isNotEmpty)
          .join(', '),
    );
  }

  bool get isLiveNow {
    final now = DateTime.now();
    if (startDate == null || endDate == null) return false;
    final end = endDate!.add(const Duration(days: 1));
    return now.isAfter(startDate!.subtract(const Duration(days: 1))) &&
        now.isBefore(end);
  }
}

/// A single FRC team competing at an event, derived from the OPR map
/// returned alongside match data. Powers the matchup simulator's team
/// pickers without needing a separate backend call.
class EventTeam {
  final String teamKey; // e.g. "frc254"
  final double opr;

  const EventTeam({required this.teamKey, required this.opr});

  String get teamNumber => teamKey.replaceFirst('frc', '');

  // Value equality on teamKey — without this, two EventTeam instances for
  // the same team (built on different rebuilds from the same OPR map)
  // would compare unequal, breaking List.remove/contains in the simulator.
  @override
  bool operator ==(Object other) =>
      other is EventTeam && other.teamKey == teamKey;

  @override
  int get hashCode => teamKey.hashCode;
}

/// A team competing at a specific event, used by the event detail screen
/// to show the full competitor list (not just teams with OPR data, and
/// not scoped to "my team"'s events).
class EventTeamInfo {
  final String teamNumber;
  final String name;

  const EventTeamInfo({required this.teamNumber, required this.name});

  factory EventTeamInfo.fromJson(Map<String, dynamic> json) {
    final number = json['team_number']?.toString() ?? '';
    return EventTeamInfo(
      teamNumber: number,
      name: json['name'] as String? ?? 'Team $number',
    );
  }
}

/// One team's ranking and OPR at the currently selected event.
class TeamStats {
  final String teamNumber;
  final String name;
  final double opr;
  final int rank;
  final int wins;
  final int losses;
  final int ties;

  const TeamStats({
    required this.teamNumber,
    required this.name,
    required this.opr,
    required this.rank,
    required this.wins,
    required this.losses,
    required this.ties,
  });

  factory TeamStats.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
    final number = json['team_number']?.toString() ?? '';
    return TeamStats(
      teamNumber: number,
      name: json['name'] as String? ?? 'Team $number',
      opr: asDouble(json['opr']),
      rank: json['rank'] as int? ?? 0,
      wins: json['wins'] as int? ?? 0,
      losses: json['losses'] as int? ?? 0,
      ties: json['ties'] as int? ?? 0,
    );
  }
}

/// An award a team won at a specific event (e.g. "Regional Winner",
/// "Rookie All Star").
class TeamAward {
  final String name;
  final String eventName;
  final int year;

  const TeamAward({
    required this.name,
    required this.eventName,
    required this.year,
  });

  factory TeamAward.fromJson(Map<String, dynamic> json) {
    return TeamAward(
      name: json['name'] as String? ?? 'Award',
      eventName: json['event_name'] as String? ?? '',
      year: json['year'] as int? ?? 0,
    );
  }
}

/// How a team placed at one event in a past (or current) season. Powers
/// the "past events" history on the My Team tab.
class PastEventResult {
  final String eventKey;
  final String eventName;
  final int year;
  final int? rank;
  final int? numTeams;
  final List<String> awards;

  const PastEventResult({
    required this.eventKey,
    required this.eventName,
    required this.year,
    this.rank,
    this.numTeams,
    this.awards = const [],
  });

  factory PastEventResult.fromJson(Map<String, dynamic> json) {
    return PastEventResult(
      eventKey: json['event_key'] as String? ?? '',
      eventName:
          json['event_name'] as String? ??
          json['event_key'] as String? ??
          'Event',
      year: json['year'] as int? ?? 0,
      rank: json['rank'] as int?,
      numTeams: json['num_teams'] as int?,
      awards: (json['awards'] as List<dynamic>? ?? []).cast<String>(),
    );
  }
}

/// A team's full competition history/profile, used by the My Team tab:
/// world rank, rookie year (so we can show years competing), every past
/// event with its placement, and every award ever won. Comes from the
/// backend's /team/profile route.
class TeamProfile {
  final String? teamName;
  final int? rookieYear;
  final int? worldRank;
  final List<PastEventResult> pastEvents;
  final List<TeamAward> awards;

  const TeamProfile({
    this.teamName,
    this.rookieYear,
    this.worldRank,
    required this.pastEvents,
    required this.awards,
  });

  factory TeamProfile.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const TeamProfile(pastEvents: [], awards: []);
    final events =
        (json['events'] as List<dynamic>? ?? [])
            .map((e) => PastEventResult.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => b.year.compareTo(a.year));
    final awards = (json['awards'] as List<dynamic>? ?? [])
        .map((a) => TeamAward.fromJson(a as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.year.compareTo(a.year));
    return TeamProfile(
      teamName: json['team_name'] as String?,
      rookieYear: json['rookie_year'] as int?,
      worldRank: json['world_rank'] as int?,
      pastEvents: events,
      awards: awards,
    );
  }

  int? get yearsCompeting {
    if (rookieYear == null) return null;
    return DateTime.now().year - rookieYear! + 1;
  }
}