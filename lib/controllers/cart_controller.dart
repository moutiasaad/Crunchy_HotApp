import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/app_config_service.dart';
import '../services/app_prefs.dart';
import '../services/cart_service.dart';
import '../services/catalog_service.dart';

/// Owns the cart lines, delivery/pickup mode, and derived totals.
///
/// Views bind via `context.watch<CartController>()` for the count/totals and
/// call `context.read<CartController>().add(product)` etc. for mutations.
///
/// State is persisted to [AppPrefs] on every mutation and restored in the
/// constructor, so the cart survives app cold starts. Persistence uses a
/// single JSON blob under `AppPrefs.cartState` — see [CartLine.toJson] and
/// [Branch.toJsonLocal] for the shape.
///
/// Listens to [AppConfigService] so a mid-session refresh of the admin's
/// delivery fee immediately reflows the CTA/badge — otherwise the totals
/// would stay stale until the next `notifyListeners()` from a mutation.
class CartController extends ChangeNotifier {
  final CartService      _service;
  final AppConfigService _config;
  final AppPrefs         _prefs;

  CartController(this._service, this._config, this._prefs) {
    _config.addListener(_onConfigChanged);
    _restore();
  }

  void _onConfigChanged() => notifyListeners();

  @override
  void dispose() {
    _config.removeListener(_onConfigChanged);
    super.dispose();
  }

  final List<CartLine> _lines = [];
  OrderMode _mode = OrderMode.delivery;
  Branch?   _branch;

  int _lastLineId = 0;

  // ─────────────── view surface ───────────────
  List<CartLine> get lines   => List.unmodifiable(_lines);
  OrderMode      get mode    => _mode;
  Branch?        get branch  => _branch;
  int            get count   => _lines.fold<int>(0, (s, l) => s + l.quantity);
  bool           get isEmpty => _lines.isEmpty;

  PriceBreakdown get totals => _service.quote(_lines, _mode);

  // ─────────────── mutations ───────────────
  /// Add a product to the cart. If an identical line already exists (same
  /// product + spice + addons + offer), its quantity is bumped instead of
  /// creating a new row. Pass [offer] to attach an offer to the line — the
  /// unit price becomes the offer price and the server receives `offer_id`.
  void add(
    Product product, {
    int quantity = 1,
    Spice spice = Spice.mild,
    List<Addon> addons = const [],
    String? note,
    Offer? offer,
  }) {
    final idx = _lines.indexWhere((l) =>
        l.product.id == product.id &&
        l.spice      == spice       &&
        l.offerId    == offer?.id   &&
        _sameAddons(l.addons, addons));

    if (idx >= 0) {
      _lines[idx] = _lines[idx].copyWith(quantity: _lines[idx].quantity + quantity);
    } else {
      _lines.add(CartLine(
        id: (++_lastLineId).toString(),
        product: product,
        quantity: quantity,
        spice: spice,
        addons: addons,
        note: note,
        offerId:        offer?.id,
        offerUnitPrice: offer?.price,
      ));
    }
    _notifyAndPersist();
  }

  void updateQuantity(String lineId, int quantity) {
    final idx = _lines.indexWhere((l) => l.id == lineId);
    if (idx < 0) return;
    if (quantity <= 0) {
      _lines.removeAt(idx);
    } else {
      _lines[idx] = _lines[idx].copyWith(quantity: quantity.clamp(1, 50));
    }
    _notifyAndPersist();
  }

  void remove(String lineId) {
    _lines.removeWhere((l) => l.id == lineId);
    _notifyAndPersist();
  }

  void setMode(OrderMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _notifyAndPersist();
  }

  /// Confirm-branch action from screen 12 — stores the branch and flips
  /// the cart into pickup mode in one shot (zeroes the delivery fee).
  void setPickupBranch(Branch b) {
    _branch = b;
    _mode   = OrderMode.pickup;
    _notifyAndPersist();
  }

  void clearPickupBranch() {
    if (_branch == null) return;
    _branch = null;
    _notifyAndPersist();
  }

  void clear() {
    if (_lines.isEmpty) return;
    _lines.clear();
    _notifyAndPersist();
  }

  /// Re-fetch each unique product in the cart and swap its snapshot on the
  /// line — so if the admin edited the price after the item was added, the
  /// UI reflects the new price on the next cart visit. Offer lines keep
  /// their locked-in `offerUnitPrice` (the offer's own row governs that).
  ///
  /// Silently skips lines without a slug (legacy seed items) and any product
  /// that fails to fetch (network blip, product deleted); those keep their
  /// cached snapshot until the next successful refresh.
  Future<void> refreshPrices(CatalogService catalog) async {
    if (_lines.isEmpty) return;

    final slugs = <String>{};
    for (final l in _lines) {
      if (l.product.slug.isNotEmpty) slugs.add(l.product.slug);
    }
    if (slugs.isEmpty) return;

    final results = await Future.wait(
      slugs.map((s) async {
        try {
          return MapEntry(s, await catalog.getBySlug(s));
        } catch (_) {
          return MapEntry(s, null as Product?);
        }
      }),
    );
    final fresh = <String, Product>{
      for (final e in results)
        if (e.value != null) e.key: e.value!,
    };
    if (fresh.isEmpty) return;

    var changed = false;
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      final next = fresh[line.product.slug];
      if (next == null) continue;
      if (next.price == line.product.price) continue;
      _lines[i] = line.copyWith(product: next);
      changed = true;
    }
    if (changed) _notifyAndPersist();
  }

  // ─────────────── persistence ───────────────
  void _notifyAndPersist() {
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> _persist() async {
    try {
      if (_lines.isEmpty && _branch == null && _mode == OrderMode.delivery) {
        await _prefs.clearCartState();
        return;
      }
      final payload = jsonEncode({
        'lines':       _lines.map((l) => l.toJson()).toList(),
        'mode':        _mode.name,
        if (_branch != null) 'branch': _branch!.toJsonLocal(),
        'lastLineId':  _lastLineId,
      });
      await _prefs.setCartState(payload);
    } catch (_) {
      // Persistence is best-effort — a serialization glitch shouldn't crash
      // the UI. On next successful mutation we'll try again.
    }
  }

  void _restore() {
    final raw = _prefs.cartState;
    if (raw == null || raw.isEmpty) return;
    try {
      final j = (jsonDecode(raw) as Map).cast<String, dynamic>();

      final rawLines = (j['lines'] as List?) ?? const [];
      for (final r in rawLines) {
        _lines.add(CartLine.fromJson((r as Map).cast<String, dynamic>()));
      }

      final modeName = j['mode'] as String?;
      if (modeName != null) {
        _mode = OrderMode.values.firstWhere(
          (m) => m.name == modeName,
          orElse: () => OrderMode.delivery,
        );
      }

      final b = j['branch'];
      if (b is Map) _branch = Branch.fromJsonLocal(b.cast<String, dynamic>());

      _lastLineId = (j['lastLineId'] as num?)?.toInt() ?? _lines.length;
    } catch (_) {
      // Corrupted blob — start fresh rather than block the user.
      _lines.clear();
      _mode = OrderMode.delivery;
      _branch = null;
      _lastLineId = 0;
      unawaited(_prefs.clearCartState());
    }
  }

  // ─────────────── helpers ───────────────
  bool _sameAddons(List<Addon> a, List<Addon> b) {
    if (a.length != b.length) return false;
    final ids1 = a.map((x) => x.id).toSet();
    final ids2 = b.map((x) => x.id).toSet();
    return ids1.difference(ids2).isEmpty;
  }
}
