import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'nuvo_motion.dart';

/// Nuvo's physical on/off toggle — the Nuvo-styled replacement for the stock
/// Material [Switch] in settings surfaces.
///
/// Track: navy-outline pill — ice when off, action blue when on. Knob: navy
/// when off, white when on, spring-sliding across the track. The whole
/// control presses with the shared [NuvoPressable] physics and fires a light
/// selection haptic.
///
/// Unambiguous on/off: fill color + knob position + [Semantics.toggled] all
/// agree, so state never depends on motion alone.
class NuvoToggle extends StatefulWidget {
  const NuvoToggle({
    super.key,
    required this.value,
    this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  State<NuvoToggle> createState() => _NuvoToggleState();
}

class _NuvoToggleState extends State<NuvoToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: NuvoMotion.select,
    value: widget.value ? 1 : 0,
  );
  late final Animation<double> _knob = CurvedAnimation(
    parent: _ctrl,
    curve: NuvoMotion.spring,
    reverseCurve: NuvoMotion.settle,
  );

  @override
  void didUpdateWidget(covariant NuvoToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = widget.value ? 1 : 0;
    } else if (widget.value) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    return Semantics(
      toggled: widget.value,
      enabled: enabled,
      label: widget.semanticLabel,
      child: NuvoPressable(
        onTap: enabled ? () => widget.onChanged!(!widget.value) : null,
        scale: 0.94,
        translateY: 1.5,
        child: SizedBox(
          // 44px touch height; the visual track stays compact inside it.
          height: 44,
          child: Center(
            child: AnimatedBuilder(
              animation: _knob,
              builder: (context, _) {
                final t = _knob.value;
                return Container(
                  width: 50,
                  height: 30,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      NuvoColors.panelLight,
                      NuvoColors.actionBlue,
                      t,
                    ),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: NuvoColors.navy, width: 2),
                  ),
                  child: Align(
                    alignment: Alignment.lerp(
                      Alignment.centerLeft,
                      Alignment.centerRight,
                      t,
                    )!,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Color.lerp(
                          NuvoColors.navy,
                          NuvoColors.white,
                          t,
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
