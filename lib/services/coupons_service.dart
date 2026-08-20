import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../models/models.dart';
import 'api_client.dart';

void _log(String msg) {
  if (kDebugMode) debugPrint('[Coupons] $msg');
}

/// Read-only browsing surface for `GET /api/v1/coupons`.
///
/// Public endpoint — works for guests too. Application is a separate flow
/// (`CartService.applyPromo`) so this service intentionally stays thin.
class CouponsService {
  final ApiClient _api;
  const CouponsService(this._api);

  Future<List<Coupon>> list() async {
    _log('list →');
    final data = await _api.get('/coupons') as Map<String, dynamic>;
    final r = (data['data'] as List)
        .map((j) => Coupon.fromJson(j as Map<String, dynamic>))
        .toList();
    _log('list ✓ (${r.length})');
    return r;
  }
}
