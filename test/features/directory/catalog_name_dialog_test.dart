// Ο controller του διαλόγου ζει όσο ζει το πεδίο του.
//
// Παλιότερα ο καλών τον σκότωνε με `whenComplete` τη στιγμή του `pop`: ο
// διάλογος έφευγε ακόμη με μετάβαση, ο Navigator τον ξαναέχτιζε μόλις έπαψε
// να είναι ο τρέχων, και το πεδίο ξαναδενόταν σε νεκρό controller — κόκκινη
// οθόνη στο «Τμήματα → Ομάδες → Προσθήκη».
//
//   flutter test test/features/directory/catalog_name_dialog_test.dart

import 'package:call_logger/features/directory/screens/widgets/catalog_name_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<String?> open(
    WidgetTester tester, {
    List<String> catalog = const ['Εργαστήρια'],
    String? initial,
    String? allowSelf,
  }) async {
    String? result;
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                opened = true;
                result = await showCatalogNameDialog(
                  context: context,
                  title: 'Προσθήκη ομάδας',
                  actionLabel: 'Προσθήκη',
                  fieldLabel: 'Όνομα ομάδας',
                  emptyMessage: 'Δώστε όνομα ομάδας.',
                  sameEntityPhrase: 'είναι η ίδια ομάδα.',
                  catalog: catalog,
                  initial: initial,
                  allowSelf: allowSelf,
                );
              },
              child: const Text('άνοιγμα'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('άνοιγμα'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    return result;
  }

  testWidgets('το όνομα φτάνει στον καλούντα χωρίς κατάρρευση', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextFormField), 'Ακτινολογικά');
    await tester.tap(find.widgetWithText(FilledButton, 'Προσθήκη'));

    // Καρέ-καρέ όσο ο διάλογος φεύγει: εδώ ζούσε η κατάρρευση.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull, reason: 'καρέ $i');
    }
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('η ακύρωση κλείνει τον διάλογο χωρίς κατάρρευση', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextFormField), 'Κάτι');
    await tester.tap(find.widgetWithText(TextButton, 'Ακύρωση'));

    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull, reason: 'καρέ $i');
    }
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('το διπλότυπο κρατά τον διάλογο ανοιχτό με μήνυμα', (
    tester,
  ) async {
    await open(tester);
    // Ίδια ομάδα γραμμένη χωρίς τόνο και με πεζά.
    await tester.enterText(find.byType(TextFormField), 'εργαστηρια');
    await tester.tap(find.widgetWithText(FilledButton, 'Προσθήκη'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text('Υπάρχει ήδη ως «Εργαστήρια» — είναι η ίδια ομάδα.'),
      findsOneWidget,
    );
  });

  testWidgets('η μετονομασία δεν συγκρούεται με τον εαυτό της', (tester) async {
    await open(tester, initial: 'Εργαστήρια', allowSelf: 'Εργαστήρια');
    await tester.enterText(find.byType(TextFormField), 'Εργαστήρια');
    await tester.tap(find.widgetWithText(FilledButton, 'Προσθήκη'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('το κενό όνομα ζητά συμπλήρωση', (tester) async {
    await open(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Προσθήκη'));
    await tester.pumpAndSettle();

    expect(find.text('Δώστε όνομα ομάδας.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
