import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/favourites_service.dart';

/// Backs Screen 09 — Favourites — and provides the single source of truth
/// used by the Menu 🤍 hearts.
///
/// Design notes:
///  * Products live as `List<Product>` in insertion order (server returns
///    most-recent-first, which is the display order).
///  * A parallel `Set<String>` of ids gives O(1) `isFavourite(id)` for
///    the Menu screen's rows.
///  * Guest state: any 401 from the server flips `isGuest` on; the local
///    list stays empty (per spec §8 Guest — the sign-in CTA replaces the
///    empty block). Cross-device sync + local-guest-list merge on login
///    are deferred (see TODO in [ensureLoaded]).
class FavouritesController extends ChangeNotifier {
  final FavouritesService _service;
  FavouritesController(this._service);

  static const int maxItems = 50;

  final List<Product> _items = [];
  final Set<String>   _ids   = <String>{};

  bool    _loading = false;
  bool    _loaded  = false;   // becomes true after the first successful load
  bool    _isGuest = false;
  String? _error;

  // ─────────────── view surface ───────────────
  List<Product> get items          => List.unmodifiable(_items);
  int           get count          => _items.length;
  bool          get isEmpty        => _items.isEmpty;
  bool          get loading        => _loading;
  bool          get isGuest        => _isGuest;
  String?       get error          => _error;
  bool          get hasFavourites  => _ids.isNotEmpty;

  bool isFavourite(String productId) => _ids.contains(productId);

  // ─────────────── loading ───────────────
  /// Loads from the server if we haven't yet. Subsequent calls are cheap.
  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    return refresh();
    // TODO(guest-merge): when the user signs in later, replay any locally-
    // queued favourite ids (SharedPreferences) with a union merge, then
    // clear the local list.
  }

  Future<void> refresh() async {
    _loading = true;
    _error   = null;
    notifyListeners();

    try {
      final list = await _service.list();
      _items
        ..clear()
        ..addAll(list);
      _ids
        ..clear()
        ..addAll(list.map((p) => p.id));
      _isGuest = false;
      _loaded  = true;
    } on ApiUnauthorizedException {
      _isGuest = true;
      _items.clear();
      _ids.clear();
      _loaded = true;
    } catch (_) {
      _error = 'ما قدرنا نجيب المفضلة — جرّب مرة تانية';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ─────────────── mutations ───────────────
  /// Toggle a product's favourite state. Optimistic — the UI updates before
  /// the server round-trip, and rolls back if the server rejects.
  ///
  /// Returns a [FavouriteToggleResult] the caller can use to show snackbars
  /// (undo, "list full", "sign in").
  Future<FavouriteToggleResult> toggle(Product product) async {
    if (_isGuest) return FavouriteToggleResult.guest;

    if (_ids.contains(product.id)) {
      return _optimisticRemove(product);
    }
    return _optimisticAdd(product);
  }

  Future<FavouriteToggleResult> _optimisticAdd(Product product) async {
    if (_items.length >= maxItems) {
      return FavouriteToggleResult.full;
    }

    // Optimistic insert at the front (server also stores most-recent-first).
    _items.insert(0, product);
    _ids.add(product.id);
    notifyListeners();

    try {
      final canonical = await _service.add(int.parse(product.id));
      // Swap the placeholder for the server's canonical copy.
      final idx = _items.indexWhere((p) => p.id == canonical.id);
      if (idx >= 0) _items[idx] = canonical;
      notifyListeners();
      return FavouriteToggleResult.added;
    } on ApiValidationException catch (e) {
      _rollbackAdd(product);
      // 422 from the server means the cap fired even though we thought we
      // had room (concurrent add on another device, for example).
      final err = e.firstError ?? e.message;
      if (err.contains('حد') || err.contains('FULL')) {
        return FavouriteToggleResult.full;
      }
      return FavouriteToggleResult.error;
    } on ApiUnauthorizedException {
      _rollbackAdd(product);
      _isGuest = true;
      notifyListeners();
      return FavouriteToggleResult.guest;
    } catch (_) {
      _rollbackAdd(product);
      return FavouriteToggleResult.error;
    }
  }

  Future<FavouriteToggleResult> _optimisticRemove(Product product) async {
    final idx = _items.indexWhere((p) => p.id == product.id);
    if (idx < 0) return FavouriteToggleResult.error;

    // Snapshot for undo / rollback.
    final removed         = _items[idx];
    final removedIndex    = idx;

    _items.removeAt(idx);
    _ids.remove(product.id);
    notifyListeners();

    try {
      await _service.remove(int.parse(product.id));
      return FavouriteToggleResult.removed;
    } on ApiUnauthorizedException {
      _restoreAt(removedIndex, removed);
      _isGuest = true;
      notifyListeners();
      return FavouriteToggleResult.guest;
    } catch (_) {
      _restoreAt(removedIndex, removed);
      return FavouriteToggleResult.error;
    }
  }

  /// Undo a `_optimisticRemove` — used by the snackbar undo action. Server
  /// round-trip is a plain re-add (there's no dedicated endpoint), so the
  /// re-inserted item's `created_at` will be "now" server-side and thus
  /// appear at the top on refresh.
  Future<void> restoreAt(int index, Product product) async {
    if (_ids.contains(product.id)) return;   // already back — nothing to do
    _restoreAt(index, product);
    notifyListeners();
    try {
      await _service.add(int.parse(product.id));
    } catch (_) {
      // Silent — the visible list matches the user's intent even if the
      // server hasn't caught up. Next refresh will reconcile.
    }
  }

  // ─────────────── helpers ───────────────
  void _rollbackAdd(Product product) {
    _items.removeWhere((p) => p.id == product.id);
    _ids.remove(product.id);
    notifyListeners();
  }

  void _restoreAt(int index, Product product) {
    final safeIdx = index.clamp(0, _items.length);
    _items.insert(safeIdx, product);
    _ids.add(product.id);
  }
}

/// Result of a `toggle()` call — lets the caller decide what feedback to
/// show without leaking the exception type into UI code.
enum FavouriteToggleResult {
  added,
  removed,
  full,
  guest,
  error,
}
