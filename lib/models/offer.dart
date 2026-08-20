/// A weekly deal — shown as the Home banner and the hero of Screen 16 Offers.
///
/// Backed by `GET /api/v1/offers` (see `OfferResource.php`). New fields
/// (`descriptionAr`, `endsAt`, `productId`) are nullable so the existing
/// Home banner keeps rendering when they're missing.
class Offer {
  final String    id;
  final String    kickerAr;
  final String    kickerEn;
  final String    titleAr;
  final String    titleEn;
  final String?   descriptionAr;
  final int       price;
  final int?      originalPrice;
  final String    emoji;
  final String?   imageUrl;
  final DateTime? endsAt;
  final String?   productId;
  final String?   productSlug;     // enables /products/{slug} fetch for bridge
  final String?   productName;     // shown on offer detail so buyer sees what they're getting

  const Offer({
    required this.id,
    required this.kickerAr,
    required this.kickerEn,
    required this.titleAr,
    required this.titleEn,
    required this.price,
    required this.emoji,
    this.descriptionAr,
    this.originalPrice,
    this.imageUrl,
    this.endsAt,
    this.productId,
    this.productSlug,
    this.productName,
  });

  /// Parse one element of `data[]` from `GET /api/v1/offers`.
  factory Offer.fromJson(Map<String, dynamic> j) {
    final title    = (j['title'] ?? '') as String;
    final desc     = j['description'] as String?;
    final offerP   = (j['offer_price']    as Map<String, dynamic>?) ?? const {};
    final origP    =  j['original_price'] as Map<String, dynamic>?;
    final endsRaw  =  j['ends_at']         as String?;
    final product  = (j['product']         as Map<String, dynamic>?);
    return Offer(
      id:             j['id'].toString(),
      kickerAr:      'عرض هذا الأسبوع',
      kickerEn:      "This week's deal",
      titleAr:        title,
      titleEn:        title,     // OfferResource doesn't split locales.
      descriptionAr:  desc,
      price:         (offerP['amount'] ?? 0) as int,
      originalPrice:  origP?['amount'] as int?,
      emoji:         '🍽️',
      imageUrl:       j['image'] as String?,
      endsAt:         endsRaw == null ? null : DateTime.tryParse(endsRaw),
      productId:      product?['id']?.toString(),
      productSlug:    product?['slug'] as String?,
      productName:    product?['name'] as String?,
    );
  }

  /// Savings in SYP (may be null when the offer has no original price).
  int? get savings {
    final orig = originalPrice;
    return (orig == null || orig <= price) ? null : (orig - price);
  }
}
