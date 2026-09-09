import '../../social/domain/nuvo_destination.dart';

class NuvoNotification {
  const NuvoNotification({
    required this.id,
    required this.category,
    required this.title,
    required this.createdAt,
    required this.read,
    this.body,
    this.actorName,
    this.actorPhotoUrl,
    this.destination,
  });

  final String id;
  final String category;
  final String title;
  final String? body;
  final DateTime createdAt;
  final bool read;
  final String? actorName;
  final String? actorPhotoUrl;

  /// Resolved from the server's structured descriptor — never a route string.
  final NuvoDestination? destination;

  NuvoNotification copyWith({bool? read}) => NuvoNotification(
        id: id,
        category: category,
        title: title,
        body: body,
        createdAt: createdAt,
        read: read ?? this.read,
        actorName: actorName,
        actorPhotoUrl: actorPhotoUrl,
        destination: destination,
      );

  factory NuvoNotification.fromJson(Map<String, dynamic> j) {
    final actor = j['actor'] as Map<String, dynamic>?;
    return NuvoNotification(
      id: j['id'] as String,
      category: j['category'] as String? ?? 'unknown',
      title: j['title'] as String? ?? '',
      body: j['body'] as String?,
      createdAt:
          DateTime.tryParse(j['createdAt'] as String? ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
      read: j['read'] as bool? ?? false,
      actorName: actor?['displayName'] as String?,
      actorPhotoUrl: actor?['profilePhotoUrl'] as String?,
      destination: NuvoDestination.fromDescriptor(
        j['destination'] as Map<String, dynamic>?,
      ),
    );
  }
}

class NotificationPage {
  const NotificationPage({
    required this.items,
    required this.unreadCount,
    this.nextCursor,
  });

  final List<NuvoNotification> items;
  final int unreadCount;
  final String? nextCursor;

  factory NotificationPage.fromJson(Map<String, dynamic> j) => NotificationPage(
        items: (j['notifications'] as List<dynamic>? ?? [])
            .map((e) => NuvoNotification.fromJson(e as Map<String, dynamic>))
            .toList(),
        unreadCount: (j['unreadCount'] as num?)?.toInt() ?? 0,
        nextCursor: j['nextCursor'] as String?,
      );
}
