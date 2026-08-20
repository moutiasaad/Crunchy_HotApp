import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/catalog_service.dart';

/// Backs the Home screen — categories rail, weekly offer, featured cards.
class HomeController extends ChangeNotifier {
  final CatalogService _catalog;
  HomeController(this._catalog);

  List<MenuCategory> _categories = const [];
  List<Product>      _featured   = const [];
  Offer?             _weeklyOffer;
  bool               _loading    = true;
  String?            _error;

  List<MenuCategory> get categories  => _categories;
  List<Product>      get featured    => _featured;
  Offer?             get weeklyOffer => _weeklyOffer;
  bool               get loading     => _loading;
  String?            get error       => _error;

  Future<void> load() async {
    _loading = true;
    _error   = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _catalog.getCategories(),
        _catalog.getFeatured(),
        _catalog.getWeeklyOffer(),
      ]);
      _categories  = results[0] as List<MenuCategory>;
      _featured    = results[1] as List<Product>;
      _weeklyOffer = results[2] as Offer?;
    } catch (_) {
      _error = 'ما قدرنا نجيب المنيو — جرّب مرة تانية';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();
}
