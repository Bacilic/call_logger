// Η συγκατάθεση αναβάθμισης σχήματος ακολουθεί το αρχείο που θα ανοίξει —
// και στο αντίγραφο, όχι μόνο στο πρωτότυπο. Χωρίς αυτό, η επιλογή
// «Αναβάθμιση αντιγράφου» δημιουργεί το αντίγραφο και μετά ο φρουρός
// σχήματος το ξαναμπλοκάρει ως «χωρίς συγκατάθεση» («Αποτυχία ανοίγματος
// αντιγράφου», 20/08/2026).
//
// Η επιλογή του χρήστη δίνεται έτοιμη (askConsent) και η ροή τρέχει
// ολόκληρη μέσα σε tester.runAsync: πραγματικά αρχεία και βάση SQLite δεν
// προχωρούν κάτω από το παγωμένο ρολόι του testWidgets (βλ. μνήμη
// fake-clock). Τα κουμπιά του διαλόγου κάνουν σκέτο pop — δικό τους τεστ
// δεν χρειάζεται· εδώ φυλάμε την ενορχήστρωση.
//
//   flutter test test/features/database/schema_upgrade_consent_copy_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/features/database/widgets/schema_upgrade_consent_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Πραγματικό αρχείο SQLite παλαιού σχήματος (user_version 36) — ώστε ο
/// υπολογισμός ταυτότητας συγκατάθεσης να δουλεύει πάνω σε αληθινή βάση.
Future<String> _createOldSchemaDb(Directory dir, String name) async {
  final dbPath = p.join(dir.path, name);
  final db = await openDatabase(dbPath);
  await db.execute(
    'CREATE TABLE calls (id INTEGER PRIMARY KEY, call_date TEXT)',
  );
  await db.execute('PRAGMA user_version = 36');
  await db.close();
  return dbPath;
}

DatabaseInitResult _schemaMismatchResult(String dbPath) => DatabaseInitResult(
  status: DatabaseStatus.corruptedOrInvalid,
  message: 'Αναντιστοιχία σχήματος (δοκιμή).',
  path: dbPath,
  recoveryKind: DatabaseInitRecoveryKind.schemaUpgradeConsent,
  technicalCode: '36→47',
);

const _okOutcome = (
  ok: true,
  runner: DatabaseInitRunnerResult(
    result: DatabaseInitResult(status: DatabaseStatus.success),
    isLocalDevMode: false,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    initSqfliteFfiForTests();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = Directory.systemTemp.createTempSync('consent_copy_test_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Ζωντανό BuildContext για τη ροή — χωρίς πάτημα κουμπιών.
  Future<BuildContext> mountContext(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              captured = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return captured;
  }

  testWidgets(
    'Αναβάθμιση αντιγράφου: η συγκατάθεση καταγράφεται για το ΑΝΤΙΓΡΑΦΟ '
    'πριν από το άνοιγμά του',
    (tester) async {
      final ctx = await mountContext(tester);

      String? openedPath;
      String? consentAtOpen;
      var successCalls = 0;

      final outcome = await tester.runAsync(() async {
        final dbPath = await _createOldSchemaDb(tempDir, 'old_schema.db');
        final ok = await runSchemaUpgradeConsentRecovery(
          context: ctx,
          result: _schemaMismatchResult(dbPath),
          onSuccess: () async => successCalls++,
          askConsent: (_, _, _, _) async =>
              SchemaUpgradeConsentChoice.upgradeCopy,
          openAndVerify: (path) async {
            openedPath = path;
            consentAtOpen = await SettingsService()
                .getSchemaUpgradeConsentIdentity();
            return _okOutcome;
          },
        );
        final expectedIdentity = openedPath == null
            ? null
            : await schemaUpgradeConsentIdentityForPath(openedPath!);
        return (ok: ok, dbPath: dbPath, expectedIdentity: expectedIdentity);
      });
      await tester.pumpAndSettle();

      // Το άνοιγμα αφορά το αντίγραφο (όχι το πρωτότυπο), που όντως υπάρχει.
      expect(openedPath, isNotNull);
      expect(openedPath, isNot(outcome!.dbPath));
      expect(p.basename(openedPath!), contains('_αναβαθμισμένη_'));
      expect(File(openedPath!).existsSync(), isTrue);
      // Το πρωτότυπο μένει στη θέση του.
      expect(File(outcome.dbPath).existsSync(), isTrue);

      // Το συμβόλαιο: τη στιγμή του ανοίγματος έχει ήδη καταγραφεί συγκατάθεση
      // με την ταυτότητα του ΑΝΤΙΓΡΑΦΟΥ — αλλιώς ο φρουρός σχήματος θα το
      // μπλόκαρε ξανά ως «χωρίς συγκατάθεση».
      expect(consentAtOpen, isNotNull);
      expect(consentAtOpen, outcome.expectedIdentity);

      // Η ροή ολοκληρώνεται ως επιτυχία, χωρίς διάλογο αποτυχίας.
      expect(outcome.ok, isTrue);
      expect(successCalls, 1);
      expect(find.text('Αποτυχία ανοίγματος αντιγράφου'), findsNothing);
    },
  );

  testWidgets(
    'Αναβάθμιση πρωτοτύπου: η συγκατάθεση καταγράφεται για το πρωτότυπο '
    'πριν από το άνοιγμα',
    (tester) async {
      final ctx = await mountContext(tester);

      String? openedPath;
      String? consentAtOpen;

      final outcome = await tester.runAsync(() async {
        final dbPath = await _createOldSchemaDb(tempDir, 'old_schema.db');
        final ok = await runSchemaUpgradeConsentRecovery(
          context: ctx,
          result: _schemaMismatchResult(dbPath),
          onSuccess: () async {},
          askConsent: (_, _, _, _) async =>
              SchemaUpgradeConsentChoice.upgradeOriginal,
          openAndVerify: (path) async {
            openedPath = path;
            consentAtOpen = await SettingsService()
                .getSchemaUpgradeConsentIdentity();
            return _okOutcome;
          },
        );
        final expectedIdentity = await schemaUpgradeConsentIdentityForPath(
          dbPath,
        );
        return (ok: ok, dbPath: dbPath, expectedIdentity: expectedIdentity);
      });
      await tester.pumpAndSettle();

      expect(outcome!.ok, isTrue);
      expect(openedPath, outcome.dbPath);
      expect(consentAtOpen, outcome.expectedIdentity);
    },
  );

  testWidgets('Άκυρο: κανένα άνοιγμα, καμία συγκατάθεση, κανένα αντίγραφο', (
    tester,
  ) async {
    final ctx = await mountContext(tester);

    var openCalls = 0;

    final outcome = await tester.runAsync(() async {
      final dbPath = await _createOldSchemaDb(tempDir, 'old_schema.db');
      final ok = await runSchemaUpgradeConsentRecovery(
        context: ctx,
        result: _schemaMismatchResult(dbPath),
        onSuccess: () async {},
        askConsent: (_, _, _, _) async => SchemaUpgradeConsentChoice.cancel,
        openAndVerify: (path) async {
          openCalls++;
          return _okOutcome;
        },
      );
      final consent = await SettingsService().getSchemaUpgradeConsentIdentity();
      return (ok: ok, consent: consent);
    });
    await tester.pumpAndSettle();

    expect(outcome!.ok, isFalse);
    expect(openCalls, 0);
    expect(outcome.consent, isNull);
    final copies = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).contains('_αναβαθμισμένη_'))
        .toList();
    expect(copies, isEmpty);
  });
}
