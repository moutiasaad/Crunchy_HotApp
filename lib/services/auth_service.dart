import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../models/user.dart';
import 'api_client.dart';
import 'app_prefs.dart';

void _log(String msg) {
  if (kDebugMode) debugPrint('[Auth] $msg');
}

/// Thrown by [AuthService] when the entered OTP is wrong.
class WrongOtpException implements Exception {
  final String message;
  const WrongOtpException([this.message = 'الرمز غير صحيح — جرّب مرة تانية']);
}

/// Thrown when the OTP request is rate-limited by the server.
class RateLimitedException implements Exception {
  final String message;
  final int?   retryAfterSeconds;
  const RateLimitedException([this.message = 'جرّب مرة تانية بعد دقيقة', this.retryAfterSeconds]);
}

/// Talks to `POST /api/v1/auth/otp/*` on the Laravel backend and persists
/// the Sanctum bearer token via [AppPrefs] so [ApiClient] can attach it to
/// subsequent requests automatically.
class AuthService {
  final AppPrefs  _prefs;
  final ApiClient _api;

  AuthService(this._prefs, this._api);

  /// Ask the backend to send a 6-digit OTP to [phone] via WhatsApp.
  ///
  /// [phone] must be E.164 (`+countrycode…`). Laravel returns 200 whether
  /// the phone exists or not (no user enumeration); the only failure paths
  /// are validation (invalid phone), 429 (rate limit), or the wavadesk
  /// service refusing (invalid number, no WA instance, cooldown, etc.) which
  /// the backend surfaces as 422 with an Arabic message.
  ///
  /// **No account is created on this call** — signup happens inside
  /// [verifyOtp] after a valid code is entered.
  Future<void> requestOtp(String phone) async {
    _log('requestOtp → phone="$phone"');
    try {
      await _api.post('/auth/otp/request', data: {'phone': phone});
      await _prefs.setLastPhone(phone);
      _log('requestOtp ✓ (WA message queued; account NOT created)');
    } on ApiValidationException catch (e) {
      // The backend returns 422 for both invalid phone AND wavadesk refusal
      // (invalid_phone, no_instance, cooldown, gateway_error). Surface the
      // server's Arabic message verbatim so the UI can display it as-is.
      _log('requestOtp ✗ ${e.firstError ?? e.message}');
      rethrow;
    } on ApiRateLimitException catch (e) {
      _log('requestOtp ✗ rate-limited (retry after ${e.retryAfterSeconds}s)');
      throw RateLimitedException(e.message, e.retryAfterSeconds);
    } catch (e) {
      _log('requestOtp ✗ $e');
      rethrow;
    }
  }

  /// Verify the 6-digit [code]. Returns the authenticated user and stores
  /// the bearer token in [AppPrefs]. If no account existed for [phone],
  /// the backend creates it here and flags `is_new_user: true`.
  ///
  /// Throws [WrongOtpException] on 422, [RateLimitedException] on 429.
  Future<User> verifyOtp(String phone, String code) async {
    final hex = code.codeUnits
        .map((c) => c.toRadixString(16).padLeft(4, '0'))
        .join(' ');
    _log('verifyOtp → phone="$phone"  code="$code"  len=${code.length}  chars=[$hex]');

    try {
      final data = await _api.post('/auth/otp/verify', data: {
        'phone': phone,
        'code':  code,
      }) as Map<String, dynamic>;

      final token = data['token'] as String;
      final isNew = data['is_new_user'] == true;
      await _prefs.setAuthToken(token);

      _log('verifyOtp ✓ (is_new_user=$isNew, token=${token.substring(0, 8)}…)');
      return User.fromJson(data['user'] as Map<String, dynamic>);
    } on ApiValidationException catch (e) {
      _log('verifyOtp ✗ invalid code — server said: ${e.firstError ?? e.message}');
      throw WrongOtpException(e.firstError ?? 'الرمز غير صحيح — جرّب مرة تانية');
    } on ApiRateLimitException catch (e) {
      _log('verifyOtp ✗ rate-limited (retry after ${e.retryAfterSeconds}s)');
      throw RateLimitedException(e.message, e.retryAfterSeconds);
    } catch (e) {
      _log('verifyOtp ✗ unexpected: $e');
      rethrow;
    }
  }

