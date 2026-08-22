import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around SharedPreferences for the app's persistent flags.
///
/// Bootstrap in `main()` **before** `runApp` so any screen can read from it
/// synchronously without awaiting:
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await AppPrefs.init();
///   runApp(...);
/// }
/// ```
class AppPrefs {
  AppPrefs._(this._sp);

  final SharedPreferences _sp;
  static AppPrefs? _instance;

  static AppPrefs get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('AppPrefs.init() must be awaited before AppPrefs.instance is read.');
    }
    return i;
  }

  static Future<AppPrefs> init() async {
    _instance ??= AppPrefs._(await SharedPreferences.getInstance());
    return _instance!;
  }

  // ---------------- Keys ----------------
  static const _kOnboardingSeen  = 'onboarding_seen';
  static const _kRecentSearches  = 'recent_searches';
  static const _kLastEmail       = 'last_email';
  static const _kLastPhone       = 'last_phone';
  static const _kAuthToken       = 'auth_token';
  static const _kCartState       = 'cart_state';
  static const int _kMaxRecents  = 10;

  // ---------------- Onboarding ----------------
  bool get onboardingSeen             => _sp.getBool(_kOnboardingSeen) ?? false;
  Future<void> setOnboardingSeen()    => _sp.setBool(_kOnboardingSeen, true);
  /// Wipe the "seen" flag so onboarding re-appears on next splash. Called
  /// from logout so signed-out users get the full welcome flow again.
  Future<void> clearOnboardingSeen()  => _sp.remove(_kOnboardingSeen);

  // ---------------- Recent searches ----------------
  /// Newest-first, de-duplicated case-insensitively, max 10.
  List<String> get recentSearches   => _sp.getStringList(_kRecentSearches) ?? const [];

  Future<void> addRecentSearch(String term) async {
    final t = term.trim();
    if (t.isEmpty) return;
    final low = t.toLowerCase();
    final next = [
      t,
      ...recentSearches.where((r) => r.toLowerCase() != low),
    ].take(_kMaxRecents).toList();
    await _sp.setStringList(_kRecentSearches, next);
  }

  Future<void> removeRecentSearch(String term) async {
    final low = term.toLowerCase();
    final next = recentSearches.where((r) => r.toLowerCase() != low).toList();
    await _sp.setStringList(_kRecentSearches, next);
  }

  Future<void> clearRecentSearches() => _sp.remove(_kRecentSearches);

  // ---------------- Last email (kept for the profile email-change flow) ----
  String? get lastEmail                => _sp.getString(_kLastEmail);
  Future<void> setLastEmail(String e)  => _sp.setString(_kLastEmail, e);

  // ---------------- Last phone (prefill Login on repeat sign-in) ----------
  String? get lastPhone                => _sp.getString(_kLastPhone);
  Future<void> setLastPhone(String p)  => _sp.setString(_kLastPhone, p);

  // ---------------- Auth token (Laravel Sanctum bearer) ----------------
  String? get authToken                  => _sp.getString(_kAuthToken);
  Future<void> setAuthToken(String t)    => _sp.setString(_kAuthToken, t);
  Future<void> clearAuthToken()          => _sp.remove(_kAuthToken);
  bool    get isAuthenticated            => authToken != null;

  // ---------------- Persisted cart ----------------
  /// Serialized `{lines, mode, branch, lastLineId}` snapshot; stored as a
  /// single JSON blob because we always want to load/save it atomically.
  String? get cartState                  => _sp.getString(_kCartState);
  Future<void> setCartState(String j)    => _sp.setString(_kCartState, j);
  Future<void> clearCartState()          => _sp.remove(_kCartState);

  /// Wipe everything — useful for debug menus / testing.
  Future<void> resetAll() async {
    await _sp.clear();
  }
}
