import 'participant.dart';

/// The categories shown as the horizontal chip row at the top of the Arena.
enum ChallengeCategory {
  fitness,
  learning,
  habits,
  custom;

  String get label => switch (this) {
        ChallengeCategory.fitness => 'Fitness',
        ChallengeCategory.learning => 'Learning',
        ChallengeCategory.habits => 'Habits',
        ChallengeCategory.custom => 'Custom',
      };
}

/// What the prize pool is denominated in.
enum PrizeType { usd, glory }

/// Lifecycle of a challenge from the perspective of the viewing user.
enum ChallengeStatus { upcoming, active, completed, abandoned }

/// Core domain model.
class Challenge {
  const Challenge({
    required this.id,
    required this.title,
    required this.category,
    required this.participants,
    required this.startDate,
    required this.endDate,
    this.entryFee = 0,
    this.prizePool = 0,
    this.prizeType = PrizeType.usd,
    this.isHot = false,
    this.status = ChallengeStatus.active,
    this.description,
    this.heroImageUrl,
  });

  final String id;
  final String title;
  final ChallengeCategory category;
  final List<Participant> participants;
  final DateTime startDate;
  final DateTime endDate;
  final double entryFee;
  final double prizePool;
  final PrizeType prizeType;
  final bool isHot;
  final ChallengeStatus status;
  final String? description;
  final String? heroImageUrl;

  Duration get timeLeft => endDate.difference(DateTime.now());

  int get daysLeft {
    final left = timeLeft.inDays;
    return left < 0 ? 0 : left;
  }

  Challenge copyWith({
    String? id,
    String? title,
    ChallengeCategory? category,
    List<Participant>? participants,
    DateTime? startDate,
    DateTime? endDate,
    double? entryFee,
    double? prizePool,
    PrizeType? prizeType,
    bool? isHot,
    ChallengeStatus? status,
    String? description,
    String? heroImageUrl,
  }) {
    return Challenge(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      participants: participants ?? this.participants,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      entryFee: entryFee ?? this.entryFee,
      prizePool: prizePool ?? this.prizePool,
      prizeType: prizeType ?? this.prizeType,
      isHot: isHot ?? this.isHot,
      status: status ?? this.status,
      description: description ?? this.description,
      heroImageUrl: heroImageUrl ?? this.heroImageUrl,
    );
  }
}
