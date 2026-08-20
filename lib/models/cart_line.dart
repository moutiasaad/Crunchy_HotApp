import 'addon.dart';
import 'enums.dart';
import 'product.dart';

/// A single line in the cart — one product + its picked options and quantity.
///
/// [offerId] / [offerUnitPrice] are set when the line was added from an active
/// offer. The unit price then uses the offer price (options still add on top),
/// and the server receives `offer_id` in the add-to-cart body so the
/// authoritative quote matches what the user saw.
class CartLine {
  final String       id;
  final Product      product;
  final int          quantity;
  final Spice        spice;
  final List<Addon>  addons;
  final String?      note;
  final String?      offerId;
  final int?         offerUnitPrice;

  const CartLine({
    required this.id,
    required this.product,
    required this.quantity,
    this.spice = Spice.mild,
    this.addons = const [],
    this.note,
    this.offerId,
    this.offerUnitPrice,
  });

  bool get isFromOffer => offerId != null;

  /// Unit price = (offer price if this line came from an offer, else product
  /// base price) + sum of addon deltas.
  int get unitPrice =>
      (offerUnitPrice ?? product.price) +
      addons.fold<int>(0, (s, a) => s + a.price);

  int get lineTotal => unitPrice * quantity;

  CartLine copyWith({
    Product? product,
    int? quantity,
    Spice? spice,
    List<Addon>? addons,
    String? note,
  }) => CartLine(
        id: id,
        product: product ?? this.product,
        quantity: quantity ?? this.quantity,
        spice: spice ?? this.spice,
        addons: addons ?? this.addons,
        note: note ?? this.note,
        offerId: offerId,
        offerUnitPrice: offerUnitPrice,
      );

  // ──────────────── Local persistence ────────────────
  // A private shape — NOT the server contract. Product/Addon inline as
  // minimal display snapshots so we can rehydrate the cart on cold start
  // without waiting for a menu re-fetch. `refreshPrices()` overwrites the
  // product snapshot once the user opens the cart tab.

  Map<String, dynamic> toJson() => {
        'id':             id,
        'quantity':       quantity,
        'spice':          spice.name,
        if (note != null)          'note':           note,
        if (offerId != null)       'offerId':        offerId,
        if (offerUnitPrice != null)'offerUnitPrice': offerUnitPrice,
        'product': {
          'id':           product.id,
          'slug':         product.slug,
          'nameAr':       product.nameAr,
          'nameEn':       product.nameEn,
          'descriptionAr':product.descriptionAr,
          'price':        product.price,
          'imageUrl':     product.imageUrl,
          'emoji':        product.emoji,
          'categorySlug': product.categorySlug,
        },
        'addons': addons
            .map((a) => {
                  'id':     a.id,
                  'nameAr': a.nameAr,
                  'nameEn': a.nameEn,
                  'price':  a.price,
                })
            .toList(),
      };

  factory CartLine.fromJson(Map<String, dynamic> j) {
    final p = (j['product'] as Map).cast<String, dynamic>();
    return CartLine(
      id:       j['id']       as String,
      quantity: j['quantity'] as int,
      spice: Spice.values.firstWhere(
        (s) => s.name == j['spice'],
        orElse: () => Spice.mild,
      ),
      note:            j['note']           as String?,
      offerId:         j['offerId']        as String?,
      offerUnitPrice: (j['offerUnitPrice'] as num?)?.toInt(),
      product: Product(
        id:            p['id']           as String,
        slug:          p['slug']         as String? ?? '',
        nameAr:        p['nameAr']       as String? ?? '',
        nameEn:        p['nameEn']       as String? ?? '',
        descriptionAr: p['descriptionAr']as String? ?? '',
        price:        (p['price']        as num?)?.toInt() ?? 0,
        imageUrl:      p['imageUrl']     as String?,
        emoji:         p['emoji']        as String? ?? '🍽️',
        categorySlug:  p['categorySlug'] as String? ?? '',
      ),
      addons: ((j['addons'] as List?) ?? const [])
          .map((raw) {
            final a = (raw as Map).cast<String, dynamic>();
            return Addon(
              id:     a['id']     as String,
              nameAr: a['nameAr'] as String? ?? '',
              nameEn: a['nameEn'] as String? ?? '',
              price: (a['price']  as num?)?.toInt() ?? 0,
            );
          })
          .toList(),
    );
  }
}
