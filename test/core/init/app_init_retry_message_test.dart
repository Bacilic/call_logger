// Μήνυμα αποτυχίας της επαναδοκιμής αρχικοποίησης.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/core/init/app_init_retry_message_test.dart

import 'package:call_logger/core/database/database_path_resolution.dart';
import 'package:call_logger/core/database/database_switch_success_notice.dart';
import 'package:call_logger/core/init/app_init_retry_runner.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Ο κανόνας: η πράσινη «αλλαγή βάσης» βγαίνει μόνο όταν η βάση που ανοίγει
  // είναι ΑΛΛΗ από εκείνη που απέτυχε.
  group('Πράσινη λωρίδα μετά την επαναδοκιμή', () {
    const network = r'\\popinio\CallLogger\Data Base\hospital.db';
    const other = r'C:\CallLogger\allh.db';

    Future<ProviderContainer> retry(
      WidgetTester tester, {
      required String? failedPath,
      String configured = network,
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await SettingsService().setDatabasePath(configured);
      final container = ProviderContainer(
        overrides: [
          lookupServiceProvider.overrideWith(
            (ref) async => LookupLoadResult(service: LookupService.instance),
          ),
        ],
      );
      addTearDown(container.dispose);
      late WidgetRef widgetRef;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                widgetRef = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await runAppInitRetry(ref: widgetRef, failedDatabasePath: failedPath);
      await tester.pump();
      return container;
    }

    tearDown(LocalDatabaseSessionFallback.forget);

    testWidgets('μετά τη «Χρήση τοπικής βάσης» δεν ανακοινώνει τη δικτυακή', (
      tester,
    ) async {
      LocalDatabaseSessionFallback.accept(network, r'C:\CallLogger\local.db');

      final container = await retry(tester, failedPath: network);

      expect(
        container.read(databaseSwitchSuccessNoticeProvider),
        isNull,
        reason:
            'Άνοιξε η τοπική· η πράσινη «αλλαγή βάσης: \\\\popinio…» έλεγε '
            'ψέματα κάτω από την κίτρινη λωρίδα',
      );
    });

    testWidgets('η απλή «Επαναδοκιμή» της ίδιας βάσης δεν ανακοινώνει', (
      tester,
    ) async {
      final container = await retry(tester, failedPath: network);

      expect(
        container.read(databaseSwitchSuccessNoticeProvider),
        isNull,
        reason: 'Απλώς ξεκίνησε η εφαρμογή — δεν άλλαξε καμία βάση',
      );
    });

    testWidgets('επαναδοκιμή μετά από επιλογή άλλης βάσης ανακοινώνει', (
      tester,
    ) async {
      final container = await retry(
        tester,
        failedPath: network,
        configured: other,
      );

      expect(
        container.read(databaseSwitchSuccessNoticeProvider),
        databaseSwitchSuccessMessage(other),
      );
    });

    testWidgets('άγνωστη βάση αποτυχίας: σιωπή αντί για πιθανό ψέμα', (
      tester,
    ) async {
      final container = await retry(tester, failedPath: null);

      expect(container.read(databaseSwitchSuccessNoticeProvider), isNull);
    });
  });

  group('Μήνυμα αποτυχίας επαναδοκιμής αρχικοποίησης', () {
    test('χωρίς αποτυχία κλεισίματος επιστρέφει σκέτο το βασικό μήνυμα', () {
      final message = composeAppInitRetryFailureMessage(
        base: 'Η βάση δεν βρέθηκε.',
        closeFailure: null,
      );

      expect(message, 'Η βάση δεν βρέθηκε.');
    });

    test('με αποτυχία κλεισίματος εξηγεί και το κλείδωμα του αρχείου', () {
      final message = composeAppInitRetryFailureMessage(
        base: 'Η βάση δεν βρέθηκε.',
        closeFailure: Exception('database is locked'),
      );

      expect(message, startsWith('Η βάση δεν βρέθηκε.'));
      expect(message, contains('Το κλείσιμο της τρέχουσας σύνδεσης απέτυχε'));
      expect(message, contains('άλλο ανοιχτό αντίγραφο'));
    });
  });

  group('Αποτέλεσμα επαναδοκιμής', () {
    test('η επιτυχία δεν κουβαλά μήνυμα σφάλματος', () {
      const outcome = AppInitRetryOutcome.success();

      expect(outcome.succeeded, isTrue);
      expect(outcome.errorMessage, isNull);
    });

    test('η αποτυχία κουβαλά το μήνυμα προς εμφάνιση', () {
      const outcome = AppInitRetryOutcome.failure('Κάτι πήγε στραβά.');

      expect(outcome.succeeded, isFalse);
      expect(outcome.errorMessage, 'Κάτι πήγε στραβά.');
    });
  });
}
