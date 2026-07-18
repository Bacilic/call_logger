// Μόνιμος φρουρός: καμία οθόνη σφάλματος βάσης χωρίς διέξοδο.
//
//   flutter test test/core/widgets/database_error_screen_actions_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/widgets/database_error_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

Finder _findByLabel(String label) => find.widgetWithText(OutlinedButton, label);

Finder _findTonalByLabel(String label) =>
    find.widgetWithText(FilledButton, label);

Future<void> _pumpErrorScreen(
  WidgetTester tester,
  DatabaseInitResult result, {
  String? dbPath,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: DatabaseErrorScreen(
          result: result,
          dbPath: dbPath ?? result.path,
          onRetry: () async {},
        ),
      ),
    ),
  );
  await tester.pump();
  // Ολοκλήρωση ασύγχρονης φόρτωσης πρόσφατων διαδρομών (SharedPreferences).
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final dummyMissing = p.join(
      Directory.systemTemp.path,
      'call_logger_test_nonexistent_recent.db',
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      // Μη κενή λίστα ώστε να μην επιστρέφεται AppConfig.defaultDbPath.
      'recent_database_paths': <String>[dummyMissing],
    });
  });

  group('πάντα παρόντα κουμπιά διάσωσης', () {
    testWidgets(
      'μήνυμα βάσης Λάμπας χωρίς recoveryKind: Εύρεση + Δημιουργία + Επαναδοκιμή',
      (tester) async {
        await _pumpErrorScreen(
          tester,
          const DatabaseInitResult(
            status: DatabaseStatus.corruptedOrInvalid,
            message:
                'Το αρχείο «old_equipment 2.db» είναι η βάση δεδομένων της Λάμπας. '
                'Η Καταγραφή Κλήσεων χρειάζεται το δικό της αρχείο βάσης '
                '(π.χ. call_logger.db).',
            details: r'Διαδρομή: C:\data\old_equipment 2.db',
            path: r'C:\data\old_equipment 2.db',
          ),
        );

        expect(_findByLabel('Επιλογή αρχείου βάσης'), findsOneWidget);
        expect(_findByLabel('Δημιουργία νέας βάσης'), findsOneWidget);
        expect(_findByLabel('Επαναδοκιμή'), findsOneWidget);
        expect(
          _findTonalByLabel('Αντιγραφή πλήρους σφάλματος'),
          findsOneWidget,
        );
      },
    );

    for (final status in DatabaseStatus.values) {
      testWidgets(
        'DatabaseStatus.$status: βασικά κουμπιά διάσωσης πάντα παρόντα',
        (tester) async {
          await _pumpErrorScreen(
            tester,
            DatabaseInitResult(
              status: status,
              message: 'Δοκιμαστικό μήνυμα για $status',
              path: r'C:\data\call_logger.db',
            ),
          );

          expect(_findByLabel('Επιλογή αρχείου βάσης'), findsOneWidget);
          expect(_findByLabel('Δημιουργία νέας βάσης'), findsOneWidget);
          expect(
            find.textContaining(RegExp(r'Επαναδοκιμή|Επανεκκίνηση εφαρμογής')),
            findsOneWidget,
          );
        },
      );
    }

    for (final kind in DatabaseInitRecoveryKind.values) {
      testWidgets(
        'recoveryKind.$kind: βασικά κουμπιά διάσωσης πάντα παρόντα',
        (tester) async {
          await _pumpErrorScreen(
            tester,
            DatabaseInitResult(
              status: DatabaseStatus.applicationError,
              message: 'Δοκιμαστικό για $kind',
              path: r'C:\data\call_logger.db',
              recoveryKind: kind,
            ),
          );

          expect(_findByLabel('Επιλογή αρχείου βάσης'), findsOneWidget);
          expect(_findByLabel('Δημιουργία νέας βάσης'), findsOneWidget);
          if (kind == DatabaseInitRecoveryKind.timeout) {
            expect(_findByLabel('Επανεκκίνηση εφαρμογής'), findsOneWidget);
          } else {
            expect(_findByLabel('Επαναδοκιμή'), findsOneWidget);
          }
        },
      );
    }
  });

  group('κουμπί Επαναφοράς από αντίγραφο', () {
    testWidgets('εμφανίζεται για wrongDatabaseLamp', (tester) async {
      await _pumpErrorScreen(
        tester,
        const DatabaseInitResult(
          status: DatabaseStatus.corruptedOrInvalid,
          message: 'λάθος βάση',
          recoveryKind: DatabaseInitRecoveryKind.wrongDatabaseLamp,
        ),
      );
      expect(
        _findByLabel('Επαναφορά από αντίγραφο ασφαλείας'),
        findsOneWidget,
      );
    });

    testWidgets('εμφανίζεται για wrongDatabaseUnknown', (tester) async {
      await _pumpErrorScreen(
        tester,
        const DatabaseInitResult(
          status: DatabaseStatus.corruptedOrInvalid,
          message: 'άγνωστη βάση',
          recoveryKind: DatabaseInitRecoveryKind.wrongDatabaseUnknown,
        ),
      );
      expect(
        _findByLabel('Επαναφορά από αντίγραφο ασφαλείας'),
        findsOneWidget,
      );
    });

    testWidgets('εμφανίζεται για corruptedOrMigration', (tester) async {
      await _pumpErrorScreen(
        tester,
        const DatabaseInitResult(
          status: DatabaseStatus.applicationError,
          message: 'μετανάστευση',
          recoveryKind: DatabaseInitRecoveryKind.corruptedOrMigration,
        ),
      );
      expect(
        _findByLabel('Επαναφορά από αντίγραφο ασφαλείας'),
        findsOneWidget,
      );
    });

    testWidgets('εμφανίζεται για fileNotFound', (tester) async {
      await _pumpErrorScreen(
        tester,
        const DatabaseInitResult(
          status: DatabaseStatus.fileNotFound,
          message: 'Δεν βρέθηκε',
          path: r'C:\missing\call_logger.db',
        ),
      );
      expect(
        _findByLabel('Επαναφορά από αντίγραφο ασφαλείας'),
        findsOneWidget,
      );
    });

    testWidgets('ΔΕΝ εμφανίζεται για locked', (tester) async {
      await _pumpErrorScreen(
        tester,
        const DatabaseInitResult(
          status: DatabaseStatus.accessDenied,
          message: 'κλειδωμένο',
          recoveryKind: DatabaseInitRecoveryKind.locked,
        ),
      );
      expect(
        _findByLabel('Επαναφορά από αντίγραφο ασφαλείας'),
        findsNothing,
      );
    });

    testWidgets('ΔΕΝ εμφανίζεται για timeout', (tester) async {
      await _pumpErrorScreen(
        tester,
        const DatabaseInitResult(
          status: DatabaseStatus.applicationError,
          message: 'timeout',
          recoveryKind: DatabaseInitRecoveryKind.timeout,
        ),
      );
      expect(
        _findByLabel('Επαναφορά από αντίγραφο ασφαλείας'),
        findsNothing,
      );
    });
  });

  group('πρόσφατες έγκυρες βάσεις', () {
    late Directory tempDir;
    late String existingPath;
    late String missingPath;
    late String currentPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('db_err_recent_');
      existingPath = p.join(tempDir.path, 'good.db');
      missingPath = p.join(tempDir.path, 'gone.db');
      currentPath = p.join(tempDir.path, 'current_bad.db');
      await File(existingPath).writeAsBytes(<int>[0]);
      await File(currentPath).writeAsBytes(<int>[0]);

      // Ενημέρωση στο ήδη cached SharedPreferences instance (όχι μόνο mock store).
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('recent_database_paths', <String>[
        existingPath,
        missingPath,
        currentPath,
      ]);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets(
      'εμφανίζει μόνο υπάρχουσες διαδρομές που διαφέρουν από την τρέχουσα',
      (tester) async {
        await _pumpErrorScreen(
          tester,
          DatabaseInitResult(
            status: DatabaseStatus.corruptedOrInvalid,
            message: 'λάθος αρχείο',
            path: currentPath,
            recoveryKind: DatabaseInitRecoveryKind.wrongDatabaseLamp,
          ),
          dbPath: currentPath,
        );

        expect(find.text('Πρόσφατες έγκυρες βάσεις'), findsOneWidget);
        expect(find.text('good.db'), findsOneWidget);
        expect(find.text('gone.db'), findsNothing);
        expect(find.text('current_bad.db'), findsNothing);
      },
    );
  });
}
