import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsService settings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsService();
  });

  group('SettingsService.setDatabasePath — φρουρός κενής διαδρομής', () {
    test('κενή διαδρομή απορρίπτεται με ArgumentError', () async {
      await expectLater(
        settings.setDatabasePath(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('διαδρομή μόνο με κενά απορρίπτεται με ArgumentError', () async {
      await expectLater(
        settings.setDatabasePath('   '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('η απόρριψη δεν αγγίζει την αποθηκευμένη διαδρομή', () async {
      const valid = r'C:\data\call_logger.db';
      await settings.setDatabasePath(valid);
      try {
        await settings.setDatabasePath('');
      } on ArgumentError {
        // αναμενόμενο
      }
      expect(await settings.getDatabasePath(), valid);
    });

    test('έγκυρη διαδρομή αποθηκεύεται με trim', () async {
      await settings.setDatabasePath(r'  C:\data\call_logger.db  ');
      expect(await settings.getDatabasePath(), r'C:\data\call_logger.db');
    });
  });
}
