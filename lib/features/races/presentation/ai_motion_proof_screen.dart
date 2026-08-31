// Conditional export: mobile uses the full camera/MLKit implementation;
// web uses a static placeholder that does not import any native-only packages.
export 'ai_motion_proof_screen_io.dart'
    if (dart.library.js_interop) 'ai_motion_proof_screen_web.dart';
