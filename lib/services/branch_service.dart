import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../models/models.dart';
import 'api_client.dart';

void _log(String msg) {
  if (kDebugMode) debugPrint('[Branch] $msg');
}

/// Talks to `GET /api/v1/branches` for pickup selection.
///
/// No offline fallback — a branch id is required for `POST /orders`, so we
/// must have real server IDs. On failure the caller shows an error state.
class BranchService {
  final ApiClient _api;
  const BranchService(this._api);

  Future<List<Branch>> fetchAll() async {
    _log('fetchAll →');
    final data = await _api.get('/branches') as Map<String, dynamic>;
    final r = (data['data'] as List)
        .map((j) => Branch.fromJson(j as Map<String, dynamic>))
        .toList();
    _log('fetchAll ✓ (${r.length} from API)');
    return r;
  }
}
