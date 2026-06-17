import 'package:intl/intl.dart';

/// Stateless formatters shared across the app. Always extend this file
/// rather than inlining date/number formatting in widgets — easier to
/// localize and unit-test later.
abstract final class Formatters {
  static final NumberFormat _usd = NumberFormat.simpleCurrency(
    locale: 'en_US',
    decimalDigits: 0,
  );

  /// `$1,250` style money. Pass `prefix: 'pool'` if you want to display
  /// "Pool $1,250".
  static String money(num value) => _usd.format(value);

  /// "Glory" prizes carry no $ — display the raw integer with a suffix.
  static String glory(num value) => '${NumberFormat.decimalPattern().format(value)} Glory';

  /// `12d`, `4h`, `<1h`. Used on the countdown chip of [ChallengeCard].
  static String countdown(Duration remaining) {
    if (remaining.isNegative) return 'Ended';
    if (remaining.inDays >= 1) return '${remaining.inDays}d';
    if (remaining.inHours >= 1) return '${remaining.inHours}h';
    return '<1h';
  }

  /// `Jun 16 → Jul 30` style date range for the create-challenge summary.
  static String dateRange(DateTime start, DateTime end) {
    final fmt = DateFormat.MMMd();
    return '${fmt.format(start)} → ${fmt.format(end)}';
  }
}
