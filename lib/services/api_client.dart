import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../config/api_config.dart';
import 'app_prefs.dart';

// ─────────────────────── Exceptions ───────────────────────

/// Base type for API errors — always carries a human-readable Arabic message.
class ApiException implements Exception {
  final String  message;
  final int?    statusCode;
  final Object? raw;

  const ApiException(this.message, {this.statusCode, this.raw});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// 422 — Laravel FormRequest validation failure. `errors` maps field → messages.
class ApiValidationException extends ApiException {
  final Map<String, List<String>> errors;
  const ApiValidationException(super.message, this.errors, {super.statusCode, super.raw});

  String? get firstError {
    for (final list in errors.values) {
      if (list.isNotEmpty) return list.first;
    }
    return null;
  }
}

/// 429 — throttled by the server.
class ApiRateLimitException extends ApiException {
  final int? retryAfterSeconds;
  const ApiRateLimitException(super.message, {this.retryAfterSeconds, super.statusCode, super.raw});
}

/// 401 — token missing/expired. Caller should route to Login.
class ApiUnauthorizedException extends ApiException {
  const ApiUnauthorizedException([super.message = 'الرجاء تسجيل الدخول من جديد.'])
      : super(statusCode: 401);
}

/// No network / DNS / connect timeout.
class ApiOfflineException extends ApiException {
  const ApiOfflineException([super.message = 'لا يوجد اتصال بالإنترنت. تحقّق من الشبكة.']);
}

// ─────────────────────── Client ───────────────────────

/// Thin Dio wrapper. Attaches the Sanctum bearer token, maps HTTP failures
/// to typed exceptions, and enforces consistent timeouts. Prefer using this
/// over `Dio` directly so all services stay uniform.
class ApiClient {
  final Dio      _dio;
  final AppPrefs _prefs;

  ApiClient(this._prefs)
      : _dio = Dio(BaseOptions(
          baseUrl: ApiConfig.baseUrl,
          connectTimeout: ApiConfig.connectTimeout,
          receiveTimeout: ApiConfig.receiveTimeout,
          responseType: ResponseType.json,
          headers: {
            'Accept': 'application/json',
            'Accept-Language': 'ar',
          },
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (opts, handler) {
        final token = _prefs.authToken;
        if (token != null && token.isNotEmpty) {
          opts.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(opts);
      },
    ));

    // Debug-only network logger. Kept lightweight (URL + status + short body)
    // so the Flutter console stays scannable.
    if (kDebugMode) {
      _dio.interceptors.add(InterceptorsWrapper(
        onRequest: (opts, handler) {
          debugPrint('[API] → ${opts.method} ${opts.uri}${opts.data == null ? '' : '  body=${_snip(opts.data)}'}');
          handler.next(opts);
        },
        onResponse: (resp, handler) {
          debugPrint('[API] ← ${resp.statusCode} ${resp.requestOptions.uri}  ${_snip(resp.data)}');
          handler.next(resp);
        },
        onError: (err, handler) {
          debugPrint('[API] ✗ ${err.response?.statusCode ?? "-"} '
              '${err.requestOptions.uri}  '
              '${err.type.name}  ${_snip(err.response?.data ?? err.message)}');
          handler.next(err);
        },
      ));
    }
  }

  static String _snip(Object? v, [int max = 240]) {
    final s = v?.toString() ?? '';
    return s.length > max ? '${s.substring(0, max)}…' : s;
  }

  // ─────────────── Public verbs ───────────────
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _run(() => _dio.get(path, queryParameters: query));

  Future<dynamic> post(String path, {Object? data}) =>
      _run(() => _dio.post(path, data: data));

  Future<dynamic> patch(String path, {Object? data}) =>
      _run(() => _dio.patch(path, data: data));

  Future<dynamic> delete(String path, {Object? data}) =>
      _run(() => _dio.delete(path, data: data));

  // ─────────────── Error mapping ───────────────
  Future<dynamic> _run(Future<Response<dynamic>> Function() call) async {
    try {
      final r = await call();
      return r.data;
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  ApiException _map(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
        return const ApiOfflineException();
      case DioExceptionType.badResponse:
        return _mapBadResponse(e);
      default:
        return ApiException(
          'حدث خطأ في الشبكة — جرّب مرة تانية',
          statusCode: e.response?.statusCode,
          raw: e,
        );
    }
  }

  ApiException _mapBadResponse(DioException e) {
    final code = e.response?.statusCode ?? 0;
    final data = e.response?.data;

    // Laravel FormRequest → { message, errors: { field: [msg, ...] } }
    if (code == 422 && data is Map<String, dynamic>) {
      final rawErrors = (data['errors'] as Map<String, dynamic>?) ?? const {};
      final errors = rawErrors.map<String, List<String>>((k, v) => MapEntry(
            k,
            (v as List).map((m) => m.toString()).toList(),
          ));
      return ApiValidationException(
        (data['message'] as String?) ?? 'بيانات غير صالحة.',
        errors,
        statusCode: 422,
        raw: e,
      );
    }

    if (code == 429) {
      final retry = int.tryParse(
        e.response?.headers.value('Retry-After') ?? '',
      );
      final msg = (data is Map && data['message'] is String)
          ? data['message'] as String
          : 'كثرت المحاولات — جرّب بعد شوي.';
      return ApiRateLimitException(msg, retryAfterSeconds: retry, statusCode: 429, raw: e);
    }

    if (code == 401 || code == 403) {
      // Clear the local token so the next boot goes back to Login.
      _prefs.clearAuthToken();
      return const ApiUnauthorizedException();
    }

    final msg = (data is Map && data['message'] is String)
        ? data['message'] as String
        : 'حدث خطأ في الخادم.';
    return ApiException(msg, statusCode: code, raw: e);
  }
}
