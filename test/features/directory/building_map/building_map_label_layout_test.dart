// Διάταξη ετικέτας χάρτη: η αναζήτηση μεγέθους γραμμάτων δεν αφήνει πίσω της
// μετρήσεις κειμένου. Ο χάρτης ξαναδιατάσσει κάθε ετικέτα σε κάθε καρέ, άρα
// ό,τι δεν αποδεσμεύεται εδώ μαζεύεται όσο μετακινείς ή μεγεθύνεις.
//
// Ο έλεγχος διαρροών είναι ενεργός (flutter_test_config.dart): το τεστ
// κοκκινίζει αν μείνει έστω μία μέτρηση χωρίς αποδέσμευση.
//
//   flutter test test/features/directory/building_map/building_map_label_layout_test.dart

import 'package:call_logger/features/directory/building_map/building_map_label_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'η διάταξη ετικέτας αποδεσμεύει τις δοκιμές της, και ο χρήστης της το αποτέλεσμα',
    (tester) async {
      final layout = layoutMapLabelTextInBox(
        text: 'Γραμματεία ΤΕΙ Ορθοπεδικό',
        boxWidth: 120,
        boxHeight: 40,
        maxFontSize: 20,
      );

      expect(layout.textPainter.width, greaterThan(0));
      expect(layout.fontSize, greaterThan(0));

      layout.dispose();
    },
  );

  test('το ελάχιστο πλάτος πλαισίου χωρά τη μεγαλύτερη λέξη', () {
    expect(
      computeMinMapLabelBoxWidthForText('Α Ορθοπεδικό'),
      greaterThan(computeMinMapLabelBoxWidthForText('Α Β')),
    );
  });
}
