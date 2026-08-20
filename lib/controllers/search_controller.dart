import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/app_prefs.dart';
import '../services/catalog_service.dart';

/// Owns the Search screen's query, filter, results, and persisted recents.
///
/// Named [CatalogSearchController] to avoid colliding with Flutter's own
/// `SearchController` (Material 3 search bar) — the two aren't related.
class CatalogSearchController extends ChangeNotifier {
  final CatalogService _catalog;
  final AppPrefs       _prefs;

  CatalogSearchController(this._catalog, this._prefs) {
    _recents = _prefs.recentSearches;
  }

  // ─────────────── state ───────────────
  String        _query   = '';
  SearchFilter  _filter  = SearchFilter.popular;
  List<Product> _results = [];
  bool          _loading = false;
  List<String>  _recents = const [];
  Timer?        _debounce;

  // ─────────────── view surface ───────────────
  String        get query     => _query;
  SearchFilter  get filter    => _filter;
  List<Product> get results   => _results;
  bool          get loading   => _loading;
  List<String>  get recents   => _recents;
  bool          get hasQuery  => _query.trim().length >= 2;
  bool          get isEmpty   => hasQuery && !_loading && _results.isEmpty;

  // ─────────────── mutations ───────────────
  void setQuery(String q) {
    _query = q;
    _debounce?.cancel();

    if (q.trim().length < 2) {
      _results = [];
      _loading = false;
      notifyListeners();
      return;
    }

    _loading = true;         // dim previous + show skeleton immediately
    notifyListeners();

    _debounce = Timer(const Duration(milliseconds: 300), _run);
  }

  void setFilter(SearchFilter f) {
    if (_filter == f) return;
    _filter = f;
    if (hasQuery) {
      _run();
    } else {
      notifyListeners();
    }
  }

  Future<void> _run() async {
    final r = await _catalog.search(_query.trim(), _filter);
    // Ignore stale results
    _results = r;
    _loading = false;
    notifyListeners();
  }

  Future<void> commitAsRecent(String term) async {
    if (term.trim().length < 2) return;
    await _prefs.addRecentSearch(term.trim());
    _recents = _prefs.recentSearches;
    notifyListeners();
  }

  Future<void> removeRecent(String term) async {
    await _prefs.removeRecentSearch(term);
    _recents = _prefs.recentSearches;
    notifyListeners();
  }

  Future<void> clearRecents() async {
    await _prefs.clearRecentSearches();
    _recents = const [];
    notifyListeners();
  }

  void reset() {
    _query = '';
    _results = [];
    _loading = false;
    _debounce?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
