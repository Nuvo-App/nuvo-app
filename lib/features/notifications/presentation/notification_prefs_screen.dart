import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/nuvo_entrance.dart';
import '../../../core/widgets/nuvo_back_header.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_loading_indicator.dart';
import '../../../core/widgets/nuvo_page.dart';
import '../../../core/widgets/nuvo_toggle.dart';
import '../application/push_service.dart';
import '../data/notification_prefs.dart';

final notificationPrefsApiProvider =
    Provider<NotificationPrefsApi>((_) => NotificationPrefsApi());

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
    final status =
        await ref.read(pushServiceProvider).notificationAuthorizationStatus();
    if (mounted) setState(() => _osStatus = status);
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

  Future<void> _toggle(
    NotificationPref pref, {
    bool? inApp,
    bool? push,
  }) async {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't save that. Try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(pref.category));
    }
  }

  @override
  Widget build(BuildContext context) {
    return NuvoPage(
      topBar: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: NuvoBackHeader(
            title: 'Notifications',
            onBack: () => context.canPop()
                ? context.pop()
                : context.go('/profile'),
          ),
        ),
      ),
      child: _body(),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: NuvoErrorState(
          message: "Couldn't load your settings.",
          onRetry: _load,
        ),
      );
    }
    final prefs = _prefs;
    if (prefs == null) return const Center(child: NuvoLoadingIndicator());

    final c = context.themeColors;
    final groups = <String, List<NotificationPref>>{};
    for (final p in prefs) {
      groups.putIfAbsent(p.display.group, () => []).add(p);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
      children: [
        Text(
          'Control in-app and push alerts.',
          style: AppTextStyles.bodySmall.copyWith(color: c.inkMuted),
        ),
        if (_osStatus == AuthorizationStatus.denied) ...[
          const SizedBox(height: NuvoSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(NuvoRadii.md),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Icon(Icons.notifications_off_rounded,
                    size: 18, color: c.inkMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Notifications are off on this device.',
                    style: AppTextStyles.bodySmall.copyWith(color: c.ink),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      launchUrl(Uri.parse('app-settings:')),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: NuvoSpacing.xl),
        for (final entry in groups.entries.toList().asMap().entries) ...[
          _SectionHeader(label: entry.value.key.toUpperCase()),
          const SizedBox(height: NuvoSpacing.sm),
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(NuvoRadii.md),
              border: Border.all(color: c.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(NuvoRadii.md - 1),
              child: Column(
                children: [
                  for (var i = 0; i < entry.value.value.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, thickness: 1, color: c.border),
                    _PrefRow(
                      pref: entry.value.value[i],
                      saving: _saving.contains(
                        entry.value.value[i].category,
                      ),
                      onInApp: (v) =>
                          _toggle(entry.value.value[i], inApp: v),
                      onPush: (v) =>
                          _toggle(entry.value.value[i], push: v),
                    ),
                  ],
                ],
              ),
            ),
          ).nuvoEnter(
            delay: Duration(milliseconds: 40 * entry.key),
          ),
          const SizedBox(height: NuvoSpacing.xl),
        ],
      ],
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
    final c = context.themeColors;
    final headerStyle = AppTextStyles.labelSmall.copyWith(
      color: c.inkMuted,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
    );
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
    final c = context.themeColors;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              pref.display.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(color: c.ink),
            ),
          ),
          _ToggleCell(
            semanticLabel:
                '${pref.display.label}, app notifications',
            value: pref.inApp,
            onChanged: saving ? null : onInApp,
          ),
          _ToggleCell(
            semanticLabel:
                '${pref.display.label}, push notifications',
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
          child: NuvoToggle(value: value, onChanged: onChanged),
        ),
      ),
    );
  }
}
