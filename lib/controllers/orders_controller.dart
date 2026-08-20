import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/order_service.dart';

/// Backs Order History (screen 17) and the active-order banner on Home.
///
/// Talks to `GET /api/v1/orders` (paginated list, latest first). Line-item
/// detail comes from `_service.show(number)` when the user opens the sheet.
class OrdersController extends ChangeNotifier {
  final OrderService _service;
  OrdersController(this._service);

  List<Order> _orders = const [];
  bool        _loading = false;
  String?     _error;
  bool        _hasLoaded = false;

  List<Order> get orders     => List.unmodifiable(_orders);
  bool        get loading    => _loading;
  String?     get error      => _error;
  bool        get hasLoaded  => _hasLoaded;

  Order? get activeOrder =>
      _orders.where((o) => o.isActive).firstOrNull;

  List<Order> get historyOrders =>
      _orders.where((o) => !o.isActive).toList();

  Future<void> load() async {
    _loading = true;
    _error   = null;
    notifyListeners();

    try {
      final rows = await _service.list();
      _orders = rows.map(Order.fromListJson).toList();
      _hasLoaded = true;
    } catch (_) {
      _error = 'ما قدرنا نجيب الطلبات — جرّب مرة تانية';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  /// Used by Checkout after a successful place to add the freshly-placed
  /// order into history (so the user can already see it in "طلباتي").
  void addLocal(Order o) {
    _orders = [o, ..._orders];
    notifyListeners();
  }

  /// Wipe everything (used on sign-out).
  void reset() {
    _orders = const [];
    _hasLoaded = false;
    notifyListeners();
  }
}
