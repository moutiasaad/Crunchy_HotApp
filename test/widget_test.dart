// Smoke test — verify the splash screen renders and navigates cleanly.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crunchy_hot/main.dart';
import 'package:crunchy_hot/services/api_client.dart';
import 'package:crunchy_hot/services/app_config_service.dart';
import 'package:crunchy_hot/services/app_prefs.dart';
import 'package:crunchy_hot/services/push_notifications_service.dart';

void main() {
  setUp(() async {
    // AppPrefs.init() reads from SharedPreferences — mock it in tests.
    SharedPreferences.setMockInitialValues({});
    await AppPrefs.init();
  });

  testWidgets('App boots, splash renders, no exceptions', (WidgetTester tester) async {
    // Build the app the same way main() does, minus Firebase.initializeApp
    // (would need a mock — smoke test only cares about first paint).
    final apiClient   = ApiClient(AppPrefs.instance);
    final pushService = PushNotificationsService(apiClient);
    final appConfig   = AppConfigService(apiClient);
    await tester.pumpWidget(CrunchyHotApp(
      apiClient:   apiClient,
      appConfig:   appConfig,
      pushService: pushService,
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('FAST FOOD'), findsOneWidget);

    // Let the splash sequence + navigation animations complete.
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(tester.takeException(), isNull);
  });
}
