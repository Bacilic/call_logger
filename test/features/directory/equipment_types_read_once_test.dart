// Οι κοινές λίστες του Καταλόγου (τύποι εξοπλισμού) ζουν στο `app_settings` της
// βάσης. Σε κοινόχρηστη βάση πάνω σε δικτυακό φάκελο κάθε ανάγνωση είναι γύρος
// στο δίκτυο — άρα η φόρμα οφείλει να ρωτά ΜΙΑ φορά, όχι σε κάθε πληκτρολόγηση.
//
//   flutter test test/features/directory/equipment_types_read_once_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/providers/equipment_directory_provider.dart';
import 'package:call_logger/features/directory/providers/equipment_types_provider.dart';
import 'package:call_logger/features/directory/screens/widgets/equipment_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

const _kOpenButton = 'OPEN_EQUIP_FORM';

Finder _codeField() => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is InputDecorator && w.decoration.labelText == 'Κωδικός',
  ),
  matching: find.byType(EditableText),
);

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  /// Πόσες φορές ρωτήθηκε η ΒΑΣΗ για το κλειδί των τύπων εξοπλισμού.
  ///
  /// Μετράμε την πραγματική έξοδο — την ανάγνωση — όχι πόσες φορές χτίστηκε το
  /// widget: το ζητούμενο είναι το κόστος στο δίκτυο, όχι ο αριθμός των frames.
  var reads = 0;

  setUp(() async {
    reads = 0;
    final db = await DatabaseHelper.instance.database;
    SettingsService.registerAppSettingsProvider(
      (key) async {
        if (key == 'equipment_types') reads++;
        return SettingsRepository(db).getSetting(key);
      },
      (key, value) => SettingsRepository(db).saveSetting(key, value),
      (key, change) => SettingsRepository(db).updateSetting(key, change),
    );
  });

  //   flutter test test/features/directory/equipment_types_read_once_test.dart --plain-name "πληκτρολόγηση"
  testWidgets(
    'η πληκτρολόγηση στον Κωδικό δεν ξαναρωτά τη βάση για τους τύπους',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      late EquipmentDirectoryNotifier notifier;
      await tester.runAsync(() async {
        await container.read(lookupServiceProvider.future);
        notifier = container.read(equipmentDirectoryProvider.notifier);
        await notifier.load();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (ctx) => EquipmentFormDialog(notifier: notifier),
                    ),
                    child: const Text(_kOpenButton),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text(_kOpenButton));
      await pumpUntilSettledLong(tester);

      final afterOpen = reads;
      expect(
        afterOpen,
        lessThanOrEqualTo(1),
        reason: greekExpectMsg(
          'Το άνοιγμα της φόρμας ρωτά τη βάση το πολύ μία φορά',
        ),
      );

      // Τέσσερις χαρακτήρες σε κωδικό εξοπλισμού — όπως το «3731».
      for (final code in ['3', '37', '373', '3731']) {
        await tester.enterText(_codeField(), code);
        await pumpUntilSettled(tester);
      }

      expect(
        reads,
        afterOpen,
        reason: greekExpectMsg(
          'Η πληκτρολόγηση δεν προσθέτει ερωτήματα στη βάση — η λίστα των '
          'τύπων διαβάστηκε ήδη',
        ),
      );

      await flushCallLoggerSqfliteLockTimers(tester);
    },
  );

  // Η άλλη πλευρά του ίδιου συμβολαίου: όταν αλλάξει η λίστα, η ανανέωση
  // πρέπει να συμβεί — αλλιώς το «διαβάζεται μία φορά» θα σήμαινε «μένει
  // παγωμένη μέχρι την επόμενη εκκίνηση».
  testWidgets('μετά από αλλαγή της λίστας, η ανανέωση δίνει τη νέα', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      expect(await container.read(equipmentTypesProvider.future), [
        'Υπολογιστής',
        'Εκτυπωτής',
      ], reason: 'κενή ρύθμιση → οι προεπιλογές');
      expect(reads, 1);

      await SettingsService().catalogs.setEquipmentTypes(
        'Υπολογιστής, Εκτυπωτής, Σαρωτής',
        expected: null,
      );
      container.invalidate(equipmentTypesProvider);

      expect(await container.read(equipmentTypesProvider.future), [
        'Υπολογιστής',
        'Εκτυπωτής',
        'Σαρωτής',
      ]);
      expect(
        reads,
        2,
        reason: 'η ανανέωση είναι ρητή — δεν συμβαίνει σε κάθε χτίσιμο',
      );
    });

    await flushCallLoggerSqfliteLockTimers(tester);
  });
}
