import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../models/loyalty_status.dart';
import '../models/reward.dart';
import 'api_client.dart';

void _log(String msg) {
  if (kDebugMode) debugPrint('[Loyalty] $msg');
}

/// Wraps the `/api/v1/loyalty/*` endpoints — balance + ledger + admin
/// rewards catalogue + redeem.
class LoyaltyService {
  final ApiClient _api;
  const LoyaltyService(this._api);

  /// `GET /loyalty` → balance + rules + last 30 ledger entries.
  Future<LoyaltyStatus> fetch() async {
    _log('fetch →');
    try {
      final data = await _api.get('/loyalty') as Map<String, dynamic>;
      final s = LoyaltyStatus.fromJson(data);
      _log('fetch ✓ balance=${s.balance} entries=${s.ledger.length}');
      return s;
    } catch (e) {
      _log('fetch ✗ $e');
      rethrow;
    }
  }

  /// `GET /loyalty/rewards` → the admin-managed reward catalogue.
  Future<List<Reward>> rewards() async {
    _log('rewards →');
    final data = await _api.get('/loyalty/rewards') as Map<String, dynamic>;
    final list = (data['data'] as List)
        .map((j) => Reward.fromJson(j as Map<String, dynamic>))
        .toList();
    _log('rewards ✓ ${list.length}');
    return list;
  }

  /// `GET /loyalty/coupons` → the user's redeemed coupons (wallet).
  /// Includes active + used + expired so the UI can filter.
  Future<List<MyCoupon>> coupons() async {
    _log('coupons →');
    final data = await _api.get('/loyalty/coupons') as Map<String, dynamic>;
    final list = (data['data'] as List)
        .map((j) => MyCoupon.fromJson(j as Map<String, dynamic>))
        .toList();
    _log('coupons ✓ ${list.length}');
    return list;
  }

  /// `POST /loyalty/redeem { reward_id }` → deducts points server-side and
  /// mints a single-use promo code for this user. Server is race-safe via
  /// row-level lock so concurrent taps can't double-spend.
  Future<RewardRedemption> redeem(String rewardId) async {
    _log('redeem → rewardId=$rewardId');
    final data = await _api.post('/loyalty/redeem', data: {
      'reward_id': int.parse(rewardId),
    }) as Map<String, dynamic>;
    _log('redeem ✓ code=${data['coupon']?['code']}');
    return RewardRedemption.fromJson(data);
  }
}