  /// `GET /me` — fetch the current signed-in profile. Throws
  /// [ApiUnauthorizedException] if the stored token is expired/invalid.
  Future<User> me() async {
    _log('me →');
    final data = await _api.get('/me') as Map<String, dynamic>;
    final user = User.fromJson(data['data'] as Map<String, dynamic>);
    _log('me ✓ email=${user.email} complete=${user.isProfileComplete}');
    return user;
  }

  /// `PATCH /me` — update editable profile fields. Any field left null is
  /// omitted from the payload (server treats it as `sometimes`). Returns the
  /// fresh user.
  Future<User> updateProfile({
    String? name,
    String? phone,
    DateTime? birthday,
  }) async {
    final body = <String, dynamic>{
      if (name != null)     'name':     name,
      if (phone != null)    'phone':    phone,
      if (birthday != null) 'birthday': _fmtDate(birthday),
    };
    _log('updateProfile → ${body.keys.join(',')}');
    try {
      final data = await _api.patch('/me', data: body) as Map<String, dynamic>;
      final user = User.fromJson(data['data'] as Map<String, dynamic>);
      _log('updateProfile ✓');
      return user;
    } catch (e) {
      _log('updateProfile ✗ $e');
      rethrow;
    }
  }

  /// `POST /profile/complete` — writes the user's display name after signup.
  /// Phone is already captured + verified during WhatsApp OTP; email is
  /// optional (pass `null` to skip).
  Future<User> completeProfile({required String name, String? email}) async {
    _log('completeProfile → name="$name" email="${email ?? '(none)'}"');
    try {
      final data = await _api.post('/profile/complete', data: {
        'name': name,
        if (email != null && email.isNotEmpty) 'email': email,
      }) as Map<String, dynamic>;
      final user = User.fromJson(data['data'] as Map<String, dynamic>);
      _log('completeProfile ✓');
      return user;
    } catch (e) {
      _log('completeProfile ✗ $e');
      rethrow;
    }
  }

  /// `POST /me/email/request` — send a 6-digit OTP to a candidate new email.
  /// Throws [ApiValidationException] on 422 (already-taken / same-as-current)
  /// so the caller can surface the exact reason.
  Future<void> requestEmailChangeOtp(String newEmail) async {
    _log('requestEmailChangeOtp → "$newEmail"');
    try {
      await _api.post('/me/email/request', data: {'email': newEmail});
      _log('requestEmailChangeOtp ✓');
    } catch (e) {
      _log('requestEmailChangeOtp ✗ $e');
      rethrow;
    }
  }

  /// `POST /me/email` — verify the code + swap the email server-side.
  /// Returns the fresh [User] with the new email.
  Future<User> changeEmail({required String newEmail, required String code}) async {
    _log('changeEmail → "$newEmail"');
    try {
      final data = await _api.post('/me/email', data: {
        'email': newEmail,
        'code':  code,
      }) as Map<String, dynamic>;
      final user = User.fromJson(data['data'] as Map<String, dynamic>);
      _log('changeEmail ✓');
      return user;
    } catch (e) {
      _log('changeEmail ✗ $e');
      rethrow;
    }
  }

  /// yyyy-MM-dd — the shape Laravel's `date` validator prefers.
  static String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  Future<void> logout() async {
    _log('logout →');
    try {
      await _api.post('/auth/logout');
    } on ApiException {
      // Server side may already be dead — clear locally regardless.
    }
    await _prefs.clearAuthToken();
    _log('logout ✓ (token cleared)');
  }
}
