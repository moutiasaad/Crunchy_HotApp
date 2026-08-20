import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../services/api_client.dart';
import '../services/app_prefs.dart';
import '../services/auth_service.dart';

/// Owns the sign-in lifecycle.
///
/// Views bind to it with `context.watch<AuthController>()`. All the mutating
/// entry points return `bool` so screens can decide whether to navigate.
class AuthController extends ChangeNotifier {
  final AuthService _service;
  final AppPrefs    _prefs;

  AuthController(this._service, this._prefs);

  // ─────────────── state ───────────────
  User?   _user;
  String? _pendingEmail;   // set between requestOtp() and verifyOtp()
  bool    _sending = false;
  String? _error;
  int     _cooldownSecs = 0;
  Timer?  _cooldownTimer;
  bool    _bootstrapped = false;

  // ─────────────── getters (view surface) ───────────────
  User?   get user             => _user;
  bool    get isSignedIn       => _user != null && !_user!.isGuest;
  bool    get isGuest          => _user?.isGuest ?? false;
  bool    get sending          => _sending;
  String? get error            => _error;
  int     get cooldownSecs     => _cooldownSecs;
  bool    get onCooldown       => _cooldownSecs > 0;
  String? get pendingEmail     => _pendingEmail;
  String? get lastEmail        => _prefs.lastEmail;
  bool    get bootstrapped     => _bootstrapped;

  /// True when the user is signed in AND has completed their profile
  /// (real name + phone). Used by Splash to decide Home vs Register.
  bool get needsProfile        => isSignedIn && !(_user!.isProfileComplete);

  // ─────────────── bootstrap (session persistence) ───────────────
  /// Runs once at app launch — if a bearer token is stored, hits GET /me to
  /// re-hydrate the User object. On 401 we clear the token so the user lands
  /// on Login; on any other error we stay logged-out but keep the token for
  /// a later retry (e.g. offline start).
  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    // Yield once so notifyListeners doesn't fire during the caller's build
    // phase (Splash calls bootstrap() from initState).
    await Future<void>.microtask(() {});

