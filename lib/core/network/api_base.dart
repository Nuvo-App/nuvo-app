/// Shared API base URL for every backend client — one source of truth so the
/// deploy target can be overridden once with `--dart-define=NUVO_API_BASE_URL`.
const kNuvoApiBase = String.fromEnvironment(
  'NUVO_API_BASE_URL',
  defaultValue: 'https://nuvo-api.getnuvoapp.workers.dev',
);
