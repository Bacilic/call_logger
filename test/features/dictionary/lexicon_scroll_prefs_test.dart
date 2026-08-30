// Οι προτιμήσεις κύλισης του Λεξικού ανήκουν στον χρήστη που τις έκανε.
//
// Ως τώρα γράφονταν στην κοινή θέση, ενώ τα κλειδιά είναι δηλωμένα προσωπικά:
// όποιος άλλαζε τελευταίος, άλλαζε και του άλλου. Το γράψιμο ζούσε μέσα σε
// κουμπιά της οθόνης, με δικό του αντίγραφο κωδικοποίησης.
//
//   flutter test test/features/dictionary/lexicon_scroll_prefs_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/operator_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/features/dictionary/providers/lexicon_scroll_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

Future<void> _signIn(String name) async {
  final db = await DatabaseHelper.instance.database;
  final saved = await OperatorRepository(
    db,
  ).insert(Operator(displayName: name, createdAt: DateTime(2026, 8, 30)));
  CurrentOperator.activate(saved);
}

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: callLoggerTestProviderOverrides(),
  );
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
      whereArgs: ['lexicon_%'],
    );
  });
  tearDown(CurrentOperator.reset);

  group('συνεχής κύλιση', () {
    test('η επιλογή του ενός δεν αλλάζει του άλλου', () async {
      await _signIn('Βασίλης');
      final mine = _container();
      await mine.read(lexiconContinuousScrollProvider.future);
      await mine
          .read(lexiconContinuousScrollProvider.notifier)
          .setEnabled(false);
      expect(await mine.read(lexiconContinuousScrollProvider.future), isFalse);

      await _signIn('Συνάδελφος');
      final theirs = _container();
      expect(
        await theirs.read(lexiconContinuousScrollProvider.future),
        isTrue,
        reason: 'ο συνάδελφος κρατά την προεπιλογή, όχι τη δική μου επιλογή',
      );
    });
  });

  group('λέξεις ανά σελίδα', () {
    test('η επιλογή του ενός δεν αλλάζει του άλλου', () async {
      await _signIn('Βασίλης');
      final mine = _container();
      await mine.read(lexiconPageSizeProvider.future);
      await mine.read(lexiconPageSizeProvider.notifier).setPageSize(200);
      expect(await mine.read(lexiconPageSizeProvider.future), 200);

      await _signIn('Συνάδελφος');
      final theirs = _container();
      expect(await theirs.read(lexiconPageSizeProvider.future), 40);
    });

    test('τα όρια ισχύουν και στην ΕΓΓΡΑΦΗ, όχι μόνο στην ανάγνωση', () async {
      await _signIn('Βασίλης');
      final container = _container();
      await container.read(lexiconPageSizeProvider.future);
      final notifier = container.read(lexiconPageSizeProvider.notifier);

      await notifier.setPageSize(5000);
      expect(await container.read(lexiconPageSizeProvider.future), 500);

      await notifier.setPageSize(1);
      expect(await container.read(lexiconPageSizeProvider.future), 10);
    });
  });
}
