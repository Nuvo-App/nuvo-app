import 'package:flutter/material.dart';

import 'track_view_fixture.dart';

class TrackViewRacer extends StatelessWidget {
  const TrackViewRacer({
    super.key,
    required this.participant,
    required this.rank,
    required this.isFocused,
    required this.depth,
    required this.isCurrentUser,
    required this.onTap,
  });

  final TrackViewParticipantData participant;
  final int rank;
  final bool isFocused;
  final double depth;
  final bool isCurrentUser;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = isFocused ? 54.0 : 44.0;
    final shadowAlpha = (0.22 + depth * 0.22).clamp(0.0, 1.0);
    final shadowOffset = Offset(0, 5 + depth * 10);
    final borderColor = isFocused
        ? const Color(0xFFF3F8FF)
        : Color.lerp(const Color(0xFF6F8DB5), const Color(0xFFD9EAFF), depth)!;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        scale: isFocused ? 1 : 0.94,
        child: Semantics(
          label:
              '${participant.displayName}, rank $rank, ${participant.completedAmount}',
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCurrentUser
                        ? const Color(0xFF2879F6)
                        : const Color(0xFFDAE9FF),
                    border: Border.all(
                      color: borderColor,
                      width: isFocused ? 3 : 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: shadowAlpha),
                        blurRadius: 10 + depth * 14,
                        offset: shadowOffset,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _initials(participant.displayName),
                      style: TextStyle(
                        color: isCurrentUser
                            ? Colors.white
                            : const Color(0xFF102B4A),
                        fontSize: isFocused ? 16 : 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: -5,
                  top: -7,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF102B4A),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 4,
                      ),
                      child: Text(
                        '#$rank',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }
}
