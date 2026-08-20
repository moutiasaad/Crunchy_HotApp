import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Live public config from `GET /api/v1/config` — currently just the flat
/// delivery fee, but this is where any other admin-editable business value
/// (min-order, prep minutes, …) will land.
///
/// Fetched once at app boot and again when the checkout screen mounts so a
/// mid-session admin change lands before the customer commits. Server caches
/// the payload for 60 seconds, so re-hitting the endpoint is cheap.
///
/// The client keeps a 5,000 SYP fallback so cart totals still render if the
/// very first fetch fails (offline boot); the server is authoritative when
/// `POST /orders` runs, so this fallback never causes a wrong charge — only
/// a briefly wrong preview.
class AppConfigService extends ChangeNotifier {
  final ApiClient _api;
  AppConfigService(this._api);

  static const int _fallbackDeliveryFeeSyp = 5000;

  int    _deliveryFeeSyp  = _fallbackDeliveryFeeSyp;
  String _loyaltyNoticeAr = '';
  bool   _loaded          = false;

  int    get deliveryFeeSyp  => _deliveryFeeSyp;
  /// Admin-editable notice shown at the top of the Rewards screen. Empty
  /// string means the admin hasn't written a message — screens should hide
  /// the notice card in that case.
  String get loyaltyNoticeAr => _loyaltyNoticeAr;
  bool   get isLoaded        => _loaded;

  Future<void> load() async {
    try {
      final resp = await _api.get('/config');
      if (resp is! Map) return;
      final business = resp['business'];
      if (business is! Map) return;

      var changed = false;

      final fee = (business['delivery_fee_syp'] as num?)?.toInt();
      if (fee != null && fee >= 0 && fee != _deliveryFeeSyp) {
        _deliveryFeeSyp = fee;
        changed = true;
      }

      final notice = (business['loyalty_notice_ar'] as String?)?.trim() ?? '';
      if (notice != _loyaltyNoticeAr) {
        _loyaltyNoticeAr = notice;
        changed = true;
      }

      _loaded = true;
      if (changed) notifyListeners();
    } catch (_) {
      // Silent — keep the previous values. Screens should render sensibly
      // with defaults; the server is authoritative wherever it matters.
    }
  }
}
