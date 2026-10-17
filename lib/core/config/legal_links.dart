import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The four legal pages. One source of truth — every screen that links to a
/// legal page (welcome, onboarding, Settings) uses these, never a literal URL.
abstract final class LegalLinks {
  static const String privacy = 'https://getnuvo.net/privacy/';
  static const String terms = 'https://getnuvo.net/terms/';
  static const String communityGuidelines =
      'https://getnuvo.net/community-guidelines/';
  static const String deleteAccount = 'https://getnuvo.net/delete-account/';

  static final Uri privacyUri = Uri.parse(privacy);
  static final Uri termsUri = Uri.parse(terms);
  static final Uri communityGuidelinesUri = Uri.parse(communityGuidelines);
  static final Uri deleteAccountUri = Uri.parse(deleteAccount);
}

/// Test seam: replaces the real launcher. Null in production.
@visibleForTesting
Future<bool> Function(Uri uri, LaunchMode mode)? legalLaunchOverride;

/// Opens a legal page in the external browser (the app keeps its place, and
/// the browser has its own back button). Says so out loud if it can't.
Future<void> openLegalLink(BuildContext context, Uri uri) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var opened = false;
  try {
    opened = await (legalLaunchOverride ?? _launch)(
      uri,
      LaunchMode.externalApplication,
    );
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    messenger?.showSnackBar(
      const SnackBar(content: Text("Couldn't open the link. Try again.")),
    );
  }
}

Future<bool> _launch(Uri uri, LaunchMode mode) => launchUrl(uri, mode: mode);
