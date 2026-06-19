class RacePlayer {
  const RacePlayer({
    required this.name,
    required this.initials,
    required this.progress,
  });

  final String name;
  final String initials;
  final int progress;
}

class Race {
  const Race({
    required this.id,
    required this.title,
    required this.description,
    required this.daysLeft,
    required this.proof,
    required this.players,
    this.note,
  });

  final String id;
  final String title;
  final String description;
  final int daysLeft;
  final String proof;
  final List<RacePlayer> players;
  final String? note;

  RacePlayer get leader {
    final sorted = [...players]
      ..sort((a, b) => b.progress.compareTo(a.progress));
    return sorted.first;
  }
}
