#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "lib/features/arena/presentation/arena_screen.dart"
text = path.read_text()
lines = text.splitlines(keepends=True)

start = None
end = None
for i, line in enumerate(lines):
    if start is None and "Arena header" in line:
        start = i
    if start is not None and end is None and line.startswith("class _BlinkingDot"):
        end = i
        break

if start is None or end is None:
    raise SystemExit(f"markers not found start={start} end={end}")

replacement = '''// ── Arena header ──────────────────────────────────────────────────────────────

class _ArenaHeader extends StatelessWidget {
  const _ArenaHeader({
    required this.initials,
    required this.onProfileTap,
    required this.onNotificationsTap,
    this.photoUrl,
    this.hasActivity = false,
  });

  final String initials;
  final String? photoUrl;
  final VoidCallback onProfileTap;
  final VoidCallback onNotificationsTap;
  final bool hasActivity;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: NuvoColors.border),
          boxShadow: AppShadows.hardShadow3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PressableScale(
              onTap: onProfileTap,
              child: NuvoAvatar(
                initials: initials,
                photoUrl: photoUrl,
                size: 34,
                bgColor: NuvoColors.navy,
                textColor: NuvoColors.white,
                borderColor: NuvoColors.border,
                borderWidth: 1,
              ),
            ),
            const SizedBox(width: 8),
            PressableScale(
              onTap: onNotificationsTap,
              child: SizedBox(
                width: 34,
                height: 34,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(
                      Icons.notifications_none_rounded,
                      color: NuvoColors.navy,
                      size: 22,
                    ),
                    if (hasActivity)
                      Positioned(
                        top: 5,
                        right: 5,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: NuvoColors.actionBlue,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: NuvoColors.white,
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

'''

new_lines = lines[:start] + [replacement] + lines[end:]
path.write_text(''.join(new_lines))
print(f"fixed header lines {start+1}-{end} -> new block")
