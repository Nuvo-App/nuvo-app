import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'track_view_fixture.dart';
import 'track_view_geometry.dart';
import 'track_view_world.dart';

const _kArenaNavy = Color(0xFF061A33);
const _kArenaNavyDeep = Color(0xFF031327);
const _kArenaBlue = Color(0xFF2F7DFF);
const _kArenaText = Color(0xFFF7FAFF);
const _kArenaMuted = Color(0xFF9EADC0);
const _kPanelText = Color(0xFF1E293B);
const _kPanelMuted = Color(0xFF7D8796);
const _kPanelLine = Color(0xFFE7EBF1);

class ArenaScreen extends StatelessWidget {
  const ArenaScreen({super.key});

  @override
  Widget build(BuildContext context) => const TrackViewScreen();
}

class TrackViewScreen extends StatefulWidget {
  const TrackViewScreen({super.key, this.races = trackViewFixtures});

  final List<TrackViewRaceData> races;

  @override
  State<TrackViewScreen> createState() => _TrackViewScreenState();
}

class _TrackViewScreenState extends State<TrackViewScreen> {
  late final ValueNotifier<TrackViewParticipantData?> _focusedParticipant;
  var _selectedRaceIndex = 0;

  TrackViewRaceData get _race => widget.races[_selectedRaceIndex];

  TrackViewParticipantData get _currentUser => _race.participants.firstWhere(
    (participant) =>
        participant.isCurrentUser || participant.id == _race.currentUserId,
  );

  @override
  void initState() {
    super.initState();
    _focusedParticipant = ValueNotifier(_currentUser);
  }

  @override
  void dispose() {
    _focusedParticipant.dispose();
    super.dispose();
  }

  void _selectRace(int index) {
    setState(() {
      _selectedRaceIndex = index;
      _focusedParticipant.value = _currentUser;
    });
  }

