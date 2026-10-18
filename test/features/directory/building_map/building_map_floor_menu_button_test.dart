// Το μενού κατόψεων: χωρίς το δικαίωμα «Διαχείριση κατόψεων» μένει μόνο
// επιλογέας ορόφου.
//
//   flutter test test/features/directory/building_map/building_map_floor_menu_button_test.dart

import 'package:call_logger/core/models/building_map_floor.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/features/directory/building_map/widgets/building_map_floor_menu_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

BuildingMapFloor _floor({String? hash, bool previous = false}) =>
    BuildingMapFloor(
      id: 2,
      sortOrder: 0,
      label: '2ος',
      imagePath: '',
      rotationDegrees: 0,
      imageHash: hash,
      hasPreviousImage: previous,
    );

Future<void> _openMenu(WidgetTester tester, BuildingMapFloor floor) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: BuildingMapFloorsMenuButton(
            floors: [floor],
            onFloorsChanged: () {},
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byType(BuildingMapFloorsMenuButton));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(CurrentOperator.reset);

  testWidgets('απλός χρήστης: βλέπει τον όροφο, όχι προσθήκη, αλλαγή, '
      'επαναφορά, διαγραφή ή ανέβασμα', (tester) async {
    CurrentOperator.activate(
      Operator(id: 41, displayName: 'Συνάδελφος', createdAt: DateTime(2026)),
    );
    await _openMenu(tester, _floor(previous: true));

    expect(find.text('2ος'), findsOneWidget);
    expect(find.text('Προσθήκη νέας κάτοψης'), findsNothing);
    expect(find.text('Ανέβασμα κατόψεων στη βάση'), findsNothing);
    expect(find.byTooltip('Επεξεργασία'), findsNothing);
    expect(find.byTooltip('Επαναφορά προηγούμενης κάτοψης'), findsNothing);
    expect(find.byTooltip('Διαγραφή'), findsNothing);
  });

  testWidgets('διαχειριστής: όλες οι ενέργειες, και ανέβασμα όσο λείπει '
      'κάτοψη', (tester) async {
    CurrentOperator.activate(
      Operator(
        id: 42,
        displayName: 'Διαχειριστής',
        isAdmin: true,
        createdAt: DateTime(2026),
      ),
    );
    await _openMenu(tester, _floor());

    expect(find.text('Προσθήκη νέας κάτοψης'), findsOneWidget);
    expect(find.text('Ανέβασμα κατόψεων στη βάση'), findsOneWidget);
    expect(find.byTooltip('Επεξεργασία'), findsOneWidget);
    expect(find.byTooltip('Διαγραφή'), findsOneWidget);
    // Χωρίς προηγούμενη εικόνα δεν υπάρχει τι να επανέλθει.
    expect(find.byTooltip('Επαναφορά προηγούμενης κάτοψης'), findsNothing);
  });

  testWidgets('όλες οι κατόψεις ανεβασμένες: το «Ανέβασμα» φεύγει, η '
      'επαναφορά φαίνεται όταν υπάρχει προηγούμενη', (tester) async {
    CurrentOperator.activate(
      Operator(
        id: 43,
        displayName: 'Διαχειριστής',
        isAdmin: true,
        createdAt: DateTime(2026),
      ),
    );
    await _openMenu(tester, _floor(hash: 'abc', previous: true));

    expect(find.text('Ανέβασμα κατόψεων στη βάση'), findsNothing);
    expect(find.byTooltip('Επαναφορά προηγούμενης κάτοψης'), findsOneWidget);
  });
}
