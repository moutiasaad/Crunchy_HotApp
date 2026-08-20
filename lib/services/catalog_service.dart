import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../models/models.dart';
import 'api_client.dart';

void _log(String msg) {
  if (kDebugMode) debugPrint('[Catalog] $msg');
}

/// Fetches menu data from `GET /api/v1/{categories,products,offers}`.
///
/// Products, offers and search **always** hit the server — never fall back
/// to the local seed. That's on purpose: seed products have string IDs
/// (`p1`..`p12`) that can't be POSTed to `/cart/items` (server expects real
/// int product ids), so a silent fallback would let the user add un-
/// checkoutable items to their cart. On failure we rethrow → the calling
/// controller surfaces an error state and the screen offers a retry.
///
/// Categories still fall back to a static seed when the API blips, because
/// the id isn't used in POST bodies — only the slug for the menu filter.
class CatalogService {
  final ApiClient _api;
  const CatalogService(this._api);

  // ─────────────────────── Public API ───────────────────────

  Future<List<MenuCategory>> getCategories() async {
    _log('getCategories →');
    try {
      final data = await _api.get('/categories') as Map<String, dynamic>;
      final r = (data['data'] as List)
          .map((j) => MenuCategory.fromJson(j as Map<String, dynamic>))
          .toList();
      _log('getCategories ✓ (${r.length} from API)');
      return r;
    } on Object catch (e) {
      _log('getCategories ✗ falling back to seed ($e)');
      return _seedCategories;
    }
  }

  Future<List<Product>> getFeatured() async {
    _log('getFeatured →');
    // Laravel's `boolean` validator accepts 1/0/"1"/"0"/true/false but NOT
    // the strings "true"/"false" — Dio would serialise `true` → "true", so
    // we send the int form to satisfy the server's `featured` rule.
    final data = await _api.get('/products', query: {'featured': 1}) as Map<String, dynamic>;
    final r = (data['data'] as List)
        .map((j) => Product.fromJson(j as Map<String, dynamic>))
        .toList();
    _log('getFeatured ✓ (${r.length} from API)');
    return r;
  }

  Future<List<Product>> getAllProducts() async {
    _log('getAllProducts →');
    final data = await _api.get('/products', query: {'per_page': 60}) as Map<String, dynamic>;
    final r = (data['data'] as List)
        .map((j) => Product.fromJson(j as Map<String, dynamic>))
        .toList();
    _log('getAllProducts ✓ (${r.length} from API)');
    return r;
  }

  /// Single product by slug — hits `GET /products/{slug}` for the detail
  /// resource (long_desc, images, option_groups). Item Detail calls this on
  /// open so newly-published admin changes appear without a full menu reload.
  Future<Product> getBySlug(String slug) async {
    _log('getBySlug → $slug');
    final data = await _api.get('/products/$slug') as Map<String, dynamic>;
    final j    = data['data'] as Map<String, dynamic>;
    _log('getBySlug ✓ ($slug)');
    return Product.fromJson(j);
  }

  /// Paginated products scoped to one category slug. Backs Screen 07 Menu.
  Future<List<Product>> getByCategory(
    String slug, {
    int page = 1,
    int perPage = 20,
  }) async {
    _log('getByCategory → $slug page=$page');
    final data = await _api.get('/products', query: {
      'category': slug,
      'page':     page,
      'per_page': perPage,
    }) as Map<String, dynamic>;
    final r = (data['data'] as List)
        .map((j) => Product.fromJson(j as Map<String, dynamic>))
        .toList();
    _log('getByCategory ✓ (${r.length})');
    return r;
  }

  Future<Offer?> getWeeklyOffer() async {
    _log('getWeeklyOffer →');
    final data = await _api.get('/offers') as Map<String, dynamic>;
    final list = (data['data'] as List);
    if (list.isEmpty) {
      _log('getWeeklyOffer ✓ (none)');
      return null;
    }
    _log('getWeeklyOffer ✓ (${list.length}, picking first)');
    return Offer.fromJson(list.first as Map<String, dynamic>);
  }

