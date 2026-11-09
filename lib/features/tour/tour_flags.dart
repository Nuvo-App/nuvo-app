import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ship switch for the post-signup guided tour. OFF: nothing in
/// `lib/features/tour` renders, no fixtures overlay any screen, no row or
/// setting appears. Flip to true only when every stop is finished to the
/// quality bar (see docs/redesign/onboarding-v2-spec.md, TOUR ENGINE).
const bool kTourEnabled = false;

/// The runtime read of [kTourEnabled]. Every tour surface asks this provider
/// (never the const directly) so widget tests can turn the tour on without a
/// recompile; production overrides nothing and gets the const.
final tourFeatureEnabledProvider = Provider<bool>((ref) => kTourEnabled);
