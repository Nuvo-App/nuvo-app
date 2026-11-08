/// Feature flag for the v13 redesign shell.
///
/// Defaults ON. `--dart-define=NUVO_V13=false` restores the pre-v13 shell
/// byte-for-byte. Removed in stage S9 once the old shell is deleted.
const bool kNuvoV13 = bool.fromEnvironment('NUVO_V13', defaultValue: true);
