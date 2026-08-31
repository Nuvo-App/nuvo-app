class TrackViewRaceData {
  const TrackViewRaceData({
    required this.title,
    required this.goal,
    required this.unit,
    required this.currentUserId,
    required this.participants,
  });

  final String title;
  final int goal;
  final String unit;
  final String currentUserId;
  final List<TrackViewParticipantData> participants;
}

class TrackViewParticipantData {
  const TrackViewParticipantData({
    required this.id,
    required this.displayName,
    required this.completedAmount,
    this.avatarUrl,
    this.isCurrentUser = false,
  });

  final String id;
  final String displayName;
  final int completedAmount;
  final String? avatarUrl;
  final bool isCurrentUser;
}

const trackViewFixtures = [
  TrackViewRaceData(
    title: 'First to 100 Pushups',
    goal: 100,
    unit: 'reps',
    currentUserId: 'current-user',
    participants: [
      TrackViewParticipantData(
        id: 'maya',
        displayName: 'Maya',
        completedAmount: 41,
      ),
      TrackViewParticipantData(
        id: 'current-user',
        displayName: 'You',
        completedAmount: 68,
        isCurrentUser: true,
      ),
      TrackViewParticipantData(
        id: 'riley',
        displayName: 'Riley',
        completedAmount: 76,
      ),
    ],
  ),
  TrackViewRaceData(
    title: 'First to 60 Squats',
    goal: 60,
    unit: 'reps',
    currentUserId: 'current-user',
    participants: [
      TrackViewParticipantData(
        id: 'jordan',
        displayName: 'Jordan',
        completedAmount: 19,
      ),
      TrackViewParticipantData(
        id: 'current-user',
        displayName: 'You',
        completedAmount: 28,
        isCurrentUser: true,
      ),
      TrackViewParticipantData(
        id: 'riley',
        displayName: 'Riley',
        completedAmount: 34,
      ),
    ],
  ),
  TrackViewRaceData(
    title: 'First to 40 Lunges',
    goal: 40,
    unit: 'reps',
    currentUserId: 'current-user',
    participants: [
      TrackViewParticipantData(
        id: 'current-user',
        displayName: 'You',
        completedAmount: 0,
        isCurrentUser: true,
      ),
      TrackViewParticipantData(
        id: 'maya',
        displayName: 'Maya',
        completedAmount: 8,
      ),
      TrackViewParticipantData(
        id: 'jordan',
        displayName: 'Jordan',
        completedAmount: 15,
      ),
    ],
  ),
];
