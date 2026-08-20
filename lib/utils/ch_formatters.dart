import 'package:intl/intl.dart';

/// Money formatter for SYP.
/// Always western digits with thousands separators: `45,000 ل.س` / `45,000 SYP`.
class ChMoney {
  ChMoney._();

  static final NumberFormat _fmt = NumberFormat('#,###', 'en_US');

  /// Format an integer SYP amount with the Arabic currency mark.
  /// Example: `format(45000)` → `45,000 ل.س`
  static String format(int syp) => '${_fmt.format(syp)} ل.س';

  /// Latin variant: `45,000 SYP`.
  static String formatEn(int syp) => '${_fmt.format(syp)} SYP';

  /// Plain formatted number without a currency mark.
  static String number(int n) => _fmt.format(n);
}
