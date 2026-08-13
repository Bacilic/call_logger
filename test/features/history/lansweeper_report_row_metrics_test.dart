// Το ύψος της κάρτας ακολουθεί το περιεχόμενό της. Δεν είναι αισθητική
// λεπτομέρεια: το ίδιο νούμερο δίνεται και στον κύλινδρο της λίστας, οπότε μια
// λάθος μέτρηση εμφανίζεται είτε ως κομμένο κείμενο είτε ως μπάρα κύλισης που
// μεταπηδά.
//
//   flutter test test/features/history/lansweeper_report_row_metrics_test.dart

import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_report_row_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const style = TextStyle(fontSize: 12, height: 1.25);
  const width = 240.0;
  const scaler = TextScaler.noScaling;

  double body(String issue, {String solution = ''}) {
    return LansweeperReportRowMetrics.bodyHeight(
      issue: issue,
      solution: solution,
      style: style,
      maxWidth: width,
      textScaler: scaler,
    );
  }

  group('ύψος κειμένου', () {
    test('χωρίς κείμενο δεν δεσμεύεται χώρος', () {
      expect(body(''), 0);
      expect(body('   '), 0);
    });

    test('μία γραμμή πιάνει λιγότερο από δύο', () {
      final one = body('δεν εκτυπώνει');
      final two = body('δεν εκτυπώνει\nεπανεκκίνηση εκτυπωτή');

      expect(one, greaterThan(0));
      expect(two, greaterThan(one));
    });

    // Ο λόγος που ξεκίνησε η αλλαγή: κάρτα με μία γραμμή δέσμευε χώρο τριών.
    test('το μακρύ κείμενο σταματά στο όριο γραμμών', () {
      final capped = body('γραμμή α\nγραμμή β\nγραμμή γ\nγραμμή δ\nγραμμή ε');
      final two = body('γραμμή α\nγραμμή β');

      expect(capped, two);
    });

    test('η λύση προσθέτει τον δικό της χώρο', () {
      final withoutSolution = body('δεν εκτυπώνει');
      final withSolution = body(
        'δεν εκτυπώνει',
        solution: 'επανεκκίνηση εκτυπωτή',
      );

      expect(withSolution, greaterThan(withoutSolution));
    });

    test('κενή λύση δεν δεσμεύει γραμμή', () {
      expect(body('δεν εκτυπώνει', solution: '  '), body('δεν εκτυπώνει'));
    });

    test('μηδενικό πλάτος δεν ρίχνει τη μέτρηση', () {
      expect(
        LansweeperReportRowMetrics.bodyHeight(
          issue: 'κάτι',
          solution: '',
          style: style,
          maxWidth: 0,
          textScaler: scaler,
        ),
        0,
      );
    });
  });

  group('ύψος κάρτας', () {
    test('ακολουθεί το ύψος του κειμένου', () {
      final short = LansweeperReportRowMetrics.rowExtent(
        bodyHeight: 15,
        isLastInGroup: false,
      );
      final tall = LansweeperReportRowMetrics.rowExtent(
        bodyHeight: 45,
        isLastInGroup: false,
      );

      expect(tall - short, 30);
    });

    test('η τελευταία κάρτα της ομάδας κρατά το κάτω περιθώριο', () {
      final middle = LansweeperReportRowMetrics.rowExtent(
        bodyHeight: 15,
        isLastInGroup: false,
      );
      final last = LansweeperReportRowMetrics.rowExtent(
        bodyHeight: 15,
        isLastInGroup: true,
      );

      expect(
        last - middle,
        LansweeperReportRowMetrics.groupBottomHeight,
      );
    });

    // Το παλιό σταθερό ύψος ήταν 90 για κάθε κάρτα, ανεξαρτήτως περιεχομένου.
    test('μια κλήση με μία γραμμή είναι πιο κοντή από το παλιό σταθερό', () {
      final oneLine = LansweeperReportRowMetrics.rowExtent(
        bodyHeight: body('δεν εκτυπώνει'),
        isLastInGroup: false,
      );

      expect(oneLine, lessThan(90));
    });
  });
}