  void _focusParticipant(TrackViewParticipantData participant) {
    if (_focusedParticipant.value?.id != participant.id) {
      _focusedParticipant.value = participant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentProgress = _currentUser.completedAmount;
    final rank = _rankFor(_currentUser);
    final leader = _race.participants.reduce(
      (a, b) => a.completedAmount >= b.completedAmount ? a : b,
    );
    final contextLabel = leader.id == _currentUser.id
        ? '#$rank · You lead the crew'
        : '#$rank · ${leader.completedAmount - _currentUser.completedAmount} ${_race.unit} behind ${leader.displayName}';
    final toFinish = (_race.goal - currentProgress).clamp(0, _race.goal);

    return ColoredBox(
      color: NuvoColors.surface,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final heroHeight = (constraints.maxHeight * 0.62).clamp(
              520.0,
              590.0,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: heroHeight,
                  child: _ArenaHero(
                    race: _race,
                    selectedRaceIndex: _selectedRaceIndex,
                    raceCount: widget.races.length,
                    currentProgress: currentProgress,
                    toFinish: toFinish,
                    contextLabel: contextLabel,
                    focusedParticipant: _focusedParticipant,
                    currentUser: _currentUser,
                    rankFor: _rankFor,
                    onPrevious: _selectedRaceIndex > 0
                        ? () => _selectRace(_selectedRaceIndex - 1)
                        : null,
                    onNext: _selectedRaceIndex < widget.races.length - 1
                        ? () => _selectRace(_selectedRaceIndex + 1)
                        : null,
                    onFocusParticipant: _focusParticipant,
                    onSubmitProof: () {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Verification will be connected in the next gate.',
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: _StandingsPanel(
                    race: _race,
                    onViewStandings: () {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(
                          content: Text('Standings will connect here later.'),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  int _rankFor(TrackViewParticipantData participant) =>
      _race.participants
          .where(
            (candidate) =>
                candidate.completedAmount > participant.completedAmount,
          )
          .length +
      1;
}

class _ArenaHero extends StatelessWidget {
  const _ArenaHero({
    required this.race,
    required this.selectedRaceIndex,
    required this.raceCount,
    required this.currentProgress,
    required this.toFinish,
    required this.contextLabel,
    required this.focusedParticipant,
    required this.currentUser,
    required this.rankFor,
    required this.onPrevious,
    required this.onNext,
    required this.onFocusParticipant,
    required this.onSubmitProof,
  });

  final TrackViewRaceData race;
  final int selectedRaceIndex;
  final int raceCount;
  final int currentProgress;
  final int toFinish;
  final String contextLabel;
  final ValueNotifier<TrackViewParticipantData?> focusedParticipant;
  final TrackViewParticipantData currentUser;
  final int Function(TrackViewParticipantData participant) rankFor;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<TrackViewParticipantData> onFocusParticipant;
  final VoidCallback onSubmitProof;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _kArenaNavy,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF08203F), _kArenaNavyDeep],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _ArenaBackdropPainter())),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ArenaHeader(
                  index: selectedRaceIndex,
                  count: raceCount,
                  onPrevious: onPrevious,
                  onNext: onNext,
                ),
                const SizedBox(height: 28),
                const Text(
                  'Your next move',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _kArenaText,
                    fontSize: 31,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  race.title,
                  key: const ValueKey('track-view-title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _kArenaMuted,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 22),
                _ProgressReadout(
                  currentProgress: currentProgress,
                  goal: race.goal,
                  unit: race.unit,
                ),
                const SizedBox(height: 9),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$toFinish',
                        style: const TextStyle(
                          color: _kArenaBlue,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const TextSpan(text: ' to the finish line'),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _kArenaMuted,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  contextLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF9FC8FF),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ClipRect(
                    child: TrackViewWorld(
                      race: race,
                      focusedParticipant: focusedParticipant,
                      onFocusParticipant: onFocusParticipant,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                ValueListenableBuilder<TrackViewParticipantData?>(
                  valueListenable: focusedParticipant,
                  builder: (context, participant, _) {
                    final active = participant ?? currentUser;
                    return Text(
                      key: const ValueKey('track-view-focused-racer'),
                      '${active.displayName} · #${rankFor(active)} · ${active.completedAmount} / ${race.goal} ${race.unit}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFE5F0FF),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 278,
                      maxWidth: 304,
                    ),
                    child: SizedBox(
                      height: 60,
                      child: FilledButton(
                        key: const ValueKey('track-view-make-move'),
                        onPressed: onSubmitProof,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kArenaBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                        child: const Text(
                          'Submit proof',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArenaBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final vignette = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.68, -0.58),
        radius: 1.05,
        colors: [
          const Color(0xFF10345F).withValues(alpha: 0.48),
          Colors.transparent,
        ],
        stops: const [0, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignette);

    final lowerGlow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          const Color(0xFF020D1B).withValues(alpha: 0.62),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, lowerGlow);
  }

  @override
  bool shouldRepaint(covariant _ArenaBackdropPainter oldDelegate) => false;
}

class _ArenaHeader extends StatelessWidget {
  const _ArenaHeader({
    required this.index,
    required this.count,
    required this.onPrevious,
    required this.onNext,
  });

  final int index;
  final int count;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(
          'assets/branding/nuvo_logo.png',
          width: 82,
          height: 30,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          errorBuilder: (context, error, stackTrace) => const Text(
            'NUVO',
            style: TextStyle(
              color: _kArenaText,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
        ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              'ARENA',
              style: TextStyle(
                color: _kArenaBlue,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.6,
              ),
            ),
            if (count > 1) ...[
              const SizedBox(height: 8),
              _RaceSwitcher(
                index: index,
                count: count,
                onPrevious: onPrevious,
                onNext: onNext,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ProgressReadout extends StatelessWidget {
  const _ProgressReadout({
    required this.currentProgress,
    required this.goal,
    required this.unit,
  });

  final int currentProgress;
  final int goal;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '$currentProgress',
            key: const ValueKey('track-view-current-progress'),
            style: const TextStyle(
              color: _kArenaBlue,
              fontSize: 72,
              fontWeight: FontWeight.w900,
              height: 0.95,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '/',
              style: TextStyle(
                color: _kArenaMuted,
                fontSize: 47,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
          Text(
            '$goal',
            style: const TextStyle(
              color: _kArenaText,
              fontSize: 66,
              fontWeight: FontWeight.w800,
              height: 0.95,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 7, bottom: 8),
            child: Text(
              unit,
              style: const TextStyle(
                color: _kArenaMuted,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RaceSwitcher extends StatelessWidget {
  const _RaceSwitcher({
    required this.index,
    required this.count,
    required this.onPrevious,
    required this.onNext,
  });

  final int index;
  final int count;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x171264FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x553D7BFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SwitcherButton(
            key: const ValueKey('previous-race'),
            icon: Icons.chevron_left,
            onPressed: onPrevious,
          ),
          SizedBox(
            width: 56,
            child: Text(
              '${index + 1} / $count',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFDDEBFF),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _SwitcherButton(
            key: const ValueKey('next-race'),
            icon: Icons.chevron_right,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _SwitcherButton extends StatelessWidget {
  const _SwitcherButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 26,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        color: onPressed == null ? const Color(0x667D8CA3) : _kArenaText,
        padding: EdgeInsets.zero,
        splashRadius: 18,
      ),
    );
  }
}

class _StandingsPanel extends StatelessWidget {
  const _StandingsPanel({required this.race, required this.onViewStandings});

  final TrackViewRaceData race;
  final VoidCallback onViewStandings;

  @override
  Widget build(BuildContext context) {
    final standings = [...race.participants]
      ..sort((a, b) => b.completedAmount.compareTo(a.completedAmount));
    final recent = standings.firstWhere(
      (participant) => !participant.isCurrentUser,
      orElse: () => standings.first,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final showRecent = constraints.maxHeight >= 260;
        return DecoratedBox(
          decoration: const BoxDecoration(color: NuvoColors.surface),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 21, 26, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text(
                      'CREW STANDINGS',
                      style: TextStyle(
                        color: _kPanelMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      key: const ValueKey('track-view-standings'),
                      onPressed: onViewStandings,
                      style: TextButton.styleFrom(
                        foregroundColor: _kArenaBlue,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'View standings',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final entry in standings.asMap().entries) ...[
                  _StandingRow(
                    participant: entry.value,
                    rank: entry.key + 1,
                    goal: race.goal,
                  ),
                  if (entry.key != standings.length - 1)
                    const Divider(height: 15, color: _kPanelLine),
                ],
                if (showRecent) ...[
                  const Spacer(),
                  const Text(
                    'RECENT ACTIVITY',
                    style: TextStyle(
                      color: _kPanelMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ActivityRow(participant: recent, race: race),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.participant,
    required this.rank,
    required this.goal,
  });

  final TrackViewParticipantData participant;
  final int rank;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final progress = TrackViewGeometry.normalizeProgress(
      completedAmount: participant.completedAmount,
      goal: goal,
    );
    final isUser = participant.isCurrentUser;
    final rankColor = switch (rank) {
      1 => NuvoColors.gold,
      2 => NuvoColors.silver,
      3 => NuvoColors.bronze,
      _ => _kArenaBlue,
    };
    final selectedFill = isUser ? rankColor : null;
    final outlineColor = rank <= 3
        ? rankColor
        : isUser
        ? _kArenaBlue
        : null;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: selectedFill,
        borderRadius: BorderRadius.circular(12),
        border: outlineColor != null
            ? Border.all(color: outlineColor, width: 2)
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$rank',
              style: TextStyle(
                color: selectedFill != null
                    ? NuvoColors.white
                    : (rank <= 3 ? rankColor : _kPanelMuted),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _PanelAvatar(participant: participant, size: 38, rank: rank),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              participant.displayName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selectedFill != null
                    ? NuvoColors.white
                    : (rank <= 3 ? rankColor : const Color(0xFF4A5565)),
                fontSize: 16,
                fontWeight: isUser ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${participant.completedAmount}',
                  style: TextStyle(
                    color: selectedFill != null
                        ? NuvoColors.white
                        : (rank <= 3 ? rankColor : _kPanelMuted),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(text: ' / $goal'),
              ],
            ),
            style: TextStyle(
              color: selectedFill != null ? NuvoColors.white : _kPanelMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 58,
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: const Color(0xFFE4E7EC),
                valueColor: AlwaysStoppedAnimation<Color>(
                  selectedFill != null ? NuvoColors.white : rankColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.participant, required this.race});

  final TrackViewParticipantData participant;
  final TrackViewRaceData race;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PanelAvatar(participant: participant, size: 30),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: participant.displayName,
                  style: const TextStyle(
                    color: _kPanelText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(
                  text: ' submitted proof for ${race.title.toLowerCase()}',
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _kPanelMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          '2m ago',
          style: TextStyle(
            color: _kPanelMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PanelAvatar extends StatelessWidget {
  const _PanelAvatar({
    required this.participant,
    required this.size,
    this.rank,
  });

  final TrackViewParticipantData participant;
  final double size;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final isUser = participant.isCurrentUser;
    return SizedBox(
      width: rank == null ? size : size + 4,
      height: rank == null ? size : size + 5,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isUser ? _kArenaBlue : _avatarColor(participant.id),
              border: Border.all(
                color: isUser ? const Color(0xFFBBD5FF) : Colors.white,
                width: 2,
              ),
            ),
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: Text(
                  _initials(participant.displayName),
                  style: TextStyle(
                    color: isUser ? Colors.white : _kPanelText,
                    fontSize: size * 0.36,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
          if (rank != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isUser ? _kArenaBlue : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: NuvoColors.surface, width: 1.5),
                ),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: Center(
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        color: isUser ? Colors.white : _kPanelText,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _avatarColor(String id) {
    final palette = NuvoColors.avatarPalette;
    return palette[id.hashCode.abs() % palette.length].withValues(alpha: 0.55);
  }

  String _initials(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }
}
