import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../models/models.dart';
import 'api_client.dart';

void _log(String msg) {
  if (kDebugMode) debugPrint('[Order] $msg');
}

/// Thin façade for `/api/v1/orders` — not yet consumed by any controller.
/// The order-tracking + checkout screens will bind to this when they land.
class OrderService {
  final ApiClient _api;
  const OrderService(this._api);

  /// `GET /orders` — paginated list of the signed-in user's orders.
  Future<List<Map<String, dynamic>>> list() async {
    _log('list →');
    final r = await _api.get('/orders') as Map<String, dynamic>;
    final items = ((r['data'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .toList();
    _log('list ✓ (${items.length} orders)');
    return items;
  }

  /// `GET /orders/{number}` — full detail for one order.
  Future<Map<String, dynamic>> show(String number) async {
    _log('show → $number');
    final r = await _api.get('/orders/$number') as Map<String, dynamic>;
    _log('show ✓ $number');
    return (r['data'] as Map<String, dynamic>?) ?? r;
  }

  /// `POST /orders` — checkout. Cart is server-side; we only send delivery mode + refs.
  Future<Map<String, dynamic>> place({
    required OrderMode mode,
    int? addressId,
    int? branchId,
    String paymentMethod = 'cash_on_delivery',
    String? note,
    DateTime? scheduledFor,
  }) async {
    final type = mode == OrderMode.delivery ? 'delivery' : 'pickup';
    _log('place → type=$type addressId=$addressId branchId=$branchId pay=$paymentMethod');
    try {
      final r = await _api.post('/orders', data: {
        'type':           type,
        if (addressId != null) 'address_id':     addressId,
        if (branchId  != null) 'branch_id':      branchId,
        'payment_method': paymentMethod,
        if (note != null && note.isNotEmpty) 'note': note,
        if (scheduledFor != null) 'scheduled_for': scheduledFor.toIso8601String(),
        'channel': 'app',
      }) as Map<String, dynamic>;

      // Resource response is envelope-wrapped: { data: { id, order_number, ... } }
      final data = (r['data'] as Map<String, dynamic>?) ?? r;
      final orderNumber = data['order_number'] as String? ?? 'unknown';
      _log('place ✓ order_number=$orderNumber');
      return r;
    } catch (e) {
      _log('place ✗ $e');
      rethrow;
    }
  }

  Future<void> cancel(String number, {String? reason}) async {
    _log('cancel → $number reason="$reason"');
    await _api.post('/orders/$number/cancel', data: {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
    _log('cancel ✓ $number');
  }

  Future<void> reorder(String number) async {
    _log('reorder → $number');
    await _api.post('/orders/$number/reorder');
    _log('reorder ✓ $number');
  }

  Future<void> review(String number, {required int rating, String? comment}) async {
    _log('review → $number rating=$rating');
    await _api.post('/orders/$number/review', data: {
      'rating': rating,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    });
    _log('review ✓ $number');
  }
}
