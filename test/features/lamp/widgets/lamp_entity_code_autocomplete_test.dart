import 'package:call_logger/core/database/old_database/lamp_issue_resolution_models.dart';
import 'package:call_logger/features/lamp/widgets/lamp_entity_code_autocomplete.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LampEntityCodeAutocomplete', () {
    late TextEditingController controller;
    int? selectedCode;

    const suggestions = <LampEntityCodeSuggestion>[
      LampEntityCodeSuggestion(code: 50, label: 'Άννα Πατσαρίκα'),
      LampEntityCodeSuggestion(code: 51, label: 'Μαρία Πατσαρίκα'),
      LampEntityCodeSuggestion(code: 8842, label: 'Εξοπλισμός δοκιμής'),
    ];

    Future<List<LampEntityCodeSuggestion>> search(String query) async {
      return filterEntityCodeSuggestions(suggestions, query);
    }

    setUp(() {
      controller = TextEditingController();
      selectedCode = null;
    });

    tearDown(() {
      controller.dispose();
    });

    Future<void> pumpField(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LampEntityCodeAutocomplete(
              controller: controller,
              searchSuggestions: search,
              onCodeSelected: (code) => selectedCode = code,
            ),
          ),
        ),
      );
    }

    testWidgets('εμφανίζει προτάσεις καθώς πληκτρολογείται όνομα ή κωδικός', (
      tester,
    ) async {
      await pumpField(tester);

      await tester.enterText(find.byType(TextField), 'πατσα');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('Άννα Πατσαρίκα (50)'), findsOneWidget);
      expect(find.text('Μαρία Πατσαρίκα (51)'), findsOneWidget);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets(
      'ΣΕΝΑΡΙΟ WINDOWS: κλικ ποντικιού σε πρόταση συμπληρώνει τον κωδικό',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          await pumpField(tester);

          await tester.enterText(find.byType(TextField), 'αννα');
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));

          final target = tester.getCenter(
            find.descendant(
              of: find.byType(ListView),
              matching: find.text('Άννα Πατσαρίκα (50)'),
            ),
          );
          final gesture = await tester.startGesture(
            target,
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump(const Duration(milliseconds: 80));
          await gesture.up();
          await tester.pump();

          expect(controller.text, '50');
          expect(selectedCode, 50);
        } finally {
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'ΣΕΝΑΡΙΟ WINDOWS: βελάκι κάτω + Enter επιλέγει πρόταση και κρατά εστίαση',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          await pumpField(tester);

          await tester.enterText(find.byType(TextField), 'πατσα');
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));

          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();

          expect(controller.text, '51');
          expect(selectedCode, 51);

          final editable = tester.state<EditableTextState>(
            find.byType(EditableText),
          );
          expect(editable.widget.focusNode.hasPrimaryFocus, isTrue);
        } finally {
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('numpadEnter επιλέγει την ενεργή πρόταση', (tester) async {
      await pumpField(tester);

      await tester.enterText(find.byType(TextField), '8842');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pump();

      expect(controller.text, '8842');
      expect(selectedCode, 8842);
    });
  });

  group('filterEntityCodeSuggestions', () {
    test('ταιριάζει χωρίς τόνους και με κωδικό', () {
      const source = <LampEntityCodeSuggestion>[
        LampEntityCodeSuggestion(code: 12, label: 'Βασικό Γραφείο'),
      ];

      expect(
        filterEntityCodeSuggestions(source, 'βασικο').single.code,
        12,
      );
      expect(
        filterEntityCodeSuggestions(source, '12').single.code,
        12,
      );
    });
  });
}
