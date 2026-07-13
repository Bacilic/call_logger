// Unit + widget tests: πλούσια σύνοψη audit με έγχρωμα δείγματα χρώματος.
//
//   flutter test test/features/history/audit_summary_rich_text_test.dart

import 'package:call_logger/core/widgets/audit_summary_rich_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseAuditSummarySegments', () {
    test('«Μπλε #1976D2» — κείμενο και χρώμα', () {
      final segments = parseAuditSummarySegments('Μπλε #1976D2');

      expect(segments, hasLength(2));
      expect(segments[0].kind, AuditSummarySegmentKind.text);
      expect(segments[0].value, 'Μπλε ');
      expect(segments[1].kind, AuditSummarySegmentKind.color);
      expect(segments[1].value, '#1976D2');
    });

    test('«από #61BC65 σε #1935BD» — εναλλαγή κειμένου και χρωμάτων', () {
      final segments = parseAuditSummarySegments('από #61BC65 σε #1935BD');

      expect(segments, hasLength(4));
      expect(segments[0].value, 'από ');
      expect(segments[1].value, '#61BC65');
      expect(segments[2].value, ' σε ');
      expect(segments[3].value, '#1935BD');
      expect(
        segments.where((s) => s.kind == AuditSummarySegmentKind.color),
        hasLength(2),
      );
    });

    test('συμβολοσειρά χωρίς hex — ένα τμήμα κειμένου', () {
      final segments = parseAuditSummarySegments('3 αλλαγές: χρώμα, όροφος');

      expect(segments, hasLength(1));
      expect(segments.single.kind, AuditSummarySegmentKind.text);
      expect(segments.single.value, '3 αλλαγές: χρώμα, όροφος');
    });
  });

  group('AuditSummaryRichText', () {
    Future<void> pumpRichText(WidgetTester tester, String text) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuditSummaryRichText(
              text: text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
    }

    int colorSwatchCount(WidgetTester tester) {
      return tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(AuditSummaryRichText),
              matching: find.byWidgetPredicate((w) {
                if (w is! Container) return false;
                final decoration = w.decoration;
                if (decoration is! BoxDecoration) return false;
                return decoration.color != null &&
                    decoration.borderRadius is BorderRadius;
              }),
            ),
          )
          .length;
    }

    testWidgets('δύο hex — δύο έγχρωμα κουτάκια και κείμενα (#HEX)', (
      tester,
    ) async {
      await pumpRichText(tester, 'από #61BC65 σε #1935BD');

      expect(colorSwatchCount(tester), 2);
      expect(find.textContaining('(#61BC65)'), findsOneWidget);
      expect(find.textContaining('(#1935BD)'), findsOneWidget);
    });
  });
}
