class MockTeam {
  final String number;
  final String name;
  final double epaTotal;
  final double epaAuto;
  final double epaTeleop;
  final double epaEndgame;
  final int rank;
  final int wins;
  final int losses;
  final int ties;
  final String nextMatchLabel;
  final String nextMatchTime;

  const MockTeam({
    required this.number,
    required this.name,
    required this.epaTotal,
    required this.epaAuto,
    required this.epaTeleop,
    required this.epaEndgame,
    required this.rank,
    required this.wins,
    required this.losses,
    required this.ties,
    required this.nextMatchLabel,
    required this.nextMatchTime,
  });
}

const List<MockTeam> mockTeams = [
  MockTeam(number: '254', name: 'The Cheesy Poofs', epaTotal: 42.8, epaAuto: 9.2, epaTeleop: 26.4, epaEndgame: 7.2, rank: 1, wins: 11, losses: 1, ties: 0, nextMatchLabel: 'Quals 32', nextMatchTime: 'Today, 1:45 PM'),
  MockTeam(number: '2056', name: 'OP Robotics', epaTotal: 40.2, epaAuto: 8.8, epaTeleop: 25.1, epaEndgame: 6.3, rank: 2, wins: 10, losses: 2, ties: 0, nextMatchLabel: 'Quals 28', nextMatchTime: 'Today, 12:50 PM'),
  MockTeam(number: '1323', name: 'MadTown Robotics', epaTotal: 38.1, epaAuto: 8.0, epaTeleop: 24.6, epaEndgame: 5.5, rank: 3, wins: 10, losses: 2, ties: 0, nextMatchLabel: 'Quals 30', nextMatchTime: 'Today, 1:20 PM'),
  MockTeam(number: '1114', name: 'Simbotics', epaTotal: 37.5, epaAuto: 7.9, epaTeleop: 23.8, epaEndgame: 5.8, rank: 4, wins: 9, losses: 3, ties: 0, nextMatchLabel: 'Quals 31', nextMatchTime: 'Today, 1:30 PM'),
  MockTeam(number: '148', name: 'Robowranglers', epaTotal: 36.0, epaAuto: 7.5, epaTeleop: 23.0, epaEndgame: 5.5, rank: 5, wins: 9, losses: 3, ties: 0, nextMatchLabel: 'Quals 29', nextMatchTime: 'Today, 1:05 PM'),
  MockTeam(number: '971', name: 'Spartan Robotics', epaTotal: 34.9, epaAuto: 7.0, epaTeleop: 22.5, epaEndgame: 5.4, rank: 6, wins: 8, losses: 3, ties: 1, nextMatchLabel: 'Quals 34', nextMatchTime: 'Today, 2:20 PM'),
  MockTeam(number: '4388', name: 'Ridgebotics', epaTotal: 29.4, epaAuto: 6.1, epaTeleop: 18.9, epaEndgame: 4.4, rank: 7, wins: 8, losses: 4, ties: 0, nextMatchLabel: 'Quals 33', nextMatchTime: 'Today, 2:05 PM'),
  MockTeam(number: '2910', name: 'Jack in the Bot', epaTotal: 28.3, epaAuto: 5.9, epaTeleop: 18.0, epaEndgame: 4.4, rank: 8, wins: 8, losses: 4, ties: 0, nextMatchLabel: 'Quals 35', nextMatchTime: 'Today, 2:35 PM'),
  MockTeam(number: '3061', name: 'Huskie Robotics', epaTotal: 27.2, epaAuto: 5.5, epaTeleop: 17.5, epaEndgame: 4.2, rank: 9, wins: 7, losses: 5, ties: 0, nextMatchLabel: 'Quals 27', nextMatchTime: 'Today, 12:35 PM'),
  MockTeam(number: '3476', name: 'Code Orange', epaTotal: 25.6, epaAuto: 5.2, epaTeleop: 16.4, epaEndgame: 4.0, rank: 10, wins: 7, losses: 5, ties: 0, nextMatchLabel: 'Quals 36', nextMatchTime: 'Today, 2:50 PM'),
];

MockTeam? findMockTeam(String number) {
  for (final team in mockTeams) {
    if (team.number == number) return team;
  }
  return null;
}