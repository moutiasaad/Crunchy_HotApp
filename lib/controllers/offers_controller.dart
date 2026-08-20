import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/catalog_service.dart';
import '../services/coupons_service.dart';

/// Backs Screen 16 — Offers & coupons.
///
/// One controller drives both browse mode (Home banner / Profile 🎟️ tile)
/// and picker mode (from the Checkout coupon row). The state is small — a
/// hero deal, up to 3 secondary deals, a coupon list, and a selected code
/// used only in picker mode.
///
/// Sorting per spec §4: eligible first (by [Coupon.sortValue] desc), then
/// ineligible, expiring-soon last inside each group. Ineligible rows are
/// never hidden — the reason is the motivator.
class OffersController extends ChangeNotifier {
  final CatalogService _catalog;
  final CouponsService _coupons;
  OffersController(this._catalog, this._coupons);

  // Spec §3: only one hero; up to 3 secondary deals below it.
  static const int _maxSecondaryDeals = 3;

  // ─── State ─────────────────────────────────────────────────────
  final List<Offer>  _deals   = [];
  final List<Coupon> _coupons_= [];

  bool    _loading = false;
  bool    _loaded  = false;
  String? _error;

  String? _selectedCode;   // picker mode only

  // ─── View surface ──────────────────────────────────────────────
  bool     get loading   => _loading;
  String?  get error     => _error;
  bool     get hasError  => _error != null;

  Offer?          get hero            => _deals.isEmpty ? null : _deals.first;
  List<Offer>     get secondaryDeals  => _deals.length <= 1
      ? const []
      : List.unmodifiable(_deals.skip(1).take(_maxSecondaryDeals));

  /// The full coupon list, already sorted per §4. Callers get an unmodifiable
  /// view; render rows straight from it.
  List<Coupon> get coupons => List.unmodifiable(_coupons_);

  bool get hasAnyContent => hero != null || _coupons_.isNotEmpty;

  String? get selectedCode => _selectedCode;
  Coupon? get selected {
    if (_selectedCode == null) return null;
    for (final c in _coupons_) {
      if (c.code == _selectedCode) return c;
    }
    return null;
  }

  // ─── Loading ───────────────────────────────────────────────────
  Future<void> ensureLoaded({
    required int  subtotalSyp,
    required bool hasPriorOrders,
  }) async {
    if (_loaded || _loading) return;
    return refresh(subtotalSyp: subtotalSyp, hasPriorOrders: hasPriorOrders);
  }

  Future<void> refresh({
    required int  subtotalSyp,
    required bool hasPriorOrders,
  }) async {
    _loading = true;
    _error   = null;
    notifyListeners();

    try {
      // Fetch in parallel — a slow offers call shouldn't block coupons.
      final futures = await Future.wait([
        _fetchDeals(),
        _fetchCoupons(),
      ]);
      final deals   = futures[0] as List<Offer>;
      final coupons = futures[1] as List<Coupon>;

      _deals..clear()..addAll(deals);
      _coupons_
        ..clear()
        ..addAll(_sort(coupons,
            subtotalSyp: subtotalSyp, hasPriorOrders: hasPriorOrders));
      _loaded = true;
    } on ApiOfflineException {
      _error = 'ما في اتصال — العروض ممكن تكون قديمة';
    } catch (_) {
      _error = 'ما قدرنا نجيب العروض — جرّب مرة تانية';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Re-sort the existing coupon list without a network round-trip.
  /// Called when the cart subtotal changes while the screen is visible.
  void resortForCart({
    required int  subtotalSyp,
    required bool hasPriorOrders,
  }) {
    if (_coupons_.isEmpty) return;
    final resorted = _sort(
      List<Coupon>.from(_coupons_),
      subtotalSyp: subtotalSyp,
      hasPriorOrders: hasPriorOrders,
    );
    _coupons_
      ..clear()
      ..addAll(resorted);
    notifyListeners();
  }

  Future<List<Offer>> _fetchDeals() => _catalog.listOffers();

  Future<List<Coupon>> _fetchCoupons() => _coupons.list();

  List<Coupon> _sort(
    List<Coupon> input, {
    required int  subtotalSyp,
    required bool hasPriorOrders,
  }) {
    final eligible   = <Coupon>[];
    final ineligible = <Coupon>[];
    for (final c in input) {
      final r = c.eligibleFor(
        subtotalSyp: subtotalSyp,
        hasPriorOrders: hasPriorOrders,
      );
      (r == CouponIneligibility.none ? eligible : ineligible).add(c);
    }
    // Within each group: value desc, then expiring-soon last.
    int expiresRank(Coupon c) {
      if (c.endsAt == null) return 0;
      final daysLeft = c.endsAt!.difference(DateTime.now()).inDays;
      return daysLeft <= 1 ? 1 : 0; // "expiring soon" gets bumped down
    }

    int cmp(Coupon a, Coupon b) {
      final byExpire = expiresRank(a).compareTo(expiresRank(b));
      if (byExpire != 0) return byExpire;
      return b.sortValue.compareTo(a.sortValue);
    }

    eligible.sort(cmp);
    ineligible.sort(cmp);
    return [...eligible, ...ineligible];
  }

  // ─── Picker mode ───────────────────────────────────────────────
  /// Toggle-select semantics: picking the currently-selected code clears it.
  void select(Coupon c) {
    _selectedCode = (_selectedCode == c.code) ? null : c.code;
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedCode == null) return;
    _selectedCode = null;
    notifyListeners();
  }

  // ─── Browse mode ───────────────────────────────────────────────
  /// Copy the code to the clipboard. Returns true iff it succeeded — caller
  /// shows the "تم نسخ الكود" toast on true.
  Future<bool> copy(Coupon c) async {
    try {
      await Clipboard.setData(ClipboardData(text: c.code));
      return true;
    } catch (_) {
      return false;
    }
  }
}
