// Widget test: μηχανισμός trigger-based overlay εισαγωγής στο πεδίο προτροπής Gemini.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/history/ai_prompt_template_trigger_overlay_test.dart

import 'package:call_logger/core/services/ai_prompt_template_controller.dart';
import 'package:call_logger/features/history/widgets/lansweeper/ai_prompt_template_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AiPromptTemplateTextEditingController> _pumpField(
  WidgetTester tester, {
  String initialText = '',
}) async {
  final controller = AiPromptTemplateTextEditingController(
    text: initialText,
  );
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: AiPromptTemplateField(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  group('AiPromptTemplateField · trigger overlay', () {
    testWidgets('το πληκτρολόγημα { ενεργοποιεί το overlay προτάσεων',
        (tester) async {
      await _pumpField(tester);

      // Πριν την πληκτρολόγηση δεν υπάρχει overlay.
      expect(find.text('Block Υπάλληλος'), findsNothing);

      await tester.enterText(find.byType(TextField), 'Κείμενο {');
      await tester.pump();
      await tester.pump();

      // Με κενό query εμφανίζονται όλοι οι δεσμευτές θέσης στην κορυφή.
      expect(
        find.text('Υπάλληλος'),
        findsOneWidget,
        reason: 'Η λίστα προτάσεων ενεργοποιείται με το {',
      );
      expect(
        find.text('Εξοπλισμός'),
        findsOneWidget,
        reason: 'Εμφανίζονται πολλοί δεσμευτές θέσης στη λίστα',
      );
    });

    testWidgets('η λίστα περιλαμβάνει και blocks (φιλτραρισμένα)',
        (tester) async {
      await _pumpField(tester);

      await tester.enterText(find.byType(TextField), 'Κείμενο {Υπ');
      await tester.pump();
      await tester.pump();

      expect(find.text('Υπάλληλος'), findsOneWidget);
      expect(
        find.text('Block Υπάλληλος'),
        findsOneWidget,
        reason: 'Η λίστα προτάσεων εμφανίζει και τα αντίστοιχα blocks',
      );
    });

    testWidgets('φιλτράρισμα καθώς προστίθενται χαρακτήρες μετά το {',
        (tester) async {
      await _pumpField(tester);

      await tester.enterText(find.byType(TextField), 'Κείμενο {Τμ');
      await tester.pump();
      await tester.pump();

      expect(find.text('Τμήμα'), findsOneWidget);
      expect(find.text('Block Τμήμα'), findsOneWidget);
      expect(
        find.text('Υπάλληλος'),
        findsNothing,
        reason: 'Οι μη ταιριαστές προτάσεις αποκρύπτονται',
      );
      expect(find.text('Block Υπάλληλος'), findsNothing);
    });

    testWidgets('εισαγωγή μεμονωμένου δεσμευτή θέσης με Enter',
        (tester) async {
      final controller = await _pumpField(tester);

      await tester.enterText(find.byType(TextField), '{Τμ');
      await tester.pump();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();

      expect(controller.text, '{Τμήμα}');
      expect(
        find.text('Block Τμήμα'),
        findsNothing,
        reason: 'Μετά την εισαγωγή το overlay κλείνει',
      );
    });

    testWidgets('εισαγωγή block με κλικ τοποθετεί τον δρομέα ανάμεσα',
        (tester) async {
      final controller = await _pumpField(tester);

      await tester.enterText(find.byType(TextField), '{Τμ');
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Block Τμήμα'));
      await tester.pump();
      await tester.pump();

      expect(controller.text, '{@Τμήμα}{@/Τμήμα}');
      expect(
        controller.selection.baseOffset,
        '{@Τμήμα}'.length,
        reason: 'Ο δρομέας τοποθετείται ανάμεσα στο άνοιγμα και το κλείσιμο',
      );
    });

    testWidgets('εισαγωγή μεμονωμένου δεσμευτή θέσης με κλικ',
        (tester) async {
      final controller = await _pumpField(tester);

      await tester.enterText(find.byType(TextField), '{Τμ');
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Τμήμα'));
      await tester.pump();
      await tester.pump();

      expect(controller.text, '{Τμήμα}');
    });

    testWidgets('πλοήγηση με βέλη και επιβεβαίωση με Enter',
        (tester) async {
      final controller = await _pumpField(tester);

      await tester.enterText(find.byType(TextField), '{');
      await tester.pump();
      await tester.pump();

      // Index 0: Υπάλληλος, Index 1: Εξοπλισμός.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();

      expect(controller.text, '{Εξοπλισμός}');
    });

    testWidgets('Escape κλείνει το overlay χωρίς εισαγωγή', (tester) async {
      final controller = await _pumpField(tester);

      await tester.enterText(find.byType(TextField), '{Τμ');
      await tester.pump();
      await tester.pump();
      expect(find.text('Block Τμήμα'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Block Τμήμα'),
        findsNothing,
        reason: 'Το Escape κλείνει τη λίστα',
      );
      expect(
        controller.text,
        '{Τμ',
        reason: 'Το Escape δεν εισάγει token',
      );
    });

    testWidgets(
      'ο δρομέας μέσα σε υπάρχον κλειστό token δεν ενεργοποιεί το overlay',
      (tester) async {
        final controller = await _pumpField(tester, initialText: '{Υπάλληλος}');

        // Τοποθέτηση δρομέα μέσα στο ολοκληρωμένο token {Υπάλ|ληλος}.
        controller.selection = const TextSelection.collapsed(offset: 5);
        await tester.pump();
        await tester.pump();

        expect(
          find.text('Block Υπάλληλος'),
          findsNothing,
          reason: 'Δεν ξανανοίγει overlay μέσα σε υπάρχον token',
        );
      },
    );

    testWidgets('το κουμπί «JSON απάντησης» παραμένει ανεπηρέαστο',
        (tester) async {
      final controller = await _pumpField(tester);

      await tester.tap(find.text('JSON απάντησης'));
      await tester.pump();

      expect(
        controller.text,
        contains('"title"'),
        reason: 'Το blueprint JSON εισάγεται κανονικά',
      );
      expect(controller.text, contains('"description"'));
      expect(controller.text, contains('"solution"'));
    });
  });
}
