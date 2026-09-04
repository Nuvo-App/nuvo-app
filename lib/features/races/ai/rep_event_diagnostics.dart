import '../../../core/widgets/rep_burst_controller.dart';

/// A single recognized rep, for diagnostics only. Not used by any counting
/// or verification logic — [RepBurstEvent.totalCount] (sourced straight from
/// the validator) remains the only authoritative count.
class RepEventLogEntry {
  RepEventLogEntry({required this.at, required this.event, this.intervalMs});

  final DateTime at;
  final RepBurstEvent event;

  /// Milliseconds since the previous logged rep, or null for the first.
  final int? intervalMs;

  @override
  String toString() =>
      '#${event.totalCount} at ${_hms(at)}'
      '${intervalMs != null ? ' (+${intervalMs}ms)' : ''}';

  static String _hms(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}.'
      '${t.millisecond.toString().padLeft(3, '0')}';
}

/// Bounded ring buffer of the most recent rep events, purely for the
/// diagnostics overlay/log. Keeping only the last [capacity] entries means
/// this can be recorded unconditionally on the hot frame path without
/// growing memory during a long set.
class RepEventLog {
  RepEventLog({this.capacity = 12});

  final int capacity;
  final List<RepEventLogEntry> _entries = [];

  List<RepEventLogEntry> get entries => List.unmodifiable(_entries);

  void record(RepBurstEvent event, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final prev = _entries.isEmpty ? null : _entries.last.at;
    _entries.add(
      RepEventLogEntry(
        at: at,
        event: event,
        intervalMs: prev == null ? null : at.difference(prev).inMilliseconds,
      ),
    );
    if (_entries.length > capacity) _entries.removeAt(0);
  }

  void clear() => _entries.clear();

  /// The interval (ms) between the two most recent reps, if there are at
  /// least two — the number the "fast reps missed" report cares about most.
  int? get lastIntervalMs =>
      _entries.isEmpty ? null : _entries.last.intervalMs;

  String summary() => _entries.isEmpty
      ? 'no reps yet'
      : _entries.map((e) => e.toString()).join(' | ');
}
