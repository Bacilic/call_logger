// Ό,τι δείχνει ένα χειριστήριο φίλτρου ισχύει.
//
// Το πλαίσιο αναζήτησης του Ιστορικού κρατούσε το κείμενό του για πάντα: μια
// μετάβαση από τα Στατιστικά μηδένιζε την αναζήτηση, αλλά η λέξη έμενε γραμμένη
// εκεί. Ο χρήστης διόρθωνε φίλτρο που δεν εφαρμοζόταν.
//
// Οι δύο πλευρές του κανόνα είναι εξίσου σημαντικές: το πεδίο ακολουθεί ό,τι
// έρχεται απ' έξω, αλλά ΠΟΤΕ όσο γράφει ο χρήστης μέσα του — αλλιώς μια
// καθυστερημένη ενημέρωση θα του έσβηνε τα γράμματα.
//
//   flutter test test/features/history/filter_field_follows_external_change_test.dart

import 'package:call_logger/features/history/widgets/call_entity_filter_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Οθόνη-δοκιμαστήριο: κρατά την τιμή του φίλτρου όπως θα την κρατούσε ο
  /// provider, και επιτρέπει να αλλάξει «απ' έξω».
  Future<void Function(String?)> pumpField(
    WidgetTester tester, {
    String? initial,
  }) async {
    late void Function(String?) setFromOutside;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setFromOutside = (value) => setState(() => initial = value);
              return CallEntityTextFilterField(
                label: 'Όνομα Χρήστη',
                icon: Icons.person_outline,
                value: initial,
                onChanged: (value) => setState(() => initial = value),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return setFromOutside;
  }

  group('Χειριστήριο φίλτρου και εξωτερικές αλλαγές', () {
    testWidgets('δείχνει την τιμή με την οποία ανοίγει', (tester) async {
      await pumpField(tester, initial: 'Ψαρρά');

      expect(find.text('Ψαρρά'), findsOneWidget);
    });

    testWidgets('ακολουθεί το μηδένισμα που έρχεται από άλλη οθόνη', (
      tester,
    ) async {
      final setFromOutside = await pumpField(tester, initial: 'εκτυπωτής');

      setFromOutside(null);
      await tester.pumpAndSettle();

      expect(
        find.text('εκτυπωτής'),
        findsNothing,
        reason:
            'Η μετάβαση καθάρισε το φίλτρο· κείμενο που μένει εκεί λέει ψέματα '
            'για το τι φιλτράρει η λίστα.',
      );
    });

    testWidgets('ακολουθεί και την αντικατάσταση με άλλη τιμή', (tester) async {
      final setFromOutside = await pumpField(tester, initial: 'εκτυπωτής');

      setFromOutside('Ψαρρά');
      await tester.pumpAndSettle();

      expect(find.text('Ψαρρά'), findsOneWidget);
      expect(find.text('εκτυπωτής'), findsNothing);
    });

    testWidgets('ΔΕΝ σβήνει ό,τι γράφει ο χρήστης εκείνη τη στιγμή', (
      tester,
    ) async {
      await pumpField(tester, initial: null);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Ψαρ');
      await tester.pump();

      // Η καθυστερημένη ενημέρωση φτάνει πίσω ενώ το πεδίο έχει εστίαση.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(
        find.text('Ψαρ'),
        findsOneWidget,
        reason:
            'Το πεδίο έχει εστίαση: ο χρήστης γράφει. Καμία εξωτερική τιμή δεν '
            'επιτρέπεται να του πάρει τα γράμματα από τα χέρια.',
      );
    });
  });
}
