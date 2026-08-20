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

  /// Ask the backend to email a 6-digit OTP to [email].
  ///
  /// Laravel returns 200 whether the email exists or not (no user
  /// enumeration), so the only failure paths are network + 429.
  /// **No account is created on this call** — signup happens inside
  /// [verifyOtp] after a valid code is entered.
  Future<void> requestOtp(String email) async {
    final hex = email.codeUnits
        .map((c) => c.toRadixString(16).padLeft(4, '0'))
        .join(' ');
    _log('requestOtp → email="$email"  len=${email.length}  chars=[$hex]');
    try {
      await _api.post('/auth/otp/request', data: {'email': email});
      await _prefs.setLastEmail(email);
      _log('requestOtp ✓ (email queued; account NOT created — check Laravel log for the code)');
    } on ApiRateLimitException catch (e) {
      _log('requestOtp ✗ rate-limited (retry after ${e.retryAfterSeconds}s)');
      throw RateLimitedException(e.message, e.retryAfterSeconds);
    } catch (e) {
      _log('requestOtp ✗ $e');
      rethrow;
    }
  }

  /// Verify the 6-digit [code]. Returns the authenticated user and stores
  /// the bearer token in [AppPrefs]. If no account existed for [email],
  /// the backend creates it in this call and flags `is_new_user: true`.
  ///
  /// Throws [WrongOtpException] on 422, [RateLimitedException] on 429.
  Future<User> verifyOtp(String email, String code) async {
    // In debug builds we log the real code + its hex char codes so we can
    // spot Arabic-Indic digits, hidden whitespace, direction marks, etc.
    // In profile/release the `_log` helper is a no-op (guarded by kDebugMode).
    final hex = code.codeUnits
        .map((c) => c.toRadixString(16).padLeft(4, '0'))
        .join(' ');
    _log('verifyOtp → email="$email"  code="$code"  len=${code.length}  chars=[$hex]');

    try {
      final data = await _api.post('/auth/otp/verify', data: {
        'email': email,
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

  /// `POST /profile/complete` — writes the user's real name + phone after
  /// signup. Server validates `phone` as Syrian mobile (`+9639XXXXXXXX`).
  Future<User> completeProfile({required String name, required String phone}) async {
    _log('completeProfile → name="$name" phone="$phone"');
    try {
      final data = await _api.post('/profile/complete', data: {
        'name':  name,
        'phone': phone,
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
