/// The authoritative totals returned by `CartService.quote()`.
/// Everything is integer SYP — no floats.
class PriceBreakdown {
  final int subtotal;
  final int deliveryFee;
  final int discount;
  final int total;

  const PriceBreakdown({
    required this.subtotal,
    required this.deliveryFee,
    required this.discount,
    required this.total,
  });

  static const zero = PriceBreakdown(
    subtotal: 0, deliveryFee: 0, discount: 0, total: 0,
  );
}
