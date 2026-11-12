// Το γρανάζι της σχεδίασης: οι βοήθειες ξεκινούν ανοιχτές, αποθηκεύονται όσες
// έκλεισε ο χρήστης, και κάθε κουτάκι αλλάζει μόνο τη δική του βοήθεια.
//
//   flutter test test/features/directory/building_map/plan/widgets/floor_plan_drawing_settings_button_test.dart

import 'package:call_logger/features/directory/building_map/plan/services/floor_plan_drawing_preferences.dart';
import 'package:call_logger/features/directory/building_map/plan/widgets/floor_plan_drawing_settings_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('χωρίς αποθηκευμένη επιλογή όλες οι βοήθειες είναι ανοιχτές· '
      'αποθηκεύονται μόνο όσες έκλεισαν', () {
    final fresh = FloorPlanDrawingAids.fromOff(const {});
    expect((fresh.guides, fresh.angles), (true, true));
    expect(fresh.off, isEmpty);

    final noAngles = fresh.copyWith(angles: false);
    expect(noAngles.off, {'angles'});
    final restored = FloorPlanDrawingAids.fromOff(noAngles.off);
    expect((restored.guides, restored.angles), (true, false));
  });

  test('άγνωστη βοήθεια από νεότερη έκδοση αγνοείται', () {
    final aids = FloorPlanDrawingAids.fromOff(const {'κάτι-νέο'});
    expect((aids.guides, aids.angles), (true, true));
  });

  testWidgets('το κουτάκι «Γραμμές-οδηγοί» κλείνει μόνο τους οδηγούς', (
    tester,
  ) async {
    final changes = <FloorPlanDrawingAids>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FloorPlanDrawingSettingsButton(
              aids: const FloorPlanDrawingAids(),
              onChanged: changes.add,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Ρυθμίσεις σχεδίασης'));
    await tester.pumpAndSettle();
    expect(find.text('Μοίρες τομής'), findsOneWidget);

    await tester.tap(find.text('Γραμμές-οδηγοί'));
    await tester.pump();

    expect(changes, hasLength(1));
    expect((changes.single.guides, changes.single.angles), (false, true));
  });
}