    if (!_prefs.isAuthenticated) {
      _bootstrapped = true;
      notifyListeners();
      return;
    }
    try {
      _user = await _service.me();
    } on ApiUnauthorizedException {
      await _prefs.clearAuthToken();
      _user = null;
    } catch (_) {
      // Network / server error — leave user null, don't touch the token.
    } finally {
      _bootstrapped = true;
      notifyListeners();
    }
  }

  /// Re-fetch /me and update `_user` in place. Useful after actions that
  /// change server-side user state (place order → new loyalty points, etc.).
  /// Silent on failure — keeps the last known user.
  Future<void> refreshUser() async {
    if (!_prefs.isAuthenticated) return;
    try {
      _user = await _service.me();
      notifyListeners();
    } catch (_) {
      // ignored — will retry on next natural trigger
    }
  }

  /// PATCH /me — persist an edited profile. Returns an [UpdateProfileResult]
  /// enum so the screen can decide what to render (field-level errors, retry,
  /// snackbar, ...) without leaking the exception type.
  ///
  /// The updated `User` is stored in place and listeners are notified so the
  /// Profile header re-renders with the new name / phone immediately.
  Future<UpdateProfileResult> updateProfile({
    String? name,
    String? phone,
    DateTime? birthday,
  }) async {
    _sending = true;
    _error   = null;
    notifyListeners();
    try {
      _user = await _service.updateProfile(
        name: name, phone: phone, birthday: birthday,
      );
      return UpdateProfileResult.saved;
    } on ApiValidationException catch (e) {
      final firstField = e.errors.entries.isEmpty ? '' : e.errors.entries.first.key;
      _error = e.firstError ?? 'تحقّق من البيانات';
      switch (firstField) {
        case 'phone': return UpdateProfileResult.phoneInvalidOrTaken;
        case 'email': return UpdateProfileResult.emailInvalidOrTaken;
        case 'name':  return UpdateProfileResult.nameInvalid;
        default:      return UpdateProfileResult.invalid;
      }
    } on ApiOfflineException {
      _error = 'لا يوجد اتصال — جرّب مرة تانية';
      return UpdateProfileResult.offline;
    } on ApiUnauthorizedException {
      return UpdateProfileResult.unauthenticated;
    } catch (_) {
      _error = 'حدث خطأ ما — جرّب مرة تانية';
      return UpdateProfileResult.error;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// POST /profile/complete — writes name + phone. Returns true on success.
  Future<bool> completeProfile({required String name, required String phone}) async {
    _sending = true;
    _error   = null;
    notifyListeners();
    try {
      _user = await _service.completeProfile(name: name, phone: phone);
      return true;
    } on ApiValidationException catch (e) {
      _error = e.firstError ?? 'تحقّق من الاسم ورقم الهاتف';
      return false;
    } catch (_) {
      _error = 'حدث خطأ ما — جرّب مرة تانية';
      return false;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  // ─────────────── mutations ───────────────
  Future<bool> requestOtp(String email) async {
    _sending = true;
    _error   = null;
    notifyListeners();

    try {
      await _service.requestOtp(email);
      _pendingEmail = email.trim().toLowerCase();
      return true;
    } on RateLimitedException catch (e) {
      _error = e.message;
      _startCooldown(60);
      return false;
    } catch (_) {
      _error = 'حدث خطأ ما — جرّب مرة تانية';
      return false;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<bool> verifyOtp(String code) async {
    if (_pendingEmail == null) return false;

    _sending = true;
    _error   = null;
    notifyListeners();

    try {
      _user = await _service.verifyOtp(_pendingEmail!, code);
      _pendingEmail = null;
      return true;
    } on WrongOtpException catch (e) {
      _error = e.message;
      return false;
    } catch (_) {
      _error = 'حدث خطأ ما — جرّب مرة تانية';
      return false;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  void continueAsGuest() {
    _user = const User.guest();
    _error = null;
    notifyListeners();
  }

  // ─────────────── Email change ───────────────

  /// POST /me/email/request — send an OTP to the candidate new email.
  Future<EmailChangeRequestResult> requestEmailChangeOtp(String email) async {
    _sending = true;
    _error   = null;
    notifyListeners();
    try {
      await _service.requestEmailChangeOtp(email);
      return EmailChangeRequestResult.sent;
    } on ApiValidationException catch (e) {
      final msg = e.firstError ?? e.message;
      _error = msg;
      if (msg.contains('الحالي')) return EmailChangeRequestResult.sameAsCurrent;
      if (msg.contains('مستخدم')) return EmailChangeRequestResult.taken;
      return EmailChangeRequestResult.invalidEmail;
    } on ApiRateLimitException catch (e) {
      _error = e.message;
      return EmailChangeRequestResult.rateLimited;
    } on ApiOfflineException {
      _error = 'لا يوجد اتصال — جرّب مرة تانية';
      return EmailChangeRequestResult.offline;
    } catch (_) {
      _error = 'حدث خطأ ما — جرّب مرة تانية';
      return EmailChangeRequestResult.error;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// POST /me/email — verify the OTP and apply the email change.
  Future<EmailChangeConfirmResult> confirmEmailChange({
    required String email,
    required String code,
  }) async {
    _sending = true;
    _error   = null;
    notifyListeners();
    try {
      _user = await _service.changeEmail(newEmail: email, code: code);
      return EmailChangeConfirmResult.updated;
    } on ApiValidationException catch (e) {
      final msg = e.firstError ?? e.message;
      _error = msg;
      if (msg.contains('مستخدم')) return EmailChangeConfirmResult.taken;
      return EmailChangeConfirmResult.wrongCode;
    } on ApiOfflineException {
      _error = 'لا يوجد اتصال — جرّب مرة تانية';
      return EmailChangeConfirmResult.offline;
    } catch (_) {
      _error = 'حدث خطأ ما — جرّب مرة تانية';
      return EmailChangeConfirmResult.error;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _service.logout();
    _user = null;
    _pendingEmail = null;
    _error = null;
    // Signing out is a "reset the app to a stranger" moment — show the
    // onboarding flow again on next launch instead of jumping straight
    // into Login. Matches the pattern most delivery apps use.
    await _prefs.clearOnboardingSeen();
    notifyListeners();
  }

  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  // ─────────────── cooldown ───────────────
  void _startCooldown(int seconds) {
    _cooldownSecs = seconds;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      _cooldownSecs--;
      if (_cooldownSecs <= 0) t.cancel();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }
}

/// Result of [AuthController.updateProfile] — lets the caller decide what to
/// show (field-focused error, offline banner, generic snackbar) without
/// touching HTTP or exception types.
enum UpdateProfileResult {
  saved,
  nameInvalid,
  phoneInvalidOrTaken,
  emailInvalidOrTaken,
  invalid,
  offline,
  unauthenticated,
  error,
}

/// Outcome of [AuthController.requestEmailChangeOtp].
enum EmailChangeRequestResult {
  sent,
  invalidEmail,
  sameAsCurrent,
  taken,
  rateLimited,
  offline,
  error,
}

/// Outcome of [AuthController.confirmEmailChange].
enum EmailChangeConfirmResult {
  updated,
  wrongCode,
  taken,
  offline,
  error,
}
