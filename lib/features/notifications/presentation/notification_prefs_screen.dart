import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/theme/nuvo_entrance.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_loading_indicator.dart';
import '../../../core/widgets/nuvo_page.dart';
import '../data/notification_prefs.dart';

final _prefsApiProvider = Provider<NotificationPrefsApi>((_) => NotificationPrefsApi());

/// `/settings/notifications` — grouped in-app + push toggles per category.
class NotificationPrefsScreen extends ConsumerStatefulWidget {
  const NotificationPrefsScreen({super.key});

  @override
  ConsumerState<NotificationPrefsScreen> createState() => _State();
}

class _State extends ConsumerState<NotificationPrefsScreen> {
  List<NotificationPref>? _prefs;
  Object? _error;
  final _saving = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _prefs = null;
      _error = null;
    });
    try {
      final p = await ref.read(_prefsApiProvider).list();
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
      _prefs = _prefs!.map((p) => p.category == pref.category ? updated : p).toList();
      _saving.add(pref.category);
    });
    try {
      await ref.read(_prefsApiProvider).update(
            pref.category,
            inApp: inApp,
            push: push,
          );
    } catch (_) {
      if (mounted) {
        setState(() {
          _prefs =
              _prefs!.map((p) => p.category == pref.category ? pref : p).toList();
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
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
          child: Row(children: [
            NuvoBackButton(
              onPressed: () => context.canPop() ? context.pop() : context.go('/profile'),
            ),
            const SizedBox(width: 8),
            Text('Notifications', style: AppTextStyles.screenTitle),
          ]),
        ),
      ),
      child: _body(),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: NuvoErrorState(message: "Couldn't load your settings.", onRetry: _load),
      );
    }
    final prefs = _prefs;
    if (prefs == null) return const Center(child: NuvoLoadingIndicator());

    final groups = <String, List<NotificationPref>>{};
    for (final p in prefs) {
      groups.putIfAbsent(p.display.group, () => []).add(p);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          'Choose what reaches you in the app and as a push. Push arrives once '
          'notifications are turned on for Nuvo on this device.',
          style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.textMuted),
        ),
        const SizedBox(height: 20),
        for (final entry in groups.entries) ...[
          Text(entry.key.toUpperCase(),
              style: AppTextStyles.labelSmall.copyWith(
                color: NuvoColors.textMuted,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              )),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: NuvoColors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: NuvoColors.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < entry.value.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _PrefRow(
                    pref: entry.value[i],
                    onInApp: (v) => _toggle(entry.value[i], inApp: v),
                    onPush: (v) => _toggle(entry.value[i], push: v),
                  ),
                ],
              ],
            ),
          ).nuvoEnter(
            delay: Duration(
              milliseconds: 40 * groups.keys.toList().indexOf(entry.key),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

class _PrefRow extends StatelessWidget {
  const _PrefRow({required this.pref, required this.onInApp, required this.onPush});

  final NotificationPref pref;
  final ValueChanged<bool> onInApp;
  final ValueChanged<bool> onPush;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(pref.display.label,
                style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.navy)),
          ),
          _MiniToggle(label: 'App', value: pref.inApp, onChanged: onInApp),
          const SizedBox(width: 4),
          _MiniToggle(label: 'Push', value: pref.push, onChanged: onPush),
        ],
      ),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  const _MiniToggle({required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTextStyles.labelSmall.copyWith(color: NuvoColors.textMuted)),
        Transform.scale(
          scale: 0.8,
          child: Switch(value: value, onChanged: onChanged),
        ),
      ],
    );
  }
}
