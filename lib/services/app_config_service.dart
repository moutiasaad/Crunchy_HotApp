import 'package:flutter/foundation.dart';

import 'api_client.dart';

void _log(String msg) {
  if (kDebugMode) debugPrint('[Config] $msg');
}

/// Live public config from `GET /api/v1/config` — currently just the flat
/// delivery fee + loyalty notice, but this is where any other admin-editable
/// business value (min-order, prep minutes, …) will land.
///
/// [load] is called from:
///   - `main.dart` at app boot (fire-and-forget)
///   - `CrunchyHotApp` on `AppLifecycleState.resumed` (app returns from bg)
///   - `CartScreen` on TabActivate + retap + first-mount
///   - `CheckoutScreen` on first frame
///
/// The server caches the payload for 60 s so re-hitting is cheap. On the
/// very first launch (offline boot) the fallback delivery fee is used until
/// a load succeeds; the server's `PricingEngine` is authoritative when
/// `POST /orders` runs, so this fallback never causes a wrong charge — only
/// a briefly wrong preview.
class AppConfigService extends ChangeNotifier {
  final ApiClient _api;
  AppConfigService(this._api);

  /// Matches `SettingsSeeder::business.delivery_fee_syp` on the server so
  /// a first-boot fallback lines up with what a freshly-seeded prod DB
  /// would return. Admin edits move the DB value; the app picks them up on
  /// the next `load()`.
  static const int _seedDefaultDeliveryFeeSyp = 5000;

  /// Matches `SettingsSeeder::business.loyalty.redeem_per_1000_syp`. Server's
  /// `PricingEngine` applies discount as `floor(points / rate) * 1000` SYP —
  /// the app uses the same formula in Checkout so the preview matches.
  static const int _seedDefaultLoyaltyRedeemRate = 100;

  int    _deliveryFeeSyp          = _seedDefaultDeliveryFeeSyp;
  int    _loyaltyRedeemPer1000Syp = _seedDefaultLoyaltyRedeemRate;
  String _loyaltyNoticeAr         = '';
  bool   _loaded                  = false;

  int    get deliveryFeeSyp          => _deliveryFeeSyp;
  /// Points required per 1000 SYP of discount at Checkout (server-authoritative).
  int    get loyaltyRedeemPer1000Syp => _loyaltyRedeemPer1000Syp;
  /// Admin-editable notice shown at the top of the Rewards screen. Empty
  /// string means the admin hasn't written a message — screens should hide
  /// the notice card in that case.
  String get loyaltyNoticeAr         => _loyaltyNoticeAr;
  bool   get isLoaded                => _loaded;

  Future<void> load() async {
    try {
      _log('load → GET /config');
      final resp = await _api.get('/config');
      if (resp is! Map) {
        _log('load ✗ non-map response');
        return;
      }
      final business = resp['business'];
      if (business is! Map) {
        _log('load ✗ missing business key');
        return;
      }

      var changed = false;

      final fee = (business['delivery_fee_syp'] as num?)?.toInt();
      if (fee != null && fee >= 0 && fee != _deliveryFeeSyp) {
        _log('load ✓ delivery_fee_syp $_deliveryFeeSyp → $fee');
        _deliveryFeeSyp = fee;
        changed = true;
      }

      final redeemRate = (business['loyalty_redeem_per_1000_syp'] as num?)?.toInt();
      if (redeemRate != null && redeemRate > 0 && redeemRate != _loyaltyRedeemPer1000Syp) {
        _log('load ✓ loyalty_redeem_per_1000_syp $_loyaltyRedeemPer1000Syp → $redeemRate');
        _loyaltyRedeemPer1000Syp = redeemRate;
        changed = true;
      }

      final notice = (business['loyalty_notice_ar'] as String?)?.trim() ?? '';
      if (notice != _loyaltyNoticeAr) {
        _loyaltyNoticeAr = notice;
        changed = true;
      }

      final wasLoaded = _loaded;
      _loaded = true;
      if (changed || !wasLoaded) notifyListeners();
    } catch (e) {
      _log('load ✗ $e');
      // Silent — keep the previous values. Screens should render sensibly
      // with defaults; the server is authoritative wherever it matters.
    }
  }
}
