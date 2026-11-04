// Το πλαίσιο της πρίζας: τίποτα δεν φεύγει πριν από το ✓, και το γύρισμα από
// δύο θύρες σε μία και πίσω δεν χάνει ό,τι γράφτηκε.
//
//   flutter test test/features/directory/building_map/plan/widgets/floor_plan_outlet_editor_test.dart

import 'package:call_logger/features/directory/building_map/plan/floor_plan_ports.dart';
import 'package:call_logger/features/directory/building_map/plan/widgets/floor_plan_outlet_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<List<FloorPlanOutletPortDraft>> saved;
  late int cancelled;

  Future<void> pump(
    WidgetTester tester, {
    List<FloorPlanOutletPortDraft> initial = const [
      FloorPlanOutletPortDraft(number: 1),
      FloorPlanOutletPortDraft(number: 2),
    ],
  }) async {
    saved = [];
    cancelled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FloorPlanOutletEditor(
            title: 'Πρίζα',
            initial: initial,
            onCommit: saved.add,
            onCancel: () => cancelled++,
            onPickPatchPort: (_, _) async => (id: 50, name: 'RC6.F17'),
            onPickConnection: (_) async => null,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder written(int index) => find.byType(TextField).at(index);

  testWidgets('✓ δίνει ό,τι γράφτηκε και τη θύρα που διαλέχτηκε', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(written(0), 'Κάμερα 7');
    await tester.tap(find.text(kFloorPlanOutletUnlinked).first);
    await tester.pump();
    expect(find.text('RC6.F17'), findsOneWidget);
    expect(saved, isEmpty);

    await tester.tap(find.byTooltip('Αποθήκευση (Enter)'));

    final ports = saved.single;
    expect(ports, hasLength(2));
    expect(ports.first.writtenName, 'Κάμερα 7');
    expect(ports.first.patchPortId, 50);
    expect(ports.last.patchPortId, isNull);
  });

  testWidgets('Esc ακυρώνει χωρίς να δώσει τίποτα', (tester) async {
    await pump(tester);

    await tester.enterText(written(0), 'Κάμερα 7');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);

    expect(cancelled, 1);
    expect(saved, isEmpty);
  });

  testWidgets('από 2 σε 1 θύρα και πίσω: ό,τι γράφτηκε μένει', (tester) async {
    await pump(tester);

    await tester.enterText(written(1), 'Κάμερα 7');
    await tester.tap(find.text('1 θύρα'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('2 θύρες'));
    await tester.pump();
    await tester.tap(find.byTooltip('Αποθήκευση (Enter)'));

    expect(saved.single.last.writtenName, 'Κάμερα 7');
  });

  testWidgets('με 1 θύρα αποθηκεύεται μόνο η μία', (tester) async {
    await pump(tester);

    await tester.tap(find.text('1 θύρα'));
    await tester.pump();
    await tester.tap(find.byTooltip('Αποθήκευση (Enter)'));

    expect(saved.single, hasLength(1));
  });
}
