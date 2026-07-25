import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathA =
      r'F:\flutter_projects\call_logger\Data Base\Δοκιμές\μόνο_κλήσεις.db';
  const pathB =
      r'C:\Users\Bacilic\Documents\call_logger\DB\call_logger.db';
  const pathC = r'E:\call logger\data\call_logger.db';
  const pathD = r'\\server\share\call_logger.db';

  late SettingsService settings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsService();
  });

  test(
    'setDatabasePath δεν γράφει στη λίστα πρόσφατων (αναπαραγωγή σφάλματος)',
    () async {
      await settings.setDatabasePath(pathA);
      final recent = await settings.getRecentDatabasePaths();
      expect(recent, isNot(contains(pathA)));
    },
  );

  test(
    'recordVerifiedDatabasePath βάζει πρώτη τη διαδρομή και σπρώχνει την προηγούμενη',
    () async {
      await settings.recordVerifiedDatabasePath(pathA);
      expect(await settings.getRecentDatabasePaths(), [pathA]);

      await settings.recordVerifiedDatabasePath(pathB);
      expect(await settings.getRecentDatabasePaths(), [pathB, pathA]);
    },
  );

  test('όριο τριών θέσεων: η παλαιότερη πέφτει στην τέταρτη εγγραφή', () async {
    await settings.recordVerifiedDatabasePath(pathA);
    await settings.recordVerifiedDatabasePath(pathB);
    await settings.recordVerifiedDatabasePath(pathC);
    await settings.recordVerifiedDatabasePath(pathD);

    expect(await settings.getRecentDatabasePaths(), [pathD, pathC, pathB]);
  });

  test(
    'ίδια βάση με διαφορετικά πεζά-κεφαλαία δεν διπλοεγγράφεται· κερδίζει η νεότερη γραφή',
    () async {
      const lower =
          r'f:\flutter_projects\call_logger\data base\δοκιμές\μόνο_κλήσεις.db';
      await settings.recordVerifiedDatabasePath(pathA);
      await settings.recordVerifiedDatabasePath(pathB);
      await settings.recordVerifiedDatabasePath(lower);

      final recent = await settings.getRecentDatabasePaths();
      expect(recent.first, lower);
      expect(recent.where((p) => p.toLowerCase() == pathA.toLowerCase()).length, 1);
      expect(recent, contains(pathB));
    },
  );

  test(
    'forgetRecentDatabasePath αφαιρεί ακόμη κι όταν διαφέρουν τα πεζά-κεφαλαία',
    () async {
      await settings.recordVerifiedDatabasePath(pathA);
      await settings.recordVerifiedDatabasePath(pathB);
      await settings.forgetRecentDatabasePath(
        r'f:\flutter_projects\call_logger\data base\δοκιμές\μόνο_κλήσεις.db',
      );

      final recent = await settings.getRecentDatabasePaths();
      expect(recent, isNot(contains(pathA)));
      expect(recent, contains(pathB));
    },
  );

  group('getRecentDatabasePaths ανάγνωση', () {
    test(
      'χωρίς αποθηκευμένη τιμή επιστρέφει κενή λίστα (αναπαραγωγή σφάλματος)',
      () async {
        expect(await settings.getRecentDatabasePaths(), isEmpty);
      },
    );

    test('με αποθηκευμένη κενή λίστα επιστρέφει κενή λίστα', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('recent_database_paths', <String>[]);
      expect(await settings.getRecentDatabasePaths(), isEmpty);
    });

    test(
      'κενές συμβολοσειρές φιλτράρονται· οι πραγματικές διαδρομές μένουν με τη σειρά τους',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('recent_database_paths', <String>[
          '',
          pathA,
          '   ',
          pathB,
        ]);
        expect(await settings.getRecentDatabasePaths(), [pathA, pathB]);
      },
    );

    test(
      'μετά από μία επαληθευμένη καταγραφή επιστρέφει μόνο αυτή — χωρίς συνθετική',
      () async {
        await settings.recordVerifiedDatabasePath(pathA);
        expect(await settings.getRecentDatabasePaths(), [pathA]);
      },
    );
  });
}
