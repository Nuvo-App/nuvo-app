import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/v13/v13.dart';
import '../../../core/widgets/nuvo_fade_scroll.dart';
import '../application/push_service.dart';
import '../data/notification_prefs.dart';

final notificationPrefsApiProvider = Provider<NotificationPrefsApi>(
  (_) => NotificationPrefsApi(),
);

/// `/settings/notifications` — grouped in-app + push toggles per category.
///
/// A quiet control panel, not a social surface: one App/Push column header
/// per section, compact rows, hairline dividers. Preference semantics are
/// untouched — the two toggles stay independent because the backend treats
/// in-app and push as separate channels.
class NotificationPrefsScreen extends ConsumerStatefulWidget {
  const NotificationPrefsScreen({super.key});

  @override
  ConsumerState<NotificationPrefsScreen> createState() => _State();
}

class _State extends ConsumerState<NotificationPrefsScreen> {
  List<NotificationPref>? _prefs;
  Object? _error;
  final _saving = <String>{};
  AuthorizationStatus? _osStatus;

  @override
  void initState() {
    super.initState();
    _load();
    _loadOsStatus();
  }

  /// The OS-level switch: when the device has denied Nuvo alerts the push
  /// toggles below can't deliver — surface the way back to iOS Settings
  /// rather than letting a user flip dead toggles.
  Future<void> _loadOsStatus() async {
    try {
      final status = await ref
          .read(pushServiceProvider)
          .notificationAuthorizationStatus();
      if (mounted) setState(() => _osStatus = status);
    } catch (_) {
      // Leave the OS status unknown; the toggles still work.
    }
  }

  Future<void> _load() async {
    setState(() {
      _prefs = null;
      _error = null;
    });
    try {
      final p = await ref.read(notificationPrefsApiProvider).list();
      if (mounted) setState(() => _prefs = p);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _toggle(NotificationPref pref, {bool? inApp, bool? push}) async {
    final updated = NotificationPref(
      category: pref.category,
      inApp: inApp ?? pref.inApp,
      push: push ?? pref.push,
    );
    setState(() {
      _prefs = _prefs!
          .map((p) => p.category == pref.category ? updated : p)
          .toList();
      _saving.add(pref.category);
    });
    try {
      await ref
          .read(notificationPrefsApiProvider)
          .update(pref.category, inApp: inApp, push: push);
    } catch (_) {
      if (mounted) {
        setState(() {
          _prefs = _prefs!
              .map((p) => p.category == pref.category ? pref : p)
              .toList();
        });
        showV13Toast(context, "Couldn't save that. Try again.");
      }
    } finally {
      if (mounted) setState(() => _saving.remove(pref.category));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          children: [
            const V13BackBar(title: 'Notifications', fallback: '/profile'),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(V13.gapXxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 44, color: V13.muted),
              const SizedBox(height: V13.gapLg),
              Text(
                "Couldn't load your settings.",
                style: V13.sectionHead,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: V13.gapSm),
              Text(
                'Check your connection and try again.',
                style: V13.caption,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: V13.gapXl),
              V13Button.secondary(label: 'Retry', onPressed: _load),
            ],
          ),
        ),
      );
    }
    final prefs = _prefs;
    if (prefs == null) {
      return ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(V13.pagePad, 6, V13.pagePad, 32),
        children: const [
          V13Skeleton(height: 120, radius: V13.radiusTile),
          SizedBox(height: V13.gapXl),
          V13Skeleton(height: 160, radius: V13.radiusTile),
        ],
      );
    }

    final groups = <String, List<NotificationPref>>{};
    for (final p in prefs) {
      groups.putIfAbsent(p.display.group, () => []).add(p);
    }

    return NuvoFadeScroll(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          V13.pagePad,
          6,
          V13.pagePad,
          32 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          Text('Control in-app and push alerts.', style: V13.caption),
          if (_osStatus == AuthorizationStatus.denied) ...[
            const SizedBox(height: V13.gapSm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: V13.card,
                borderRadius: BorderRadius.circular(V13.radiusTile),
                border: Border.all(color: V13.navy, width: V13.outline),
                boxShadow: V13.shadow3,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.notifications_off_rounded,
                    size: 18,
                    color: V13.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Notifications are off on this device.',
                      style: V13.bodyStrong,
                    ),
                  ),
                  V13Button.secondary(
                    label: 'Open Settings',
                    size: V13ButtonSize.small,
                    onPressed: () => launchUrl(Uri.parse('app-settings:')),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: V13.gapXl),
          for (final entry in groups.entries.toList().asMap().entries) ...[
            _SectionHeader(label: entry.value.key.toUpperCase()),
            const SizedBox(height: V13.gapSm),
            Container(
              decoration: BoxDecoration(
                color: V13.card,
                borderRadius: BorderRadius.circular(V13.radiusTile),
                border: Border.all(color: V13.navy, width: V13.outline),
                boxShadow: V13.shadow3,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(V13.radiusTile - 1),
                child: Column(
                  children: [
                    for (var i = 0; i < entry.value.value.length; i++) ...[
                      if (i > 0) const V13Divider(thickness: 1),
                      _PrefRow(
                        pref: entry.value.value[i],
                        saving: _saving.contains(entry.value.value[i].category),
                        onInApp: (v) => _toggle(entry.value.value[i], inApp: v),
                        onPush: (v) => _toggle(entry.value.value[i], push: v),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: V13.gapXl),
          ],
        ],
      ),
    );
  }
}

/// One column header per section — "App / Push" is declared once over the
/// two toggle columns instead of repeated inside every row.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final headerStyle = V13.label;
    return Row(
      children: [
        Expanded(child: Text(label, style: headerStyle)),
        SizedBox(
          width: _colW,
          child: Center(
            child: ExcludeSemantics(child: Text('App', style: headerStyle)),
          ),
        ),
        SizedBox(
          width: _colW,
          child: Center(
            child: ExcludeSemantics(child: Text('Push', style: headerStyle)),
          ),
        ),
      ],
    );
  }
}

/// Width of each toggle column — the section header labels and every row
/// share it so App and Push line up as real columns.
const _colW = 52.0;

class _PrefRow extends StatelessWidget {
  const _PrefRow({
    required this.pref,
    required this.saving,
    required this.onInApp,
    required this.onPush,
  });

  final NotificationPref pref;
  final bool saving;
  final ValueChanged<bool> onInApp;
  final ValueChanged<bool> onPush;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              pref.display.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: V13.bodyStrong,
            ),
          ),
          _ToggleCell(
            semanticLabel: '${pref.display.label}, app notifications',
            value: pref.inApp,
            onChanged: saving ? null : onInApp,
          ),
          _ToggleCell(
            semanticLabel: '${pref.display.label}, push notifications',
            value: pref.push,
            onChanged: saving ? null : onPush,
          ),
        ],
      ),
    );
  }
}

class _ToggleCell extends StatelessWidget {
  const _ToggleCell({
    required this.semanticLabel,
    required this.value,
    required this.onChanged,
  });

  final String semanticLabel;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _colW,
      child: Center(
        // The column headers are visual; each toggle carries its own full
        // phrase for screen readers ("Race starting, app notifications").
        child: Semantics(
          label: semanticLabel,
          child: Opacity(
            opacity: onChanged == null ? .5 : 1,
            child: V13Toggle(value: value, onChanged: onChanged ?? (_) {}),
          ),
        ),
      ),
    );
  }
}
