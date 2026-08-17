/// Data models for the match notifier feature. These map directly onto
/// The Blue Alliance's API shape (proxied through our backend's
/// /match/events and /match/data routes) so parsing stays in one place.

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
      redScore != null && redScore! >= 0 && blueScore != null && blueScore! >= 0;

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

class MatchEvent {
  final String key;
  final String name;
  final DateTime? startDate;
  final DateTime? endDate;

  const MatchEvent({required this.key, required this.name, this.startDate, this.endDate});

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
  bool operator ==(Object other) => other is EventTeam && other.teamKey == teamKey;

  @override
  int get hashCode => teamKey.hashCode;
}