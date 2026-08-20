import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../models/models.dart';
import 'api_client.dart';
import 'app_config_service.dart';

void _log(String msg) {
  if (kDebugMode) debugPrint('[Cart] $msg');
}

/// Cart pricing + server sync.
///
/// [quote] is a **synchronous local estimate** used by [CartController]
/// today — the same math the server runs, kept in the app so the UI can
/// show a running total while items are being added. The delivery fee comes
/// from [AppConfigService] so admin edits to `business.delivery_fee_syp`
/// land in the app as soon as the config is (re)fetched.
///
/// The `Future`-returning methods hit the authoritative endpoints under
/// `/api/v1/cart/*`. They aren't wired into the controller yet; the
/// checkout screen will call them when it lands.
class CartService {
  final ApiClient        _api;
  final AppConfigService _config;
  const CartService(this._api, this._config);

  // ─────────────────────── Local estimate ───────────────────────

  PriceBreakdown quote(List<CartLine> lines, OrderMode mode) {
    final subtotal = lines.fold<int>(0, (s, l) => s + l.lineTotal);

    // Delivery mode → flat fee from live config; pickup → free. The old
    // "free once subtotal ≥ 60,000" rule was client-only spec drift — the
    // server doesn't apply it, so it made the mobile total under-quote by
    // the delivery fee at large baskets and the customer got charged more
    // on the receipt.
    final deliveryFee = mode == OrderMode.delivery ? _config.deliveryFeeSyp : 0;

    const discount = 0;
    return PriceBreakdown(
      subtotal:    subtotal,
      deliveryFee: deliveryFee,
      discount:    discount,
      total:       (subtotal + deliveryFee - discount).clamp(0, 1 << 62),
    );
  }

  // ─────────────────────── Server-backed ───────────────────────

  /// `GET /api/v1/cart` — returns the raw cart payload (see CartController@show).
  Future<Map<String, dynamic>> fetchCart() async {
    _log('fetchCart →');
    final r = await _api.get('/cart');
    _log('fetchCart ✓');
    return r as Map<String, dynamic>;
  }

  /// `POST /api/v1/cart/items` — merges/creates a line on the server.
  /// When [offerId] is set the server validates the offer is active + linked
  /// to [productId] and prices the line at offer_price (options still add).
  Future<Map<String, dynamic>> addItem({
    required int productId,
    int quantity = 1,
    List<int> optionIds = const [],
    String? note,
    int? offerId,
  }) async {
    _log('addItem → productId=$productId qty=$quantity opts=$optionIds offer=$offerId');
    try {
      final r = await _api.post('/cart/items', data: {
        'product_id': productId,
        if (offerId != null) 'offer_id': offerId,
        'quantity':   quantity,
        if (optionIds.isNotEmpty) 'options': optionIds,
        if (note != null && note.isNotEmpty) 'note': note,
      });
      _log('addItem ✓ productId=$productId');
      return r as Map<String, dynamic>;
    } catch (e) {
      _log('addItem ✗ productId=$productId: $e');
      rethrow;
    }
  }

  /// `PATCH /api/v1/cart/items/{item}` — set the quantity on a specific line.
  /// Sending `quantity: 0` deletes it.
  Future<Map<String, dynamic>> updateItem({required int itemId, required int quantity}) async {
    _log('updateItem → itemId=$itemId qty=$quantity');
    final r = await _api.patch('/cart/items/$itemId', data: {'quantity': quantity});
    _log('updateItem ✓ itemId=$itemId');
    return r as Map<String, dynamic>;
  }

  /// `DELETE /api/v1/cart/items/{item}`.
  Future<Map<String, dynamic>> removeItem(int itemId) async {
    _log('removeItem → itemId=$itemId');
    final r = await _api.delete('/cart/items/$itemId');
    _log('removeItem ✓ itemId=$itemId');
    return r as Map<String, dynamic>;
  }

  /// `POST /api/v1/cart/promo` — attaches a promo code to the cart.
  Future<Map<String, dynamic>> applyPromo(String code) async {
    final r = await _api.post('/cart/promo', data: {'code': code});
    return r as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> clearPromo() async {
    final r = await _api.delete('/cart/promo');
    return r as Map<String, dynamic>;
  }

  /// `POST /api/v1/cart/quote` — the **authoritative** money endpoint (CDC W-22).
  /// Use this on the checkout screen before showing the "Place order" button.
  Future<Map<String, dynamic>> fetchQuote({
    required OrderMode mode,
    int? addressId,
    int? branchId,
    int redeemPoints = 0,
  }) async {
    final r = await _api.post('/cart/quote', data: {
      'type':          mode == OrderMode.delivery ? 'delivery' : 'pickup',
      if (addressId != null) 'address_id': addressId,
      if (branchId  != null) 'branch_id':  branchId,
      if (redeemPoints > 0)  'redeem_points': redeemPoints,
    });
    return r as Map<String, dynamic>;
  }
}
