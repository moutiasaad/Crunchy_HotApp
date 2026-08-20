import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/catalog_service.dart';

/// Backs Screen 07 — Menu. Owns the selected category, per-category page
/// cache, favourites (in-memory stub for now) and the offline/closed flags
/// that drive the strips above the list.
///
/// Design notes:
/// * Categories are fetched once and re-used; selecting a chip does not
///   re-fetch categories.
/// * Products are cached by slug so returning to a visited chip is
///   instant (no spinner). Pull-to-refresh clears the cache for the
///   active slug only.
/// * Pagination: `_perPage` items per request; `hasMore` becomes false
///   as soon as a page comes back short (the server may or may not
///   paginate — safe either way).
class MenuController extends ChangeNotifier {
  final CatalogService _catalog;
  MenuController(this._catalog);

  static const int _perPage = 20;

  // ─── categories ───
  List<MenuCategory> _categories = const [];
  List<MenuCategory> get categories => _categories;

  // ─── selected category ───
  String? _slug;
  String? get category => _slug;

  // ─── items for the selected slug ───
  final Map<String, List<Product>> _byCategory = {};
  final Map<String, int>           _pageBySlug = {};
  final Map<String, bool>          _hasMoreBySlug = {};

  List<Product> get items =>
      _slug == null ? const [] : (_byCategory[_slug] ?? const []);

  bool get hasMore => _slug == null ? false : (_hasMoreBySlug[_slug] ?? false);

  // ─── flags ───
  bool _loading     = true;   // initial page for the active slug
  bool _loadingMore = false;
  String? _error;
  final bool _offline = false;
  final bool _closed  = false;

  bool    get loading     => _loading;
  bool    get loadingMore => _loadingMore;
  String? get error       => _error;
  bool    get offline     => _offline;
  bool    get closed      => _closed;

  // Favourites moved to FavouritesController — it's the single source of
  // truth for both Menu heart state and the Favourites screen.

  // ─── lifecycle ───
  Future<void> init({String? initialCategory}) async {
    if (_categories.isEmpty) {
      try {
        _categories = await _catalog.getCategories();
      } catch (_) {
        _categories = const [];
      }
    }

    final target = initialCategory
        ?? _slug
        ?? (_categories.isNotEmpty ? _categories.first.slug : null);

    if (target == null) {
      _loading = false;
      notifyListeners();
      return;
    }
    await setCategory(target);
  }

  Future<void> setCategory(String slug) async {
    _slug  = slug;
    _error = null;

    // Cached path → no spinner, just repaint.
    if (_byCategory.containsKey(slug)) {
      _loading = false;
      notifyListeners();
      return;
    }

    _loading = true;
    notifyListeners();

    try {
      final first = await _catalog.getByCategory(slug, page: 1, perPage: _perPage);
      _byCategory[slug]    = first;
      _pageBySlug[slug]    = 1;
      _hasMoreBySlug[slug] = first.length >= _perPage;
    } catch (_) {
      _error = 'ما قدرنا نجيب المنيو — جرّب مرة تانية';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    final slug = _slug;
    if (slug == null || _loadingMore || _loading) return;
    if (!(_hasMoreBySlug[slug] ?? false)) return;

    _loadingMore = true;
    notifyListeners();

    final nextPage = (_pageBySlug[slug] ?? 1) + 1;
    try {
      final more = await _catalog.getByCategory(slug, page: nextPage, perPage: _perPage);
      final list = List<Product>.from(_byCategory[slug] ?? const []);
      list.addAll(more);
      _byCategory[slug]    = list;
      _pageBySlug[slug]    = nextPage;
      _hasMoreBySlug[slug] = more.length >= _perPage;
    } catch (_) {
      // silent — the sentinel row will just stop spinning.
      _hasMoreBySlug[slug] = false;
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// Pull-to-refresh (and tab-activation refresh): drop the current slug's
  /// cache, re-fetch categories from the API (so newly-added admin categories
  /// appear), then re-fetch page 1 of the current slug.
  Future<void> refresh() async {
    try {
      final fresh = await _catalog.getCategories();
      if (fresh.isNotEmpty) _categories = fresh;
    } catch (_) {
      // Keep the current categories — the slug fetch below still runs.
    }

    final slug = _slug;
    if (slug == null) return init();
    _byCategory.remove(slug);
    _pageBySlug.remove(slug);
    _hasMoreBySlug.remove(slug);
    await setCategory(slug);
  }
}
