// Έλεγχος: ο provider που ΕΚΤΕΛΕΙ τις αλλαγές Lansweeper επιβιώνει χωρίς
// ακροατή — όπως τον καλεί το μενού γραμμής στο Ιστορικό Κλήσεων.
//
// Το μενού απλώς διαβάζει τον notifier και του δίνει τη δουλειά· καμία οθόνη
// δεν τον παρακολουθεί. Όσο ήταν autoDispose, πέθαινε στο πρώτο await και η
// εγγραφή τελείωνε πάνω σε νεκρό Ref.
//
//   flutter test test/features/history/lansweeper_sync_provider_lifetime_test.dart

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/history/models/lansweeper_sync_state.dart';
import 'package:call_logger/features/history/providers/lansweeper_sync_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

const _kLifetimeMarker = 'LS_SYNC_LIFETIME_TEST';

Future<int> _insertSentCall() async {
  final db = await DatabaseHelper.instance.database;
  return CallsRepository(db).insertCall(
    CallModel(
      phoneText: kTestPhoneDigits,
      issue: _kLifetimeMarker,
      status: 'completed',
      lansweeperState: LansweeperSyncState.sent,
    ),
  );
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Lansweeper sync — διάρκεια ζωής του provider', () {
    setUp(() async {
      await bindCallLoggerIsolatedTestDatabase();
    });

    test('ο notifier επιβιώνει όταν κανείς δεν τον ακούει', () async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      final first = container.read(lansweeperSyncProvider.notifier);
      // Ο χρόνος που μεσολαβεί όσο ο χρήστης απαντά στους διαλόγους της ροής.
      await Future<void>.delayed(Duration.zero);
      final second = container.read(lansweeperSyncProvider.notifier);

      expect(
        identical(first, second),
        isTrue,
        reason:
            'Ο provider που εκτελεί εγγραφές δεν επιτρέπεται να πεθάνει '
            'ανάμεσα στο διάβασμά του και στη δουλειά του — εκεί ζει και η '
            'προστασία από διπλή αποστολή.',
      );
    });

    test('η επαναφορά σε ακαταχώρητη ολοκληρώνεται χωρίς ακροατή', () async {
      final callId = await _insertSentCall();
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      // Ακριβώς ό,τι κάνει το μενού γραμμής: ένα read, κανένα watch.
      final notifier = container.read(lansweeperSyncProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      final written = await notifier.setUnsent(callId, expected: null);

      expect(written, isTrue);
      final db = await DatabaseHelper.instance.database;
      final stored = await CallsRepository(db).getCallById(callId);
      expect(stored?.lansweeperState, LansweeperSyncState.unsent);
    });
  });
}
