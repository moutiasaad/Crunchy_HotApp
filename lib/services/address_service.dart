import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'api_client.dart';

void _log(String msg) {
  if (kDebugMode) debugPrint('[Address] $msg');
}

/// Wraps `POST /api/v1/addresses` — the piece Checkout needs before it can
/// place a delivery order. Address is a single free-text field; the admin
/// sets one flat delivery fee for every order in the SiteSettings page.
class AddressService {
  final ApiClient _api;
  const AddressService(this._api);

  /// Returns the server's numeric id for the freshly-created address.
  Future<int> create({
    required String text,
    bool isDefault = false,
  }) async {
    _log('create → "$text"');
    try {
      final data = await _api.post('/addresses', data: {
        'text':       text,
        'is_default': isDefault,
      }) as Map<String, dynamic>;

      final addr = (data['data'] as Map<String, dynamic>?) ?? data;
      final id   = addr['id'] as int;
      _log('create ✓ address_id=$id');
      return id;
    } catch (e) {
      _log('create ✗ $e');
      rethrow;
    }
  }
}
