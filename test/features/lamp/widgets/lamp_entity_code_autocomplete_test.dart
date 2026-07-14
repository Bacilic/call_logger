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

    Future<void> pumpField(
      WidgetTester tester, {
      bool autofocus = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LampEntityCodeAutocomplete(
              controller: controller,
              searchSuggestions: search,
              onCodeSelected: (code) => selectedCode = code,
              autofocus: autofocus,
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
      'autofocus: το πεδίο εστιάζεται μόλις ανοίξει, χωρίς κλικ',
      (tester) async {
        await pumpField(tester, autofocus: true);
        await tester.pump();

        final editable = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        expect(
          editable.widget.focusNode.hasPrimaryFocus,
          isTrue,
          reason: 'Με autofocus, ο χρήστης πρέπει να μπορεί να πληκτρολογήσει '
              'αμέσως χωρίς κλικ μέσα στο πεδίο.',
        );

        // Χωρίς autofocus, το πεδίο ΔΕΝ πρέπει να αρπάζει την εστίαση μόνο του.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'ΠΑΛΙΝΔΡΟΜΗΣΗ: το πεδίο ΔΕΝ ξαναχτίζεται όταν εμφανίζεται/κρύβεται η λίστα',
      (tester) async {
        await pumpField(tester);

        // Ταυτότητα του πεδίου ΠΡΙΝ εμφανιστεί λίστα (χωρίς overlay).
        final elementBefore = tester.element(find.byType(EditableText));

        // Πληκτρολόγηση → εμφανίζεται η λίστα προτάσεων (overlay).
        await tester.enterText(find.byType(TextField), 'πατσα');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));

        expect(find.byType(ListView), findsOneWidget);
        final elementWithOverlay = tester.element(find.byType(EditableText));
        expect(
          identical(elementBefore, elementWithOverlay),
          isTrue,
          reason: 'Η εμφάνιση της λίστας δεν πρέπει να ξαναχτίζει το πεδίο '
              '(αλλιώς χάνεται η εστίαση/ο κέρσορας).',
        );

        // Άδειασμα του πεδίου (σαν backspace στο τελευταίο ψηφίο) → η λίστα
        // κρύβεται. Το πεδίο πρέπει να παραμείνει το ΙΔΙΟ element.
        controller.clear();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));

        expect(find.byType(ListView), findsNothing);
        final elementAfter = tester.element(find.byType(EditableText));
        expect(
          identical(elementBefore, elementAfter),
          isTrue,
          reason: 'Το κρύψιμο της λίστας δεν πρέπει να ξαναχτίζει το πεδίο.',
        );

        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

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
