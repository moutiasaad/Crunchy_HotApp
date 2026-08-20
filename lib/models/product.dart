import 'option_group.dart';

/// A menu item.
///
/// Fields that don't come from the API (`emoji`, `popularity`, `prepMinutes`,
/// `spicy`) have sensible defaults; [Product.fromJson] fills them from
/// derived values (category slug → emoji, `badge_color == 'red'` → spicy, …).
class Product {
  final String id;
  final String slug;                    // product's own slug for /products/{slug}
  final String nameAr;
  final String nameEn;
  final String descriptionAr;
  final String descriptionEn;
  final int    price;
  final String emoji;
  final String? imageUrl;
  final int    popularity;
  final int    prepMinutes;
  final bool   spicy;
  final bool   isFeatured;
  final String? kcal;
  final String? badgeLabel;
  final String? badgeColor;             // 'red' | 'yellow' | 'green'
  final String categorySlug;
  final double ratingAvg;               // 0.0 – 5.0
  final int    ratingCount;
  final List<OptionGroup> optionGroups; // empty when the product has none

  const Product({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.price,
    required this.categorySlug,
    this.slug = '',
    this.descriptionAr = '',
    this.descriptionEn = '',
    this.emoji = '🍽️',
    this.imageUrl,
    this.popularity = 50,
    this.prepMinutes = 10,
    this.spicy = false,
    this.isFeatured = false,
    this.kcal,
    this.badgeLabel,
    this.badgeColor,
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.optionGroups = const [],
  });

  /// Drinks & desserts don't expose the spice segmented on Item Detail.
  bool get spiceApplicable => categorySlug != 'drinks' && categorySlug != 'desserts';

  /// Parse one element of `data[]` from `GET /api/v1/products`.
  factory Product.fromJson(Map<String, dynamic> j) {
    final cat        = (j['category'] as Map<String, dynamic>?) ?? const {};
    final priceObj   = (j['price']    as Map<String, dynamic>?) ?? const {};
    final ratingObj  = (j['rating']   as Map<String, dynamic>?) ?? const {};
    final slug       = (cat['slug'] as String?) ?? '';
    final badgeColor = j['badge_color'] as String?;
    final isFeat     = (j['is_featured'] ?? false) as bool;

    return Product(
      id:            j['id'].toString(),
      slug:         (j['slug']       ?? '') as String,
      nameAr:       (j['name_ar']    ?? '') as String,
      nameEn:       (j['name_en']    ?? '') as String,
      descriptionAr:(j['short_desc'] ?? '') as String,
      descriptionEn:(j['name_en']    ?? '') as String,
      price:        (priceObj['amount'] ?? 0) as int,
      emoji:         emojiForCategory(slug),
      imageUrl:      j['image'] as String?,
      popularity:  ((ratingObj['count'] ?? 0) as int) + (isFeat ? 50 : 0),
      spicy:         badgeColor == 'red',
      isFeatured:    isFeat,
      badgeLabel:    j['badge_label'] as String?,
      badgeColor:    badgeColor,
      categorySlug:  slug,
      ratingAvg:    (ratingObj['avg']   is num ? (ratingObj['avg']   as num).toDouble() : 0.0),
      ratingCount:  (ratingObj['count'] ?? 0) as int,
      optionGroups: ((j['option_groups'] as List?) ?? const [])
          .map((g) => OptionGroup.fromJson(g as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Public so [MenuCategory] can share the same mapping.
  static String emojiForCategory(String slug) => switch (slug) {
        'broasted'   => '🍗',
        'shawarma'   => '🌯',
        'burgers'    => '🍔',
        'sandwiches' => '🥪',
        'drinks'     => '🥤',
        _            => '🍽️',
      };
}
