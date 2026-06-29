// Widget/controller test: πεδίο προτροπής Gemini — ενιαίος μηχανισμός απόδοσης.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/history/gemini_prompt_template_field_test.dart

import 'package:call_logger/core/services/gemini_prompt_template_controller.dart';
import 'package:call_logger/features/history/widgets/lansweeper/gemini_prompt_template_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _kPlaceholderGreen = Color(0xFF16A34A);
const _kBlockBlue = Color(0xFF2563EB);

/// Πολυγραμμικό template που ξεπερνά το ορατό ύψος (maxLines: 10) — regression scroll/ύψους.
String _multiLineOverflowTemplate() {
  return '''
Δημιούργησε τίτλο και περιγραφή για ticket helpdesk.

Υπάλληλος: {Υπάλληλος}.
{@Εξοπλισμός}Εξοπλισμός: {Εξοπλισμός}. {@/Εξοπλισμός}
Τμήμα: {Τμήμα}. Κατηγορία: {Κατηγορία}.
Πρόβλημα: {Πρόβλημα}. Σημειώσεις: {Σημειώσεις}.

1η γραμμή υπερχείλισης
2η γραμμή υπερχείλισης
3η γραμμή υπερχείλισης
4η γραμμή υπερχείλισης
5η γραμμή υπερχείλισης

Απάντησε σε JSON: {"title":"...","description":"...","solution":"..."}''';
}

Color? _firstMatchingColor(TextSpan span, String fragment) {
  if (span.text != null && span.text!.contains(fragment)) {
    return span.style?.color;
  }
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is! TextSpan) continue;
    final color = _firstMatchingColor(child, fragment);
    if (color != null) return color;
  }
  return null;
}

void main() {
  group('GeminiPromptTemplateTextEditingController', () {
    testWidgets(
      'buildTextSpan χρωματίζει placeholders και blocks',
      (tester) async {
        late TextSpan span;
        const baseStyle = TextStyle(fontSize: 14, height: 1.45);

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                final controller = GeminiPromptTemplateTextEditingController(
                  text: 'Υπάλληλος: {Υπάλληλος}. {@Τμήμα}Τμήμα: {Τμήμα}. {@/Τμήμα}',
                );
                span = controller.buildTextSpan(
                  context: context,
                  style: baseStyle,
                  withComposing: false,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(
          _firstMatchingColor(span, '{Υπάλληλος}'),
          _kPlaceholderGreen,
          reason: 'Το γνωστό placeholder πρέπει να είναι πράσινο',
        );
        expect(
          _firstMatchingColor(span, '{@Τμήμα}'),
          _kBlockBlue,
          reason: 'Το άνοιγμα block πρέπει να είναι μπλε',
        );
        expect(
          _firstMatchingColor(span, '{@/Τμήμα}'),
          _kBlockBlue,
          reason: 'Το κλείσιμο block πρέπει να είναι μπλε',
        );
      },
    );
  });

  group('GeminiPromptTemplateField (widget)', () {
    testWidgets(
      'δεν χρησιμοποιεί διπλό Stack/Transform για highlight',
      (tester) async {
        final controller = GeminiPromptTemplateTextEditingController(
          text: _multiLineOverflowTemplate(),
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GeminiPromptTemplateField(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byType(TextField),
          findsOneWidget,
          reason: 'Ένα μόνο TextField για εισαγωγή και απόδοση',
        );
        expect(
          find.text('JSON απάντησης'),
          findsOneWidget,
          reason: 'Κουμπί εισαγωγής blueprint JSON',
        );
        expect(
          find.byTooltip('Πώς λειτουργεί η προτροπή'),
          findsOneWidget,
          reason: 'Εικονίδιο βοήθειας για την προτροπή',
        );

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(
          textField.style?.color,
          isNot(Colors.transparent),
          reason:
              'Το κείμενο δεν πρέπει να είναι διαφανές — ο controller κάνει highlight',
        );
      },
    );

    testWidgets(
      'πολλές γραμμές: scroll χωρίς ξεχωριστό highlight layer',
      (tester) async {
        final controller = GeminiPromptTemplateTextEditingController(
          text: _multiLineOverflowTemplate(),
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 480,
                  child: GeminiPromptTemplateField(
                    controller: controller,
                    minLines: 5,
                    maxLines: 10,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('5η γραμμή υπερχείλισης'),
          findsOneWidget,
          reason: 'Η τελευταία γραμμή εμφανίζεται στο ίδιο πεδίο',
        );
        expect(
          find.textContaining('{Υπάλληλος}'),
          findsOneWidget,
          reason: 'Τα placeholders εμφανίζονται στο ίδιο πεδίο (buildTextSpan)',
        );
      },
    );
  });
}
