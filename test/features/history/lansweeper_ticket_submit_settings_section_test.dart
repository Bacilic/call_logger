// Widget test: ενότητα παραμετροποίησης καταχώρησης Lansweeper.
//
//   flutter test test/features/history/lansweeper_ticket_submit_settings_section_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/services/lansweeper_ticket_submit_config.dart';
import 'package:call_logger/features/history/providers/lansweeper_ticket_submit_config_provider.dart';
import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_ticket_submit_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';
import 'lansweeper_report_test_doubles.dart';

Finder _dropdownByLabel(String label) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == label,
  );
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('τιμές με κόμμα (parseCommaValues/commaText)', () {
    test('κόβει κενά γύρω από τις τιμές και αγνοεί κενά τμήματα', () {
      expect(
        LansweeperTicketSubmitSettingsSection.parseCommaValues(
          ' Open, Closed ,In Progress,,  ,',
        ),
        ['Open', 'Closed', 'In Progress'],
      );
    });

    test('κρατά τα εσωτερικά κενά μιας τιμής', () {
      expect(
        LansweeperTicketSubmitSettingsSection.parseCommaValues(
          'In Progress, Waiting for user',
        ),
        ['In Progress', 'Waiting for user'],
      );
    });

    test('commaText: ενιαία μορφή «τιμή, τιμή» και πλήρης κύκλος', () {
      const values = ['Open', 'Closed', 'In Progress'];
      final text = LansweeperTicketSubmitSettingsSection.commaText(values);
      expect(text, 'Open, Closed, In Progress');
      expect(
        LansweeperTicketSubmitSettingsSection.parseCommaValues(text),
        values,
      );
    });
  });

  group('LansweeperTicketSubmitSettingsSection', () {
    tearDown(() async {
      final db = await DatabaseHelper.instance.database;
      await db.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: [kLansweeperTicketSubmitConfigSettingKey],
      );
    });

    Future<ProviderContainer> pumpSection(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer(
        overrides: [
          ...callLoggerTestProviderOverrides(),
          lansweeperTicketSubmitConfigProvider.overrideWith(
            FixedLansweeperTicketSubmitConfigNotifier.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      container.listen(lansweeperTicketSubmitConfigProvider, (_, _) {});
      await container
          .read(lansweeperTicketSubmitConfigProvider.notifier)
          .hydrationFuture;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: LansweeperTicketSubmitSettingsSection(),
              ),
            ),
          ),
        ),
      );
      await pumpUntilSettled(tester);
      return container;
    }

    testWidgets(
      'η ενότητα αποδίδει «Τύπος σημείωσης» με «Ιδιωτική»/«Δημόσια» και προεπιλογή Ιδιωτική',
      (tester) async {
        await pumpSection(tester);

        expect(find.text('Τύπος σημείωσης'), findsWidgets);
        expect(_dropdownByLabel('Τύπος σημείωσης'), findsOneWidget);
        expect(
          find.descendant(
            of: _dropdownByLabel('Τύπος σημείωσης'),
            matching: find.text('Ιδιωτική'),
          ),
          findsOneWidget,
        );

        await tester.tap(_dropdownByLabel('Τύπος σημείωσης'));
        await pumpUntilSettled(tester);
        expect(find.text('Δημόσια'), findsWidgets);
      },
    );

    testWidgets(
      'αποδίδονται πεδία Προτεραιότητα/Τύπος αιτήματος/Ομάδα με τις σωστές τιμές Lansweeper',
      (tester) async {
        await pumpSection(tester);

        expect(find.text('Προτεραιότητες (τιμές με κόμμα)'), findsOneWidget);
        expect(find.text('Τύποι αιτήματος (τιμές με κόμμα)'), findsOneWidget);
        expect(find.text('Ομάδες (τιμές με κόμμα)'), findsOneWidget);

        expect(_dropdownByLabel('Προεπιλογή προτεραιότητας'), findsOneWidget);
        expect(
          find.descendant(
            of: _dropdownByLabel('Προεπιλογή προτεραιότητας'),
            matching: find.text('Low'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: _dropdownByLabel('Προεπιλογή τύπου αιτήματος'),
            matching: find.text('IT Support'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: _dropdownByLabel('Προεπιλογή ομάδας'),
            matching: find.text('IT Support'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'αλλαγή προεπιλογής προτεραιότητας κάνει persist μέσω provider',
      (tester) async {
        final container = await pumpSection(tester);

        await tester.ensureVisible(
          _dropdownByLabel('Προεπιλογή προτεραιότητας'),
        );
        await pumpUntilSettled(tester);
        await tester.tap(_dropdownByLabel('Προεπιλογή προτεραιότητας'));
        await pumpUntilSettled(tester);
        await tester.tap(find.text('High').last);
        await pumpUntilSettled(tester);

        // Το persist είναι async — δίνουμε χρόνο στο DB.
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await pumpUntilSettled(tester);

        expect(
          container.read(lansweeperTicketSubmitConfigProvider).priority,
          'High',
        );

        final raw = await tester.runAsync(() async {
          final db = await DatabaseHelper.instance.database;
          return SettingsRepository(
            db,
          ).getSetting(kLansweeperTicketSubmitConfigSettingKey);
        });
        expect(raw, isNotNull);
        final decoded = LansweeperTicketSubmitConfig.decodeFromStorage(raw);
        expect(decoded.priority, 'High');
      },
    );

    testWidgets(
      'πληκτρολόγηση τιμών με κόμμα ενημερώνει τη λίστα προτεραιοτήτων μέσω provider',
      (tester) async {
        final container = await pumpSection(tester);

        final valuesField = find.widgetWithText(
          TextFormField,
          'Προτεραιότητες (τιμές με κόμμα)',
        );
        expect(valuesField, findsOneWidget);

        await tester.ensureVisible(valuesField);
        await pumpUntilSettled(tester);
        await tester.enterText(valuesField, 'Low, Medium, High, Urgent');
        await pumpUntilSettled(tester);
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await pumpUntilSettled(tester);

        expect(container.read(lansweeperTicketSubmitConfigProvider).priorities, [
          'Low',
          'Medium',
          'High',
          'Urgent',
        ]);
      },
    );

    testWidgets(
      'προσωρινό κόμμα στο τέλος δεν ξαναγράφει το κείμενο του χρήστη κατά την πληκτρολόγηση',
      (tester) async {
        final container = await pumpSection(tester);

        final valuesField = find.widgetWithText(
          TextFormField,
          'Προτεραιότητες (τιμές με κόμμα)',
        );
        await tester.ensureVisible(valuesField);
        await pumpUntilSettled(tester);
        await tester.enterText(valuesField, 'Low, Medium,');
        await pumpUntilSettled(tester);
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await pumpUntilSettled(tester);

        expect(container.read(lansweeperTicketSubmitConfigProvider).priorities, [
          'Low',
          'Medium',
        ]);

        final editable = tester.widget<EditableText>(
          find.descendant(of: valuesField, matching: find.byType(EditableText)),
        );
        expect(editable.controller.text, 'Low, Medium,');
      },
    );

    testWidgets(
      'αποδίδεται ο διακόπτης «Προσθήκη χρόνου εργασίας στη σημείωση» και η εναλλαγή του κάνει persist μέσω provider',
      (tester) async {
        final container = await pumpSection(tester);

        final toggle = find.widgetWithText(
          SwitchListTile,
          'Προσθήκη χρόνου εργασίας στη σημείωση',
        );
        expect(toggle, findsOneWidget);

        final switchTile = tester.widget<SwitchListTile>(toggle);
        expect(switchTile.value, isTrue);

        await tester.ensureVisible(toggle);
        await pumpUntilSettled(tester);
        await tester.tap(toggle);
        await pumpUntilSettled(tester);
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await pumpUntilSettled(tester);

        expect(
          container.read(lansweeperTicketSubmitConfigProvider).includeNoteTime,
          isFalse,
        );

        final raw = await tester.runAsync(() async {
          final db = await DatabaseHelper.instance.database;
          return SettingsRepository(
            db,
          ).getSetting(kLansweeperTicketSubmitConfigSettingKey);
        });
        expect(raw, isNotNull);
        final decoded = LansweeperTicketSubmitConfig.decodeFromStorage(raw);
        expect(decoded.includeNoteTime, isFalse);
      },
    );
  });
}
