/// The three coupon kinds Screen 16 renders differently:
/// - percent          → `NN%` on the value tile
/// - fixed            → `X,XXX` on the value tile (still in SYP)
/// - free_delivery    → 🛵 glyph on the value tile
enum CouponType {
  percent,
  fixed,
  freeDelivery;

  static CouponType parse(String raw) => switch (raw) {
        'percent'        => CouponType.percent,
        'fixed'          => CouponType.fixed,
        'free_delivery'  => CouponType.freeDelivery,
        _                => CouponType.percent, // safest default for unknowns
      };
}

/// Reason a coupon can't be applied to the current cart. Screen 16 §4 shows
/// this in place of the normal condition line, in red — never hides the row.
enum CouponIneligibility {
  none,
  minSpendNotMet,
  firstOrderOnly,
  expired,
}

/// A promo code as returned by `GET /api/v1/coupons` (public).
///
/// Eligibility is a **client-side pre-check** so the UI can grey out rows
/// and show reasons in real time. The server is still the source of truth
/// at apply-time (`POST /cart/promo`) — a coupon that passes here can still
/// be rejected server-side (e.g. per-user-limit already hit).
class Coupon {
  final int        id;
  final String     code;
  final String     titleAr;
  final String?    descriptionAr;
  final CouponType type;
  final int        value;            // % for percent, SYP for fixed, 0 for free_delivery
  final int        minOrder;         // SYP
  final int?       maxDiscount;      // SYP, only for percent
  final DateTime?  endsAt;
  final bool       firstOrderOnly;

  const Coupon({
    required this.id,
    required this.code,
    required this.titleAr,
    required this.type,
    required this.value,
    required this.minOrder,
    this.descriptionAr,
    this.maxDiscount,
    this.endsAt,
    this.firstOrderOnly = false,
  });

  factory Coupon.fromJson(Map<String, dynamic> j) {
    final min     = (j['min_order'] as Map<String, dynamic>?) ?? const {};
    final endsRaw =  j['ends_at']    as String?;
    return Coupon(
      id:              (j['id'] as num).toInt(),
      code:             j['code'] as String,
      titleAr:         (j['title_ar'] as String?) ?? (j['code'] as String),
      descriptionAr:    j['description_ar'] as String?,
      type:             CouponType.parse((j['type'] as String?) ?? 'percent'),
      value:           (j['value'] as num?)?.toInt() ?? 0,
      minOrder:        (min['amount'] as num?)?.toInt() ?? 0,
      maxDiscount:     (j['max_discount'] as num?)?.toInt(),
      endsAt:           endsRaw == null ? null : DateTime.tryParse(endsRaw),
      firstOrderOnly: (j['first_order_only'] as bool?) ?? false,
    );
  }

  // ─── Derived display bits ────────────────────────────────────────

  /// The big glyph on the 56 square value tile.
  ///  - percent → "NN%"
  ///  - fixed   → the value in K form ("5K") to fit in 18 pt Changa
  ///  - free    → 🛵
  String get valueGlyph {
    switch (type) {
      case CouponType.percent:      return '$value%';
      case CouponType.fixed:        return _shortMoney(value);
      case CouponType.freeDelivery: return '🛵';
    }
  }

  /// The tiny sub-caption on the value tile ("خصم" / "ل.س" / "توصيل").
  String get valueSubAr {
    switch (type) {
      case CouponType.percent:      return 'خصم';
      case CouponType.fixed:        return 'ل.س';
      case CouponType.freeDelivery: return 'توصيل';
    }
  }

  bool get isExpiringToday {
    if (endsAt == null) return false;
    final now = DateTime.now();
    return endsAt!.year == now.year &&
           endsAt!.month == now.month &&
           endsAt!.day == now.day;
  }

  bool get isExpired {
    if (endsAt == null) return false;
    return endsAt!.isBefore(DateTime.now());
  }

  /// Value used to rank eligible rows top-first when sorting.
  ///  - percent  → 1000 + value (higher %, higher rank)
  ///  - fixed    → value / 100 (a 5000-SYP coupon beats a 10% one)
  ///  - free     → 500 (mid-tier)
  int get sortValue {
    switch (type) {
      case CouponType.percent:      return 1000 + value;
      case CouponType.fixed:        return (value / 100).floor();
      case CouponType.freeDelivery: return 500;
    }
  }

  /// The client-side eligibility check. `hasPriorOrders` should be true iff
  /// the signed-in user has already placed at least one order — only known
  /// once auth is wired; passing `false` for guests is correct because the
  /// server treats them as "no orders".
  CouponIneligibility eligibleFor({
    required int subtotalSyp,
    required bool hasPriorOrders,
  }) {
    if (isExpired) return CouponIneligibility.expired;
    if (firstOrderOnly && hasPriorOrders) {
      return CouponIneligibility.firstOrderOnly;
    }
    if (subtotalSyp < minOrder) return CouponIneligibility.minSpendNotMet;
    return CouponIneligibility.none;
  }

  /// The Arabic reason line for an ineligible row (spec §4).
  /// Returns null when eligible.
  String? reasonAr({required int subtotalSyp, required bool hasPriorOrders}) {
    final r = eligibleFor(
      subtotalSyp: subtotalSyp,
      hasPriorOrders: hasPriorOrders,
    );
    switch (r) {
      case CouponIneligibility.none:            return null;
      case CouponIneligibility.expired:         return 'انتهت صلاحية الكوبون';
      case CouponIneligibility.firstOrderOnly:  return 'لأول طلب فقط';
      case CouponIneligibility.minSpendNotMet:
        final remaining = minOrder - subtotalSyp;
        return 'باقي ${_shortMoney(remaining)} ل.س للحد الأدنى';
    }
  }

  static String _shortMoney(int syp) {
    // 5,000 style — matches the design system's money format for terse cells.
    final s = syp.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
