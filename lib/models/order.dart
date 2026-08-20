import 'addon.dart';
import 'branch.dart';
import 'enums.dart';
import 'product.dart';

/// A single reorderable line inside an [Order] — same shape as a `CartLine`
/// but snapshotted at order-placement time.
class OrderLine {
  final Product     product;
  final int         quantity;
  final Spice       spice;
  final List<Addon> addons;
  final String?     note;
  final int         unitPrice;   // frozen at order time (product.price + addons)
  final int         lineTotal;   // unitPrice * quantity

  const OrderLine({
    required this.product,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.spice   = Spice.mild,
    this.addons  = const [],
    this.note,
  });

  /// Compact options note: `حار · جبنة إضافية`.
  String get optionsNote {
    final parts = <String>[
      _spiceLabel(spice),
      ...addons.map((a) => a.nameAr),
    ];
    return parts.join(' · ');
  }

  static String _spiceLabel(Spice s) => switch (s) {
        Spice.mild     => 'عادي',
        Spice.hot      => 'حار',
        Spice.extraHot => 'حار جداً',
      };
}

/// A placed order — history entry + tracking source.
class Order {
  final String       id;
  final String       orderNumber;   // e.g. "CH-2481"
  final List<OrderLine> lines;
  final OrderMode    mode;
  final String?      addressLine;   // for delivery
  final Branch?      branch;        // for pickup
  final OrderStatus  status;
  final PayMethod    paymentMethod;
  final int          subtotal;
  final int          deliveryFee;
  final int          discount;
  final int          total;
  final DateTime     createdAt;
  final int?         rating;        // null when the user hasn't rated yet

  const Order({
    required this.id,
    required this.orderNumber,
    required this.lines,
    required this.mode,
    required this.status,
    required this.paymentMethod,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.createdAt,
    this.discount = 0,
    this.addressLine,
    this.branch,
    this.rating,
  });

  /// Parse the `data[]` element from `GET /api/v1/orders` (list resource).
  /// The list response is intentionally slim — no line items, no
  /// address — so [lines] is empty. Fetch [OrderService.show] for full
  /// detail when opening the details sheet.
  factory Order.fromListJson(Map<String, dynamic> j) {
    final total  = (j['total'] as Map<String, dynamic>?) ?? const {};
    final branch = j['branch'] as Map<String, dynamic>?;
    return Order(
      id:            (j['order_number'] ?? '') as String,
      orderNumber:   (j['order_number'] ?? '') as String,
      lines:         const [],
      mode:          parseMode(j['type'] as String?),
      status:        parseStatus(j['status'] as String?),
      paymentMethod: PayMethod.cash,   // list resource omits this — refetch on details
      subtotal:      0,
      deliveryFee:   0,
      total:        (total['amount'] ?? 0) as int,
      createdAt:     DateTime.tryParse((j['created_at'] ?? '') as String) ?? DateTime.now(),
      branch: branch == null ? null : Branch(
        id:            branch['id'].toString(),
        nameAr:        (branch['name'] ?? '') as String,
        nameEn:        (branch['name'] ?? '') as String,
        shortNameAr:   (branch['name'] ?? '') as String,
        addressAr:     '',
        phone:         '',
        isOpen:        true,
        hoursText:     '',
        lat: 0, lng: 0,
      ),
    );
  }

  /// Public so Tracking's poll loop can reuse the same mapping.
  static OrderMode parseMode(String? raw) {
    switch (raw) {
      case 'pickup':   return OrderMode.pickup;
      case 'delivery':
      default:         return OrderMode.delivery;
    }
  }

  /// Public so Tracking's poll loop can reuse the same mapping.
  ///
  /// Server enum (App\Enums\OrderStatus): draft / pending / accepted /
  /// preparing / out_for_delivery / ready_for_pickup / completed / rejected /
  /// cancelled. We collapse this into the 5-step client model:
  ///   received  → order just landed on our side (draft/pending/accepted)
  ///   preparing → kitchen is cooking (preparing)
  ///   onTheWay  → out for delivery OR ready for pickup at the branch
  ///   delivered → fulfilled (completed / delivered / picked_up)
  ///   cancelled → cancelled or rejected
  static OrderStatus parseStatus(String? raw) {
    switch (raw) {
      case 'draft':
      case 'pending':
      case 'accepted':
      case 'received':          return OrderStatus.received;

      case 'preparing':         return OrderStatus.preparing;

      case 'on_the_way':
      case 'out_for_delivery':
      case 'ready':
      case 'ready_for_pickup':  return OrderStatus.onTheWay;

      case 'completed':
      case 'delivered':
      case 'picked_up':         return OrderStatus.delivered;

      case 'rejected':
      case 'cancelled':         return OrderStatus.cancelled;

      default:                  return OrderStatus.received;
    }
  }

  int  get itemCount     => lines.fold(0, (s, l) => s + l.quantity);
  bool get isDelivered   => status == OrderStatus.delivered;
  bool get isCancelled   => status == OrderStatus.cancelled;
  bool get isPickup      => mode == OrderMode.pickup;

  /// Active = live tracking eligible (received / preparing / onTheWay).
  bool get isActive =>
      status == OrderStatus.received  ||
      status == OrderStatus.preparing ||
      status == OrderStatus.onTheWay;

  /// Progress fraction 0.0 – 1.0 for the active-card progress bar (spec §3).
  double get progress => switch (status) {
        OrderStatus.received  => 0.25,
        OrderStatus.preparing => 0.50,
        OrderStatus.onTheWay  => 0.75,
        OrderStatus.delivered => 1.00,
        _                      => 0.00,
      };

  /// "Rate" is available on delivered orders that haven't been rated yet,
  /// within 7 days (spec §4 / §7).
  bool get canRate =>
      rating == null &&
      isDelivered &&
      DateTime.now().difference(createdAt) < const Duration(days: 7);

  /// "Reorder" is available except on cancelled orders older than 30 days
  /// (spec §4).
  bool get canReorder =>
      !(isCancelled &&
          DateTime.now().difference(createdAt) > const Duration(days: 30));

  /// One-line summary: `بروستد كرانشي + دبل برجر` or
  /// `بروستد كرانشي + صنفين`.
  String get displayItems {
    if (lines.isEmpty) return '';
    if (lines.length == 1) return lines.first.product.nameAr;
    if (lines.length == 2) return '${lines[0].product.nameAr} + ${lines[1].product.nameAr}';
    final rest = lines.length - 1;
    return '${lines.first.product.nameAr} + ${_countLabel(rest)}';
  }

  static String _countLabel(int n) => switch (n) {
        1 => 'صنف',
        2 => 'صنفين',
        _ => '$n أصناف',
      };
}
