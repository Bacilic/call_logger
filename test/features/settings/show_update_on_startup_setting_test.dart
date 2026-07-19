// Ρύθμιση show_update_on_startup — προεπιλογή true, get/set.
//
//   flutter test test/features/settings/show_update_on_startup_setting_test.dart

import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('getShowUpdateOnStartup προεπιλογή true', () async {
    final settings = SettingsService();
    expect(await settings.getShowUpdateOnStartup(), isTrue);
  });

  test('setShowUpdateOnStartup αποθηκεύει false και true', () async {
    final settings = SettingsService();
    await settings.setShowUpdateOnStartup(false);
    expect(await settings.getShowUpdateOnStartup(), isFalse);

    await settings.setShowUpdateOnStartup(true);
    expect(await settings.getShowUpdateOnStartup(), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('show_update_on_startup'), isTrue);
  });
}