  /// All currently-active offers, in `sort_order`. Screen 16 uses the first
  /// as its hero and up to three of the rest as secondary cards (spec §3).
  Future<List<Offer>> listOffers() async {
    _log('listOffers →');
    final data = await _api.get('/offers') as Map<String, dynamic>;
    final r = (data['data'] as List)
        .map((j) => Offer.fromJson(j as Map<String, dynamic>))
        .toList();
    _log('listOffers ✓ (${r.length})');
    return r;
  }

  /// Free-text search delegated to the server (`GET /products?search=…`)
  /// with a client-side pass for the chip states the API doesn't cover
  /// directly (spicy / quick / under 30k).
  Future<List<Product>> search(String query, SearchFilter filter) async {
    _log('search → q="$query"  filter=${filter.name}');
    final data = await _api.get('/products', query: {
      'search':   query,
      'sort':     _sortForFilter(filter),
      'per_page': 40,
    }) as Map<String, dynamic>;
    var hits = (data['data'] as List)
        .map((j) => Product.fromJson(j as Map<String, dynamic>))
        .toList();
    _log('search ✓ API returned ${hits.length} hits');

    switch (filter) {
      case SearchFilter.spicy:    hits = hits.where((p) => p.spicy).toList();               break;
      case SearchFilter.quick:    hits = hits.where((p) => p.prepMinutes <= 10).toList();   break;
      case SearchFilter.under30k: hits = hits.where((p) => p.price < 30000).toList();       break;
      case SearchFilter.cheapest: hits.sort((a, b) => a.price.compareTo(b.price));          break;
      case SearchFilter.popular:  hits.sort((a, b) => b.popularity.compareTo(a.popularity));break;
    }
    return hits;
  }

  // ─────────────────────── Helpers ───────────────────────

  String _sortForFilter(SearchFilter f) => switch (f) {
        SearchFilter.cheapest => 'price',
        SearchFilter.popular  => 'popularity',
        _                     => 'popularity',
      };

}

// ═════════════════════════════════════════════════════════════════
//  Offline fallback: categories only. Products & offers must come
//  from the API so their IDs are valid for POST /cart/items etc.
// ═════════════════════════════════════════════════════════════════
const List<MenuCategory> _seedCategories = [
  MenuCategory(slug: 'broasted',   labelAr: 'بروستد',     labelEn: 'Broasted',   emoji: '🍗', sortOrder: 1),
  MenuCategory(slug: 'shawarma',   labelAr: 'شاورما',      labelEn: 'Shawarma',   emoji: '🌯', sortOrder: 2),
  MenuCategory(slug: 'burgers',    labelAr: 'برجر',        labelEn: 'Burgers',    emoji: '🍔', sortOrder: 3),
  MenuCategory(slug: 'sandwiches', labelAr: 'ساندويشات', labelEn: 'Sandwiches', emoji: '🥪', sortOrder: 4),
  MenuCategory(slug: 'drinks',     labelAr: 'مشروبات',    labelEn: 'Drinks',     emoji: '🥤', sortOrder: 5),
];

