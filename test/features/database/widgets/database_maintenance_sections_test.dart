// Τα όρια της εκκαθάρισης Ιστορικού δέχονται μόνο ψηφία.
//
// Πριν: «30,5» ή «abc» γραφόταν στο πεδίο, η αποθήκευση απαντούσε
// «αποθηκεύτηκαν», αλλά ίσχυε σιωπηλά το παλιό όριο — και με αυτό γινόταν η
// επόμενη εκκαθάριση.
//
//   flutter test test/features/database/widgets/database_maintenance_sections_test.dart

import 'package:call_logger/features/database/widgets/database_maintenance_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('γράμματα και υποδιαστολή δεν μπαίνουν στο όριο', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RetentionLimitField(
            controller: controller,
            enabled: true,
            label: 'Κλήσεις, εκκρεμότητες, αντίγραφα (ημέρες)',
            hint: 'Κενό = χωρίς όριο',
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '3a0,5x');

    expect(
      controller.text,
      '305',
      reason: 'Ό,τι φαίνεται στο πεδίο είναι ό,τι θα αποθηκευτεί.',
    );
  });
}
