import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/loyalty_status.dart';
import '../models/reward.dart';
import '../services/api_client.dart';
import '../services/loyalty_service.dart';

class LoyaltyController extends ChangeNotifier {
  final LoyaltyService _service;
  LoyaltyController(this._service);

  LoyaltyStatus  _status  = LoyaltyStatus.empty;
  List<Reward>   _rewards = const [];
  List<MyCoupon> _coupons = const [];
  bool           _loading = false;
  bool           _rewardsLoading = false;
  bool           _couponsLoading = false;
  String?        _error;
  String?        _rewardsError;
  String?        _couponsError;
  bool           _hasLoaded = false;

  LoyaltyStatus  get status         => _status;
  List<Reward>   get rewards        => _rewards;
  List<MyCoupon> get coupons        => _coupons;
  List<MyCoupon> get activeCoupons  =>
      _coupons.where((c) => c.isActive).toList(growable: false);
  bool           get loading        => _loading;
  bool           get rewardsLoading => _rewardsLoading;
  bool           get couponsLoading => _couponsLoading;
  String?        get error          => _error;
  String?        get rewardsError   => _rewardsError;
  String?        get couponsError   => _couponsError;
  bool           get hasLoaded      => _hasLoaded;

  int get balance                   => _status.balance;

  Future<void> load() async {
    _loading = true;
    _error   = null;
    notifyListeners();
    try {
      _status    = await _service.fetch();
      _hasLoaded = true;
    } on ApiUnauthorizedException {
      _error = 'الرجاء تسجيل الدخول لعرض النقاط';
    } catch (_) {
      _error = 'ما قدرنا نجيب رصيد النقاط — جرّب مرة تانية';
    } finally {
      _loading = false;
      notifyListeners();
    }
    unawaited(loadRewards());
    unawaited(loadCoupons());
  }

  Future<void> loadRewards() async {
    _rewardsLoading = true;
    _rewardsError   = null;
    notifyListeners();
    try {
      _rewards = await _service.rewards();
    } catch (_) {
      _rewardsError = 'ما قدرنا نجيب قائمة المكافآت';
    } finally {
      _rewardsLoading = false;
      notifyListeners();
    }
  }

  /// Fetch the customer's personal coupon wallet — active + used + expired.
  /// Cheap and idempotent; called from Rewards + Checkout screens.
  Future<void> loadCoupons() async {
    _couponsLoading = true;
    _couponsError   = null;
    notifyListeners();
    try {
      _coupons = await _service.coupons();
    } catch (_) {
      _couponsError = 'ما قدرنا نجيب كوبوناتك';
    } finally {
      _couponsLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  /// Spend points on a reward. Returns the personal coupon on success.
  /// On failure, throws — caller shows the error toast.
  Future<RewardRedemption> redeem(String rewardId) async {
    final result = await _service.redeem(rewardId);
    // Server is the source of truth for balance; reflect it locally so the
    // header animates down without an extra round-trip.
    _status = LoyaltyStatus(
      balance: result.newBalance,
      rules:   _status.rules,
      ledger:  _status.ledger,
    );
    notifyListeners();
    // Refresh the wallet so the new coupon appears in "My Coupons" without
    // the customer having to leave and come back.
    unawaited(loadCoupons());
    return result;
  }

  void reset() {
    _status    = LoyaltyStatus.empty;
    _rewards   = const [];
    _coupons   = const [];
    _hasLoaded = false;
    notifyListeners();
  }
}