// ignore: unused_element  — kept for possible future dev-only offline mode.
const List<Product> _unusedSeedProducts = [
  Product(id: 'p1', nameAr: 'بروستد كرانشي — 8 قطع', nameEn: 'Crunchy Broasted — 8 pcs',
    descriptionAr: 'دجاج مقرمش بالبهارات + بطاطا + خبز + صوص', descriptionEn: 'Crispy chicken + fries + bread + sauce',
    price: 45000, popularity: 100, prepMinutes: 15, spicy: true, isFeatured: true,
    emoji: '🍗', categorySlug: 'broasted', badgeLabel: '🔥 حار', badgeColor: 'red'),
  Product(id: 'p2', nameAr: 'بروستد كرانشي — 4 قطع', nameEn: 'Crunchy Broasted — 4 pcs',
    descriptionAr: 'نصف حصة للأفراد + بطاطا صغيرة', descriptionEn: 'Half portion + small fries',
    price: 25000, popularity: 60, prepMinutes: 10, spicy: false, isFeatured: false,
    emoji: '🍗', categorySlug: 'broasted'),
  Product(id: 'p3', nameAr: 'شاورما دجاج عربي', nameEn: 'Arabic Chicken Shawarma',
    descriptionAr: 'دجاج متبل، ثوم، مخلل وبطاطا داخل خبز صاج', descriptionEn: 'Marinated chicken, garlic, pickles and fries wrapped in saj bread',
    price: 22000, popularity: 95, prepMinutes: 8, spicy: false, isFeatured: true,
    emoji: '🌯', categorySlug: 'shawarma', badgeLabel: '🥗 خفيف', badgeColor: 'green'),
  Product(id: 'p4', nameAr: 'شاورما لحم عربي', nameEn: 'Arabic Meat Shawarma',
    descriptionAr: 'لحم مشوي، طحينة، بندورة، بقدونس', descriptionEn: 'Grilled meat, tahini, tomato, parsley',
    price: 32000, popularity: 75, prepMinutes: 10, spicy: false, isFeatured: false,
    emoji: '🌯', categorySlug: 'shawarma'),
  Product(id: 'p5', nameAr: 'دبل تشيز برجر', nameEn: 'Double Cheeseburger',
    descriptionAr: 'قطعتين لحم + جبنة شيدر مضاعفة + صوص خاص', descriptionEn: 'Two beef patties + double cheddar + special sauce',
    price: 38000, popularity: 90, prepMinutes: 10, spicy: false, isFeatured: true,
    emoji: '🍔', categorySlug: 'burgers', badgeLabel: '⭐ الأشهر', badgeColor: 'yellow'),
  Product(id: 'p6', nameAr: 'زنجر برجر', nameEn: 'Zinger Burger',
    descriptionAr: 'دجاج بهارات حارة + مايونيز + خس', descriptionEn: 'Spicy chicken + mayo + lettuce',
    price: 32000, popularity: 70, prepMinutes: 9, spicy: true, isFeatured: false,
    emoji: '🍔', categorySlug: 'burgers', badgeLabel: '🔥 حار', badgeColor: 'red'),
  Product(id: 'p7', nameAr: 'كلاسيك برجر', nameEn: 'Classic Burger',
    descriptionAr: 'قطعة لحم مشوي + خضار + صوص كلاسيكي', descriptionEn: 'Grilled beef + veggies + classic sauce',
    price: 25000, popularity: 55, prepMinutes: 8, spicy: false, isFeatured: false,
    emoji: '🍔', categorySlug: 'burgers'),
  Product(id: 'p8', nameAr: 'أجنحة حارة — 10 قطع', nameEn: 'Buffalo Wings — 10 pcs',
    descriptionAr: 'صوص بافلو حار', descriptionEn: 'Hot buffalo sauce',
    price: 30000, popularity: 65, prepMinutes: 12, spicy: true, isFeatured: false,
    emoji: '🍗', categorySlug: 'sandwiches'),
  Product(id: 'p9', nameAr: 'ساندويش تشيكن فيليه', nameEn: 'Chicken Fillet Sandwich',
    descriptionAr: 'شرائح دجاج مشوية + خس + طماطم + صوص خاص', descriptionEn: 'Grilled chicken fillet + lettuce + tomato + sauce',
    price: 28000, popularity: 50, prepMinutes: 8, spicy: false, isFeatured: false,
    emoji: '🥪', categorySlug: 'sandwiches'),
  Product(id: 'p10', nameAr: 'بيبسي 330 مل', nameEn: 'Pepsi 330ml',
    descriptionAr: 'مبردة', descriptionEn: 'Chilled',
    price: 3000, popularity: 40, prepMinutes: 1, spicy: false, isFeatured: false,
    emoji: '🥤', categorySlug: 'drinks'),
  Product(id: 'p11', nameAr: 'عصير برتقال طازج', nameEn: 'Fresh Orange Juice',
    descriptionAr: 'يُعصر عند الطلب', descriptionEn: 'Pressed to order',
    price: 8000, popularity: 35, prepMinutes: 3, spicy: false, isFeatured: false,
    emoji: '🧃', categorySlug: 'drinks'),
  Product(id: 'p12', nameAr: 'ليمون بالنعناع', nameEn: 'Mint Lemonade',
    descriptionAr: 'مثلج، طازج', descriptionEn: 'Iced and fresh',
    price: 7000, popularity: 30, prepMinutes: 3, spicy: false, isFeatured: false,
    emoji: '🍋', categorySlug: 'drinks'),
];
