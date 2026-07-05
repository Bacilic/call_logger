import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/providers/spell_check_provider.dart';
import 'package:call_logger/core/services/spell_check_service.dart';
import 'package:call_logger/features/settings/widgets/remote_tool_form/remote_tool_arguments_editor.dart';
import 'package:call_logger/features/settings/widgets/remote_tool_form/remote_tool_form_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteToolArgumentsEditor — lock πριν εξαγωγή', () {
    late RemoteToolFormController controller;

    setUp(() {
      controller = RemoteToolFormController();
    });

    Future<void> settleEditor(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    Future<void> finishTest(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await settleEditor(tester);
      controller.dispose();
    }

    Future<void> pumpEditor(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            enableSpellCheckProvider.overrideWith((ref) async => false),
            spellCheckServiceProvider.overrideWith((ref) async {
              final svc = LexiconSpellCheckService();
              await svc.init(lexiconVariants: {});
              return svc;
            }),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RemoteToolArgumentsEditor(controller: controller),
              ),
            ),
          ),
        ),
      );
      await settleEditor(tester);
    }

    testWidgets('«Προσθήκη ορίσματος» προσθέτει μία γραμμή', (tester) async {
      await pumpEditor(tester);

      expect(controller.argRows, isEmpty);
      expect(find.text('Κανένα ορίσμα.'), findsOneWidget);

      await tester.tap(find.text('Προσθήκη ορίσματος'));
      await settleEditor(tester);

      expect(controller.argRows, hasLength(1));
      expect(find.text('Κανένα ορίσμα.'), findsNothing);
      expect(find.widgetWithText(TextField, ''), findsWidgets);
      expect(find.text('Όρισμα (τιμή)'), findsOneWidget);
      await finishTest(tester);
    });

    testWidgets('placeholder σε κενή λίστα δημιουργεί γραμμή με token', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('{TARGET}'));
      await settleEditor(tester);

      expect(controller.argRows, hasLength(1));
      expect(controller.argRows.single.valueC.text, '{TARGET}');
      await finishTest(tester);
    });

    testWidgets('checkbox εναλλάσσει active μέσω setArgActive', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Προσθήκη ορίσματος'));
      await settleEditor(tester);

      expect(controller.argRows.single.active, isTrue);

      await tester.tap(find.byType(Checkbox));
      await settleEditor(tester);

      expect(controller.argRows.single.active, isFalse);
      await finishTest(tester);
    });

    testWidgets('κουμπί διαγραφής αφαιρεί τη γραμμή', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Προσθήκη ορίσματος'));
      await settleEditor(tester);
      expect(controller.argRows, hasLength(1));

      await tester.tap(find.byIcon(Icons.delete_outline));
      await settleEditor(tester);

      expect(controller.argRows, isEmpty);
      expect(find.text('Κανένα ορίσμα.'), findsOneWidget);
      await finishTest(tester);
    });

    testWidgets('saving=true απενεργοποιεί προσθήκη και placeholders', (tester) async {
      await pumpEditor(tester);

      controller.saving = true;
      controller.refresh();
      await settleEditor(tester);

      final addBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Προσθήκη ορίσματος'),
      );
      expect(addBtn.onPressed, isNull);

      for (final ph in ['{TARGET}', '{EQUIPMENT_CODE}', '{FILE}']) {
        final phBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, ph),
        );
        expect(phBtn.onPressed, isNull);
      }
      await finishTest(tester);
    });
  });
}
