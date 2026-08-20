/// Where the mobile app talks to.
///
/// Production points at the hosted domain over HTTPS. For LAN development,
/// swap the two constants below to `http://192.168.100.31:8000` (dev laptop
/// LAN IP) — or `http://10.0.2.2:8000` for the Android emulator — and put
/// `android:usesCleartextTraffic="true"` back in AndroidManifest.xml.
class ApiConfig {
  const ApiConfig._();

  /// Publicly-hosted API base — HTTPS, ATS-compliant, works from any
  /// network (not just the developer's LAN).
  static const String baseUrl = 'http://192.168.100.31:8000/api/v1';

  /// Root of the same server (no `/api/v1`) — used for browser-facing pages
  /// like the privacy policy that live on web.php, not api.php.
  static const String webBaseUrl = 'http://192.168.100.31:8000';

  /// Publicly-hosted privacy policy. Same URL is submitted to Play Store and
  /// App Store listings and opened from Profile → «الشروط والخصوصية».
  static const String privacyPolicyUrl = '$webBaseUrl/privacy';

  /// If a request takes longer than this to connect, give up.
  static const Duration connectTimeout = Duration(seconds: 8);

  /// If a response doesn't arrive within this window, give up.
  static const Duration receiveTimeout = Duration(seconds: 12);
}
