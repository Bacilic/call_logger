// Η φόρμα χρήστη: οι διακόπτες του τελευταίου διαχειριστή αρνούνται στο
// πάτημα, με το ίδιο μήνυμα που θα έδειχνε η Αποθήκευση.
//
//   flutter test test/features/operators/operator_form_dialog_test.dart

import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/features/operators/services/operator_management.dart';
import 'package:call_logger/features/operators/widgets/operator_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Operator _admin() => Operator(
  id: 1,
  displayName: 'Βαρβάρα',
  isAdmin: true,
  createdAt: DateTime(2026, 8, 26),
);

Future<void> _pumpForm(
  WidgetTester tester, {
  required bool lockedAsLastAdmin,
}) async {
  // Πραγματικό μέγεθος παραθύρου: στο προεπιλεγμένο 800x600 ο διάλογος
  // ξεχειλίζει και τα πατήματα στους κάτω διακόπτες πέφτουν στα κουμπιά.
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: OperatorFormDialog(
        existing: _admin(),
        lockedAsLastAdmin: lockedAsLastAdmin,
        onSubmit: (_) async => null,
      ),
    ),
  );
}

bool _switchValue(WidgetTester tester, String title) => tester
    .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, title))
    .value;

void main() {
  group('Τελευταίος διαχειριστής — άμεσος φραγμός στους διακόπτες', () {
    testWidgets('ο διακόπτης «Διαχειριστής» μένει αναμμένος και εξηγεί', (
      tester,
    ) async {
      await _pumpForm(tester, lockedAsLastAdmin: true);

      await tester.tap(find.widgetWithText(SwitchListTile, 'Διαχειριστής'));
      await tester.pumpAndSettle();

      expect(_switchValue(tester, 'Διαχειριστής'), isTrue);
      expect(find.text(kLastAdminDemoteBlockedMessage), findsOneWidget);
    });

    testWidgets('ο διακόπτης «Ενεργός» μένει αναμμένος και εξηγεί', (
      tester,
    ) async {
      await _pumpForm(tester, lockedAsLastAdmin: true);

      await tester.tap(find.widgetWithText(SwitchListTile, 'Ενεργός'));
      await tester.pumpAndSettle();

      expect(_switchValue(tester, 'Ενεργός'), isTrue);
      expect(find.text(kLastAdminArchiveBlockedMessage), findsOneWidget);
    });

    testWidgets('με δεύτερο διαχειριστή οι διακόπτες αλλάζουν κανονικά', (
      tester,
    ) async {
      await _pumpForm(tester, lockedAsLastAdmin: false);

      await tester.tap(find.widgetWithText(SwitchListTile, 'Διαχειριστής'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, 'Ενεργός'));
      await tester.pumpAndSettle();

      expect(_switchValue(tester, 'Διαχειριστής'), isFalse);
      expect(_switchValue(tester, 'Ενεργός'), isFalse);
      expect(find.text(kLastAdminDemoteBlockedMessage), findsNothing);
      expect(find.text(kLastAdminArchiveBlockedMessage), findsNothing);
    });

    testWidgets('το ξανα-άναμμα επιτρέπεται πάντα', (tester) async {
      // Ο φραγμός αφορά μόνο το σβήσιμο: αν κάτι είναι ήδη σβηστό (π.χ. η
      // φόρμα άνοιξε πριν προλάβει να κλειδώσει), το άναμμα δεν εμποδίζεται.
      await _pumpForm(tester, lockedAsLastAdmin: false);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Ενεργός'));
      await tester.pumpAndSettle();
      expect(_switchValue(tester, 'Ενεργός'), isFalse);

      await tester.tap(find.widgetWithText(SwitchListTile, 'Ενεργός'));
      await tester.pumpAndSettle();

      expect(_switchValue(tester, 'Ενεργός'), isTrue);
    });
  });

  testWidgets('ο τίτλος λέει ποιον επεξεργάζεστε', (tester) async {
    // «Επεξεργασία Βαρβάρα», όχι γενικό «Επεξεργασία χρήστη» — ο χρήστης
    // βλέπει αμέσως για ποιον κάνει αλλαγές, με το ΑΠΟΘΗΚΕΥΜΕΝΟ όνομα.
    await _pumpForm(tester, lockedAsLastAdmin: false);

    expect(find.text('Επεξεργασία Βαρβάρα'), findsOneWidget);
  });

  group('Η κρίση «τελευταίος ενεργός διαχειριστής;»', () {
    Operator operator(
      String name, {
      bool isAdmin = false,
      bool isActive = true,
    }) => Operator(
      id: name.length,
      displayName: name,
      isAdmin: isAdmin,
      isActive: isActive,
      createdAt: DateTime(2026, 8, 26),
    );

    test('μοναδικός ενεργός διαχειριστής → ναι', () {
      final varvara = operator('Βαρβάρα', isAdmin: true);
      final all = [varvara, operator('Παναγιώτης')];

      expect(isLastActiveAdmin(varvara, all), isTrue);
    });

    test('υπάρχει δεύτερος ενεργός διαχειριστής → όχι', () {
      final varvara = operator('Βαρβάρα', isAdmin: true);
      final all = [varvara, operator('Δημήτρης', isAdmin: true)];

      expect(isLastActiveAdmin(varvara, all), isFalse);
    });

    test('ο δεύτερος διαχειριστής είναι αρχειοθετημένος → ναι', () {
      // Ο αρχειοθετημένος δεν μπορεί να συνδεθεί — δεν μετράει ως δικλείδα.
      final varvara = operator('Βαρβάρα', isAdmin: true);
      final all = [
        varvara,
        operator('Παναγιώτης', isAdmin: true, isActive: false),
      ];

      expect(isLastActiveAdmin(varvara, all), isTrue);
    });

    test('απλός χρήστης → όχι, όσοι διαχειριστές κι αν λείπουν', () {
      final plain = operator('Παναγιώτης');

      expect(isLastActiveAdmin(plain, [plain]), isFalse);
    });
  });
}
