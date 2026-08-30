// Ο πράκτορας API γράφεται και διαβάζεται από ΜΙΑ διαδρομή.
//
// Το πεδίο των ρυθμίσεων της Αναφοράς Lansweeper και οι έλεγχοι του Καταλόγου
// έδειχναν σε διαφορετικές θέσεις: ό,τι αποθήκευε ο χρήστης δεν το έβλεπε ποτέ
// ο έλεγχος — μόνιμα για συνάδελφο χωρίς δικαιώματα διαχειριστή.
//
//   flutter test test/features/history/lansweeper_agent_username_scope_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/operator_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/features/history/providers/lansweeper_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

Future<Operator> _signIn({required bool asAdmin}) async {
  final db = await DatabaseHelper.instance.database;
  final saved = await OperatorRepository(db).insert(
    Operator(
      displayName: asAdmin ? 'Διαχειριστής' : 'Συνάδελφος',
      isAdmin: asAdmin,
      createdAt: DateTime(2026, 8, 30),
    ),
  );
  CurrentOperator.activate(saved);
  return saved;
}

/// Ο provider είναι autoDispose: χωρίς ζωντανή συνδρομή πετιέται ανάμεσα στις
/// κλήσεις, ενώ στην εφαρμογή ο διάλογος ρυθμίσεων τον κρατά όσο είναι
/// ανοιχτός. Το τεστ μιμείται εκείνον, όχι μια συνθήκη που δεν υπάρχει.
ProviderContainer _liveContainer() {
  final container = ProviderContainer(
    overrides: callLoggerTestProviderOverrides(),
  );
  final subscription = container.listen<String>(
    lansweeperAgentUsernameProvider,
    (_, _) {},
  );
  addTearDown(subscription.close);
  addTearDown(container.dispose);
  return container;
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  setUp(() async {
    CurrentOperator.reset();
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'app_settings',
      where: 'key LIKE ?',
      whereArgs: ['lansweeper_%'],
    );
  });
  tearDown(CurrentOperator.reset);

  group('πράκτορας API — μία διαδρομή για γράψιμο και διάβασμα', () {
    test(
      'συνάδελφος: ό,τι αποθήκευσε, το βλέπει ο έλεγχος καταλόγου',
      () async {
        await _signIn(asAdmin: false);
        final container = _liveContainer();

        await container
            .read(lansweeperAgentUsernameProvider.notifier)
            .setAgentUsername(r'gnk\v.drosos');

        // Η πύλη που ρωτούν οι έλεγχοι του Καταλόγου και οι καρτέλες.
        expect(
          await SettingsService().remoteLansweeper.getLansweeperAgentUsername(),
          r'gnk\v.drosos',
        );
      },
    );

    test('διαχειριστής: η αλλαγή δεν παγώνει στην πρώτη τιμή', () async {
      await _signIn(asAdmin: true);
      final container = _liveContainer();

      final notifier = container.read(lansweeperAgentUsernameProvider.notifier);
      await notifier.setAgentUsername(r'gnk\palio');
      // Η πρώτη ανάγνωση «κληρονομεί» — και μετά η δεύτερη αλλαγή έπρεπε να
      // ακολουθήσει, αντί να μείνει ο κατάλογος με την παλιά τιμή.
      await SettingsService().remoteLansweeper.getLansweeperAgentUsername();
      await notifier.setAgentUsername(r'gnk\neo');

      expect(
        await SettingsService().remoteLansweeper.getLansweeperAgentUsername(),
        r'gnk\neo',
      );
    });

    test('η τιμή του κάθε χρήστη είναι δική του', () async {
      final first = await _signIn(asAdmin: false);
      final container = _liveContainer();
      await container
          .read(lansweeperAgentUsernameProvider.notifier)
          .setAgentUsername(r'gnk\protos');

      CurrentOperator.reset();
      await _signIn(asAdmin: false);
      expect(
        await SettingsService().remoteLansweeper.getLansweeperAgentUsername(),
        isNull,
        reason: 'ο δεύτερος συνάδελφος ξεκινά χωρίς πράκτορα',
      );

      CurrentOperator.activate(first);
      expect(
        await SettingsService().remoteLansweeper.getLansweeperAgentUsername(),
        r'gnk\protos',
      );
    });
  });
}
