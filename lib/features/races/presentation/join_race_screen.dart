import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/v13/v13.dart';
import '../../auth/data/auth_api.dart';
import 'race_controller.dart';

/// `/races/join` — join a race by invite code. The v13 "Join with a code"
/// surface: one sky hero, one boxed code field, one blue Join action.
class JoinRaceScreen extends ConsumerStatefulWidget {
  const JoinRaceScreen({super.key});

  @override
  ConsumerState<JoinRaceScreen> createState() => _JoinRaceScreenState();
}

class _JoinRaceScreenState extends ConsumerState<JoinRaceScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    FocusScope.of(context).unfocus();
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Enter an invite code.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .joinRaceByCode(code);
      if (!mounted) return;
      showV13Confetti(context);
      showV13Toast(context, "You're in the race.");
      context.go('/race/${race.id}');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message.trim().isEmpty
              ? 'That invite code didn’t work. Check it and try again.'
              : friendlyApiError(e);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not join this race.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          children: [
            V13BackBar(
              title: 'Join a race',
              onBack: () => safePopOrGo(context, '/compete'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  V13.pagePad,
                  V13.gapMd,
                  V13.pagePad,
                  V13.gapXxl,
                ),
                children: [
                  V13Card(
                    color: V13.sky,
                    child: Row(
                      children: [
                        const V13IconTile(
                          icon: Icons.key_rounded,
                          color: V13.card,
                        ),
                        const SizedBox(width: V13.gapMd),
                        Expanded(
                          child: Text(
                            'Have an invite code? Enter it below to join the race.',
                            style: V13.bodyStrong,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: V13.gapSection),
                  V13TextInput(
                    controller: _codeController,
                    label: 'Invite code',
                    hint: 'NUV-XXXXXX',
                    textCapitalization: TextCapitalization.characters,
                    errorText: _error,
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    onSubmitted: (_) => _join(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                V13.pagePad,
                0,
                V13.pagePad,
                V13.gapLg,
              ),
              child: V13Button.primary(
                label: 'Join race',
                icon: Icons.flag_rounded,
                fullWidth: true,
                loading: _loading,
                onPressed: _loading ? null : _join,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
