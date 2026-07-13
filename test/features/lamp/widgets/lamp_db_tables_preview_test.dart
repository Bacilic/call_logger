import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/lamp/widgets/lamp_db_tables_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TablePreviewResult _widePreview() {
  final columns = List<String>.generate(12, (i) => 'column_$i');
  final rows = List<Map<String, Object?>>.generate(
    4,
    (rowIndex) => <String, Object?>{
      for (final column in columns)
        column: 'τιμή $rowIndex $column ${'x' * 24}',
    },
  );
  return TablePreviewResult(columns: columns, rows: rows);
}

ScrollController _horizontalController(WidgetTester tester) {
  final horizontalScroll = tester.widget<SingleChildScrollView>(
    find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    ),
  );
  final controller = horizontalScroll.controller;
  expect(controller, isNotNull);
  return controller!;
}

void main() {
  group('LampSimpleDataPreview', () {
    testWidgets('εμφανίζει δύο Scrollbar και λειτουργεί η οριζόντια κύλιση',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 320,
              child: LampSimpleDataPreview(result: _widePreview()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Scrollbar), findsNWidgets(2));

      final controller = _horizontalController(tester);
      expect(controller.offset, 0);

      await tester.drag(
        find.byType(LampSimpleDataPreview),
        const Offset(-240, 0),
      );
      await tester.pumpAndSettle();

      expect(controller.offset, greaterThan(0));
    });

    testWidgets('δεν ρίχνει layout exception σε στενό πλάτος', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 160,
              height: 240,
              child: LampSimpleDataPreview(result: _widePreview()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollbar), findsNWidgets(2));
    });
  });
}
