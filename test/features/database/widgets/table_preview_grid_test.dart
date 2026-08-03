// Συμπεριφορά εικονικοποιημένου πλέγματος προεπισκόπησης πίνακα.
//
//   flutter test test/features/database/widgets/table_preview_grid_test.dart

import 'package:call_logger/features/database/widgets/table_preview_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, dynamic>> _makeRows(int count) {
  return List.generate(count, (i) => {'id': i, 'word': 'τιμή $i'});
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SizedBox(width: 800, height: 600, child: child)),
  );
}

void main() {
  testWidgets('χτίζονται ΜΟΝΟ οι ορατές γραμμές, όχι και οι 500', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        TablePreviewGrid(
          tableKey: 'full_dictionary',
          columns: const ['id', 'word'],
          rows: _makeRows(500),
          zoom: 1.0,
        ),
      ),
    );

    expect(find.text('τιμή 0'), findsOneWidget);
    // Γραμμή εκτός viewport: με εικονικοποίηση δεν έχει χτιστεί καθόλου.
    expect(find.text('τιμή 400'), findsNothing);
  });

  testWidgets('η ένδειξη δηλώνει «Χ από Ψ» όταν εμφανίζεται υποσύνολο', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        TablePreviewGrid(
          tableKey: 'audit_log',
          columns: const ['id', 'word'],
          rows: _makeRows(500),
          zoom: 1.0,
          totalRowCount: 1114,
          hasMoreRows: true,
        ),
      ),
    );

    expect(
      find.textContaining('Εμφανίζονται 500 από 1.114 εγγραφές'),
      findsOneWidget,
    );
  });

  testWidgets('όταν έχουν φορτωθεί όλες, η ένδειξη το δηλώνει', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TablePreviewGrid(
          tableKey: 'calls',
          columns: const ['id', 'word'],
          rows: _makeRows(229),
          zoom: 1.0,
          totalRowCount: 229,
        ),
      ),
    );

    expect(find.textContaining('229 εγγραφές (όλες)'), findsOneWidget);
  });

  testWidgets('η κύλιση κοντά στο τέλος πυροδοτεί φόρτωση επόμενης σελίδας', (
    tester,
  ) async {
    var loadMoreCalls = 0;
    await tester.pumpWidget(
      _wrap(
        TablePreviewGrid(
          tableKey: 'audit_log',
          columns: const ['id', 'word'],
          rows: _makeRows(500),
          zoom: 1.0,
          totalRowCount: 1114,
          hasMoreRows: true,
          onLoadMoreRows: () => loadMoreCalls++,
        ),
      ),
    );

    expect(loadMoreCalls, 0);

    await tester.drag(find.byType(ListView), const Offset(0, -25000));
    await tester.pump();

    expect(loadMoreCalls, greaterThan(0));
  });

  testWidgets('δεν ρίχνει layout exception σε στενό πλάτος με φαρδιές στήλες', (
    tester,
  ) async {
    final columns = List<String>.generate(12, (i) => 'column_$i');
    final rows = List<Map<String, dynamic>>.generate(
      40,
      (r) => {for (final c in columns) c: 'τιμή $r $c ${'x' * 24}'},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 160,
            height: 240,
            child: TablePreviewGrid(
              tableKey: 'wide',
              columns: columns,
              rows: rows,
              zoom: 1.0,
              totalRowCount: 40,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('χωρίς επόμενες σελίδες η κύλιση ΔΕΝ πυροδοτεί φόρτωση', (
    tester,
  ) async {
    var loadMoreCalls = 0;
    await tester.pumpWidget(
      _wrap(
        TablePreviewGrid(
          tableKey: 'calls',
          columns: const ['id', 'word'],
          rows: _makeRows(229),
          zoom: 1.0,
          totalRowCount: 229,
          onLoadMoreRows: () => loadMoreCalls++,
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -25000));
    await tester.pump();

    expect(loadMoreCalls, 0);
  });
}
