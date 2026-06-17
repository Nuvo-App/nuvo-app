/// A single competitor inside a [Challenge].
class Participant {
  const Participant({
    required this.id,
    required this.username,
    this.avatarUrl,
    this.progress = 0,
  });

  final String id;
  final String username;
  final String? avatarUrl;

  /// 0–100, used to render the per-participant progress ring.
  final int progress;

  Participant copyWith({
    String? id,
    String? username,
    String? avatarUrl,
    int? progress,
  }) {
    return Participant(
      id: id ?? this.id,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      progress: progress ?? this.progress,
    );
  }
}
