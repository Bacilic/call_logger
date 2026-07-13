import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/providers/spell_check_provider.dart';
import 'package:call_logger/core/services/spell_check_service.dart';
import 'package:call_logger/features/settings/widgets/remote_tool_form/remote_tool_arguments_editor.dart';
import 'package:call_logger/features/settings/widgets/remote_tool_form/remote_tool_form_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _kWarningFileTarget =
    'Το αρχείο ορίζει τον στόχο — τα ορίσματα με {TARGET} θα αγνοηθούν κατά την εκτέλεση.';
const _kWarningDuplicates =
    'Υπάρχουν διπλότυπα ορίσματα με την ίδια τιμή.';
const _kWarningRdpTargetSyntax =
    'Για RDP ο στόχος γράφεται /v:{TARGET} — κολλητά, χωρίς κενό. Σκέτο {TARGET} ή "/v: {TARGET}" ερμηνεύεται από το mstsc ως αρχείο σύνδεσης.';

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

    testWidgets(
      'banner {TARGET}+{FILE}: εμφανίζεται και κρύβεται όταν απενεργοποιηθεί το {TARGET}',
      (tester) async {
        await pumpEditor(tester);

        await tester.tap(find.text('{FILE}'));
        await settleEditor(tester);
        await tester.tap(find.text('Προσθήκη ορίσματος'));
        await settleEditor(tester);
        controller.argRows.last.valueC.text = '{TARGET}';
        controller.refresh();
        await settleEditor(tester);

        expect(
          find.textContaining(
            'Το αρχείο ορίζει τον στόχο — τα ορίσματα με {TARGET} θα αγνοηθούν κατά την εκτέλεση.',
          ),
          findsOneWidget,
        );

        await tester.tap(find.byType(Checkbox).last);
        await settleEditor(tester);

        expect(
          find.textContaining(
            'Το αρχείο ορίζει τον στόχο — τα ορίσματα με {TARGET} θα αγνοηθούν κατά την εκτέλεση.',
          ),
          findsNothing,
        );
        await finishTest(tester);
      },
    );
  });

  group('RemoteToolArgumentsEditor — ζωντανές προειδοποιήσεις banner', () {
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

    Future<void> setRoleAndArgs(
      WidgetTester tester,
      ToolRole role,
      List<String> values, {
      List<bool>? activeFlags,
    }) async {
      controller.role = role;
      while (controller.argRows.isNotEmpty) {
        controller.removeArg(0);
      }
      for (var i = 0; i < values.length; i++) {
        controller.addArg();
        controller.argRows[i].valueC.text = values[i];
        if (activeFlags != null && i < activeFlags.length) {
          controller.setArgActive(i, activeFlags[i]);
        }
      }
      controller.refresh();
      await settleEditor(tester);
    }

    testWidgets('rdp: σκέτο {TARGET} → προειδοποίηση /v:', (tester) async {
      await pumpEditor(tester);
      await setRoleAndArgs(tester, ToolRole.rdp, ['{TARGET}']);

      expect(find.textContaining(_kWarningRdpTargetSyntax), findsOneWidget);
      await finishTest(tester);
    });

    testWidgets('rdp: /v: {TARGET} με κενό → προειδοποίηση /v:', (tester) async {
      await pumpEditor(tester);
      await setRoleAndArgs(tester, ToolRole.rdp, ['/v: {TARGET}']);

      expect(find.textContaining(_kWarningRdpTargetSyntax), findsOneWidget);
      await finishTest(tester);
    });

    testWidgets('rdp: /v:{TARGET} → χωρίς προειδοποίηση /v:', (tester) async {
      await pumpEditor(tester);
      await setRoleAndArgs(tester, ToolRole.rdp, ['/v:{TARGET}']);

      expect(find.textContaining(_kWarningRdpTargetSyntax), findsNothing);
      await finishTest(tester);
    });

    testWidgets('vnc: -host={TARGET} → χωρίς προειδοποίηση /v:', (tester) async {
      await pumpEditor(tester);
      await setRoleAndArgs(tester, ToolRole.vnc, ['-host={TARGET}']);

      expect(find.textContaining(_kWarningRdpTargetSyntax), findsNothing);
      await finishTest(tester);
    });

    testWidgets(
      'ενεργά {FILE} + {TARGET} → προειδοποίηση σύγκρουσης και εξαφάνιση με απενεργοποίηση',
      (tester) async {
        await pumpEditor(tester);
        await setRoleAndArgs(
          tester,
          ToolRole.rdp,
          ['{FILE}', '{TARGET}'],
        );

        expect(find.textContaining(_kWarningFileTarget), findsOneWidget);

        await tester.tap(find.byType(Checkbox).last);
        await settleEditor(tester);

        expect(find.textContaining(_kWarningFileTarget), findsNothing);
        await finishTest(tester);
      },
    );

    testWidgets('δύο ίδια ενεργά ορίσματα → προειδοποίηση διπλοτύπου', (tester) async {
      await pumpEditor(tester);
      await setRoleAndArgs(
        tester,
        ToolRole.rdp,
        ['-password=secret', '-password=secret'],
      );

      expect(find.textContaining(_kWarningDuplicates), findsOneWidget);
      await finishTest(tester);
    });
  });
}
