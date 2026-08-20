import 'product.dart' show Product;

/// A top-level menu category shown on Home + Menu.
class MenuCategory {
  final String slug;
  final String labelAr;
  final String labelEn;
  final String emoji;
  final int    sortOrder;

  const MenuCategory({
    required this.slug,
    required this.labelAr,
    required this.labelEn,
    required this.emoji,
    this.sortOrder = 0,
  });

  /// Parse one element of `data[]` from `GET /api/v1/categories`.
  ///
  /// The API's `icon` field may hold either a real emoji glyph or an
  /// identifier like `broasted`. If it's an identifier / empty, we fall
  /// back to a stock emoji derived from the slug.
  factory MenuCategory.fromJson(Map<String, dynamic> j) {
    final slug    = (j['slug'] ?? '') as String;
    final iconRaw = (j['icon'] as String?)?.trim();
    final emoji   = (iconRaw != null &&
                     iconRaw.isNotEmpty &&
                     !RegExp(r'^[a-zA-Z_-]+$').hasMatch(iconRaw))
        ? iconRaw
        : Product.emojiForCategory(slug);

    return MenuCategory(
      slug:       slug,
      labelAr:   (j['name_ar']    ?? '') as String,
      labelEn:   (j['name_en']    ?? '') as String,
      emoji:      emoji,
      sortOrder: (j['sort_order'] ?? 0)  as int,
    );
  }
}
