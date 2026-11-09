import 'package:flutter/widgets.dart';

/// Height the S5/S6 ticket hero may take so the whole screen fits without
/// leaving a dead zone: whatever the viewport has left after the chrome
/// (top bar, CTA dock, keyboard) and the content [below] the hero.
///
/// Returns 0 when the keyboard is up (or the phone is short) and there is not even room for a mini
/// ticket (the title + fields matter more than the decoration then); never
/// less than [min] on a tall phone (the shell scrolls).
double obHeroHeight(
  BuildContext context, {
  required double below,
  double min = 96,
  double max = 300,
}) {
  final mq = MediaQuery.of(context);
  final keyboard = mq.viewInsets.bottom;
  const topBar = 64.0;
  const ctaSlot = 56.0;
  final dockGap = keyboard > 16 ? keyboard : 16.0;
  final avail =
      mq.size.height -
      mq.padding.top -
      mq.padding.bottom -
      dockGap -
      topBar -
      ctaSlot;
  final room = avail - below;
  if (room < min) return keyboard > 0 || obTightScreen(context) ? 0 : min;
  return room > max ? max : room;
}

/// Short phones (iPhone SE class) drop optional copy to keep the form on
/// screen.
bool obTightScreen(BuildContext context) =>
    MediaQuery.sizeOf(context).height < 640;
