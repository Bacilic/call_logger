// Οι ρυθμίσεις ΤΝ που είναι δηλωμένες προσωπικές ανήκουν στον χρήστη τους.
//
// Η προεπιλογή προτροπής και η αυτόματη επανυποβολή γράφονταν στην κοινή θέση,
// παρακάμπτοντας τη διαδρομή των προφίλ: ο ένας συνάδελφος άλλαζε τη ρύθμιση
// του άλλου. Ο κύριος provider προτροπής, δίπλα τους, το έκανε ήδη σωστά.
//
//   flutter test test/features/history/gemini_personal_settings_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/operator_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/services/profile_settings.dart';
import 'package:call_logger/core/services/scoped_settings.dart';
import 'package:call_logger/features/history/providers/gemini_settings_provider.dart';
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

/// Οι providers είναι autoDispose: χωρίς ζωντανή συνδρομή πετιούνται ανάμεσα
/// στις κλήσεις, ενώ στην εφαρμογή η οθόνη τους κρατά όσο είναι ανοιχτή.
ProviderContainer _liveContainer() {
  final container = ProviderContainer(
    overrides: callLoggerTestProviderOverrides(),
  );
  addTearDown(
    container
        .listen<String?>(geminiPromptTemplateUserDefaultProvider, (_, _) {})
        .close,
  );
  addTearDown(
    container.listen<bool>(geminiAutoResubmitEnabledProvider, (_, _) {}).close,
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
      whereArgs: ['gemini_%'],
    );
  });
  tearDown(CurrentOperator.reset);

  group('προεπιλογή προτροπής ΤΝ', () {
    test('η προεπιλογή του ενός δεν φτάνει στον άλλον', () async {
      await _signIn('Βασίλης');
      await _liveContainer()
          .read(geminiPromptTemplateUserDefaultProvider.notifier)
          .setUserDefault('Η δική μου προτροπή');

      expect(
        await ScopedSettings.getString(
          ProfileSettingKeys.geminiPromptTemplateUserDefault,
        ),
        'Η δική μου προτροπή',
      );

      await _signIn('Συνάδελφος');
      expect(
        await ScopedSettings.getString(
          ProfileSettingKeys.geminiPromptTemplateUserDefault,
        ),
        isNull,
      );
    });

    test('το σβήσιμο σβήνει και δεν επιστρέφει στο επόμενο άνοιγμα', () async {
      await _signIn('Βασίλης');
      final notifier = _liveContainer().read(
        geminiPromptTemplateUserDefaultProvider.notifier,
      );
      await notifier.setUserDefault('Η δική μου προτροπή');
      // Χωρίς αυτό, το τεστ θα περνούσε και με ρύθμιση που δεν γράφτηκε ποτέ.
      expect(
        await ScopedSettings.getString(
          ProfileSettingKeys.geminiPromptTemplateUserDefault,
        ),
        isNotNull,
        reason: 'προϋπόθεση: η προεπιλογή είχε όντως αποθηκευτεί',
      );

      await notifier.setUserDefault('   ');

      expect(
        await ScopedSettings.getString(
          ProfileSettingKeys.geminiPromptTemplateUserDefault,
        ),
        isNull,
        reason: 'ό,τι φαίνεται σβησμένο πρέπει να είναι σβησμένο',
      );
    });
  });

  group('αυτόματη επανυποβολή ΤΝ', () {
    test('ο διακόπτης του ενός δεν αλλάζει τη ρύθμιση του άλλου', () async {
      await _signIn('Βασίλης');
      await _liveContainer()
          .read(geminiAutoResubmitEnabledProvider.notifier)
          .setEnabled(true);

      expect(
        await ScopedSettings.getBool(ProfileSettingKeys.geminiAutoResubmit),
        isTrue,
      );

      await _signIn('Συνάδελφος');
      expect(
        await ScopedSettings.getBool(ProfileSettingKeys.geminiAutoResubmit),
        isNull,
        reason: 'ο δεύτερος ξεκινά με τη δική του (ανύπαρκτη) ρύθμιση',
      );
    });
  });
}
