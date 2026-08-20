import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../models/models.dart';
import 'api_client.dart';

void _log(String msg) {
  if (kDebugMode) debugPrint('[Favourites] $msg');
}

/// Thin wrapper around `/api/v1/favourites`. All calls are authenticated
/// (Sanctum bearer) — the ApiClient will surface [ApiUnauthorizedException]
/// for guests, which the controller catches to switch into guest mode.
///
/// Server contract (backend §7):
///  * GET    /favourites              → { data: [Product, ...] }   (most recent first)
///  * POST   /favourites              → 200 Product | 422 { code: FAVOURITES_FULL }
///  * DELETE /favourites/{productId}  → 204
class FavouritesService {
  final ApiClient _api;
  const FavouritesService(this._api);

  Future<List<Product>> list() async {
    _log('list →');
    final data = await _api.get('/favourites') as Map<String, dynamic>;
    final r = (data['data'] as List)
        .map((j) => Product.fromJson(j as Map<String, dynamic>))
        .toList();
    _log('list ✓ (${r.length})');
    return r;
  }

  /// Add [productId] to the current user's favourites. Returns the full
  /// product record so the caller can display it immediately without a
  /// re-fetch. Throws [ApiValidationException] on the 50-item cap; caller
  /// checks `.errors['code']` or the exception message.
  Future<Product> add(int productId) async {
    _log('add → $productId');
    final data = await _api.post('/favourites', data: {
      'product_id': productId,
    }) as Map<String, dynamic>;
    // The ProductResource is wrapped in {data: {...}} by Laravel.
    final json = (data['data'] ?? data) as Map<String, dynamic>;
    return Product.fromJson(json);
  }

  Future<void> remove(int productId) async {
    _log('remove → $productId');
    await _api.delete('/favourites/$productId');
  }
}
