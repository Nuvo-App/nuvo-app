import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../onboarding/presentation/first_use_guide.dart';
import 'auth_controller.dart';

class EmailStartScreen extends ConsumerStatefulWidget {
  const EmailStartScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<EmailStartScreen> createState() => _EmailStartScreenState();
}

class _EmailStartScreenState extends ConsumerState<EmailStartScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(() => setState(() {}));
    _passwordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String get _normalizedEmail => _emailController.text.trim().toLowerCase();

  // The canonical App Store review identity — the only email routed to the
  // reviewer credential path instead of a real inbox code. Exact match only:
  // other @getnuvo.net accounts are ordinary accounts.
  bool get _isReviewerEmail => isNuvoStoreDemoEmail(_normalizedEmail);

  bool get _canSubmit {
    if (_loading || !_normalizedEmail.contains('@')) return false;
    if (_isReviewerEmail) return _passwordController.text.isNotEmpty;
    return true;
  }

  Future<void> _submit() async {
    final email = _normalizedEmail;
    setState(() {
      _loading = true;
      _error = null;
    });
    // The reviewer credential's post-auth path is decided by the welcome
    // screen's intent — Sign Up replays the real first-use experience, Sign
    // In enters the seeded account directly. Under signUp the replay flag is
    // armed BEFORE the sign-in publishes auth state: the route guard
    // evaluates the moment the session resolves and must already see the
    // replay armed to route into first-run setup instead of the app.
    final intent = ref.read(authIntentProvider);
    final wasReplaying = ref.read(demoReplayProvider);
    if (_isReviewerEmail && intent == AuthIntent.signUp) {
      ref.read(demoReplayProvider.notifier).state = true;
    }
    try {
      if (_isReviewerEmail) {
        // The shared review credential authenticates through /auth/reviewer;
        // the controller's offline-demo fallback keys off this identity so
        // store review works even on networks that block workers.dev.
        await ref
            .read(authControllerProvider.notifier)
            .signInReviewer(
              email,
              _passwordController.text,
              intent: intent,
            );
        // Sign-up intent: reset the persisted demo state (guide done,
        // education flags) so the replay is complete, not just the story.
        // Sign-in intent deliberately preserves everything — returning-user
        // semantics for the seeded reviewer account.
        if (intent == AuthIntent.signUp) {
          final user = ref.read(authControllerProvider).user;
          if (user != null) {
            await resetDemoExperienceForColdLaunch(ref.read, user);
          }
        } else {
          // Returning-user semantics: drop any stale in-session replay and
          // guide step so the guard cannot redirect the sign-in into the
          // tour — e.g. a Sign Up run armed the replay earlier this process.
          ref.read(demoReplayProvider.notifier).state = false;
          ref.read(firstRaceGuideProvider.notifier).state =
              FirstRaceGuideStep.idle;
        }
        return;
      } else {
        await ref.read(authControllerProvider.notifier).startEmailAuth(email);
        // `mounted` alone is not enough: while this screen is still animating
        // out (back nav, or a redirect that swapped the stack) it stays mounted
        // but is no longer current — pushing from it would drop the code
        // screen on top of whatever replaced it.
        final route = mounted ? ModalRoute.of(context) : null;
        if (mounted && (route?.isCurrent ?? false)) {
          context.push('/auth/verify', extra: email);
        }
      }
    } catch (e) {
      debugPrint('[EmailStart] startEmailAuth failed (${e.runtimeType}): $e');
      if (_isReviewerEmail) {
        // Failed sign-in must not leave a replay armed — a normal account
        // signing in next would be bounced into the story.
        ref.read(demoReplayProvider.notifier).state = wasReplaying;
      }
      if (mounted) {
        setState(() {
          _error = isNetworkAuthError(e)
              ? "Can't reach Nuvo. Check your connection and try again."
              : _isReviewerEmail
              ? 'Invalid review credentials.'
              : 'Could not send code. Please try again.';
        });
      }
    } finally {
      // Every path — success navigation, reviewer sign-in, thrown error —
      // leaves the form usable. Without this, popping back from the code
      // screen found the button still spinning (loading was only cleared on
      // the error path).
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Widget _buildFields() => AutofillGroup(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NuvoTextInput(
          controller: _emailController,
          label: 'Email',
          hint: 'your@email.com',
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: _isReviewerEmail
              ? TextInputAction.next
              : TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (_) {
            if (!_isReviewerEmail && _canSubmit) _submit();
          },
          onChanged: (_) => setState(() => _error = null),
        ),
        if (_isReviewerEmail) ...[
          const SizedBox(height: 14),
          NuvoTextInput(
            controller: _passwordController,
            label: 'Password',
            hint: 'Password',
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) {
              if (_canSubmit) _submit();
            },
            onChanged: (_) => setState(() => _error = null),
          ),
        ],
        if (widget.embedded || _error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Semantics(
              liveRegion: _error != null,
              child: Text(
                _error ??
                    (_isReviewerEmail
                        ? 'Use your reviewer account password.'
                        : "We'll email you a sign-in code."),
                style: AppTextStyles.bodySmall.copyWith(
                  color: _error == null ? NuvoColors.muted : NuvoColors.danger,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFields(),
          const SizedBox(height: 20),
          NuvoPrimaryButton(
            label: 'Log in',
            expand: true,
            loading: _loading,
            onPressed: _canSubmit ? _submit : null,
          ),
        ],
      );
    }
    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Scrollable content ───────────────────────────────────────────
            Expanded(
              child:
                  SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            NuvoBackButton(
                              onPressed: () => safePopOrGo(context, '/welcome'),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Enter your email',
                              style: AppTextStyles.headlineLarge.copyWith(
                                fontSize: 32,
                                letterSpacing: -0.9,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "We'll send a sign-in code for your Nuvo race pass.",
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: NuvoColors.muted,
                              ),
                            ),
                            const SizedBox(height: 30),
                            _buildFields(),
                          ],
                        ),
                      )
                      .animate()
                      .fadeIn(duration: 280.ms, curve: Curves.easeOut)
                      .slideY(
                        begin: 0.04,
                        end: 0,
                        duration: 320.ms,
                        curve: Curves.easeOutCubic,
                      ),
            ),

            // ── Pinned CTA ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: NuvoPrimaryButton(
                label: _isReviewerEmail ? 'Sign in' : 'Send code',
                icon: Icons.arrow_forward_rounded,
                expand: true,
                loading: _loading,
                onPressed: _canSubmit ? _submit : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
