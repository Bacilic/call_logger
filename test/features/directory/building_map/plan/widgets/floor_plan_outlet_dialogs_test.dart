// Το παράθυρο «Τι είναι συνδεδεμένο» μιας θύρας πρίζας: η αναζήτηση βρίσκει
// ό,τι γράφεται χωρίς τόνους ή με κεφαλαία, και το κόκκινο «χ» την αδειάζει.
//
//   flutter test test/features/directory/building_map/plan/widgets/floor_plan_outlet_dialogs_test.dart

import 'package:call_logger/core/models/floor_plan_port.dart';
import 'package:call_logger/features/directory/building_map/plan/widgets/floor_plan_outlet_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const List<FloorPlanConnectionChoice> _choices = [
  (id: 1021, label: '1021', detail: 'Παπαγεωργίου Γιώτα', nearby: false),
  (id: 1064, label: '1064', detail: 'Κόικα Βασιλική', nearby: false),
  (id: 7, label: 'Πρίζα Γραφείου', detail: null, nearby: true),
];

void main() {
  test('χωρίς τόνους και με κεφαλαία βρίσκει το ίδιο', () {
    List<int> ids(String query) => [
      for (final c in floorPlanConnectionMatches(_choices, query)) c.id,
    ];

    expect(ids('γιωτ'), [1021]);
    expect(ids('ΓΙΩΤΑ'), [1021]);
    expect(ids('πριζα'), [7]);
    expect(ids('ΠΡΙΖΑ'), [7]);
    expect(ids('  '), [1021, 1064, 7]);
  });

  testWidgets('το κόκκινο «χ» αδειάζει την αναζήτηση και φέρνει πίσω όλη τη '
      'λίστα', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showFloorPlanConnectionDialog(
                context,
                portTitle: 'Θύρα 1',
                current: FloorPlanPortConnection.none,
                equipment: _choices,
                objects: const [],
              ),
              child: const Text('άνοιγμα'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('άνοιγμα'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Καθαρισμός αναζήτησης'), findsNothing);

    await tester.enterText(find.byType(TextField), 'γιωτ');
    await tester.pump();
    expect(find.text('1064'), findsNothing);

    await tester.tap(find.byTooltip('Καθαρισμός αναζήτησης'));
    await tester.pump();
    expect(find.text('1064'), findsOneWidget);
    expect(find.byTooltip('Καθαρισμός αναζήτησης'), findsNothing);
  });
}
