// Προεπισκόπηση μαζικής διαγραφής υπαλλήλων: τι δείχνει και τι επιστρέφει.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/screens/widgets/user_deletion_preview_dialog_test.dart

import 'package:call_logger/features/directory/screens/widgets/user_deletion_preview_dialog.dart';
import 'package:call_logger/features/directory/services/user_deletion_zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

var _nextId = 0;

UserDeletionInventory _inv(
  String label, {
  int? id,
  int phones = 0,
  int equipment = 0,
}) {
  return UserDeletionInventory(
    userId: id ?? ++_nextId,
    displayLabel: label,
    exclusivePhoneCount: phones,
    exclusiveEquipmentCount: equipment,
  );
}

void main() {
  UserDeletionPreviewResult? captured;

  Future<void> openWith(
    WidgetTester tester,
    List<UserDeletionInventory> inventories,
  ) async {
    captured = null;
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                captured = await showUserDeletionPreviewDialog(
                  context: ctx,
                  inventories: inventories,
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
  }

  testWidgets('ένας υπάλληλος: καμία σύνοψη — το πλήθος δεν λέει τίποτα', (
    tester,
  ) async {
    await openWith(tester, [_inv('Σοφία (Αιμοδοσία)', phones: 1)]);

    expect(find.text('Σοφία (Αιμοδοσία)'), findsOneWidget);
    expect(find.textContaining('1 υπάλληλος ·'), findsNothing);
  });

  testWidgets('πολλοί υπάλληλοι: η σύνοψη δείχνει το μέγεθος της πράξης', (
    tester,
  ) async {
    await openWith(tester, [
      _inv('Σοφία', phones: 1),
      _inv('Νίκος', equipment: 2),
      _inv('Μαρία'),
    ]);

    expect(
      find.text('3 υπάλληλοι · 1 προσωπικό τηλέφωνο · 2 προσωπικοί εξοπλισμοί'),
      findsOneWidget,
    );
  });

  testWidgets('η προειδοποίηση μετρά τις ερωτήσεις που ακολουθούν', (
    tester,
  ) async {
    await openWith(tester, [
      _inv('Σοφία', phones: 2),
      _inv('Νίκος', equipment: 1),
    ]);

    expect(
      find.text(
        'Θα σας ζητηθεί απόφαση για 3 στοιχεία πριν ολοκληρωθεί η διαγραφή.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('χωρίς προσωπικά στοιχεία δεν υπόσχεται ερωτήσεις', (
    tester,
  ) async {
    await openWith(tester, [_inv('Σοφία'), _inv('Νίκος')]);

    expect(find.textContaining('Θα σας ζητηθεί απόφαση'), findsNothing);
  });

  testWidgets('με πολλούς υπαλλήλους τα κουμπιά μένουν προσιτά χωρίς κύλιση', (
    tester,
  ) async {
    await openWith(tester, [
      for (var i = 1; i <= 40; i++) _inv('Υπάλληλος $i', phones: 1),
    ]);

    expect(find.text('Ακύρωση'), findsOneWidget);
    expect(find.text('Διαγραφή'), findsOneWidget);
    expect(find.textContaining('40 υπάλληλοι'), findsOneWidget);
  });

  testWidgets('με δύο ζώνες εμφανίζονται επικεφαλίδες με πλήθη', (
    tester,
  ) async {
    await openWith(tester, [
      _inv('Σοφία', phones: 1),
      _inv('Νίκος', equipment: 1),
      _inv('Μαρία'),
    ]);

    expect(find.text('Με προσωπικά στοιχεία (2)'), findsOneWidget);
    expect(
      find.text(
        '1 υπάλληλος χωρίς προσωπικά στοιχεία — διαγράφεται χωρίς '
        'ερώτηση',
      ),
      findsOneWidget,
    );
  });

  testWidgets('με μία μόνο ζώνη δεν μπαίνουν επικεφαλίδες', (tester) async {
    await openWith(tester, [
      _inv('Σοφία', phones: 1),
      _inv('Νίκος', phones: 1),
    ]);

    expect(find.textContaining('Με προσωπικά στοιχεία'), findsNothing);
    expect(find.text('Σοφία'), findsOneWidget);
  });

  testWidgets('οι άδειοι μαζεύονται σε πτυσσόμενη γραμμή όταν υπάρχουν και '
      'γεμάτοι', (tester) async {
    await openWith(tester, [
      _inv('Σοφία', phones: 1),
      _inv('Άδειος Α'),
      _inv('Άδειος Β'),
    ]);

    expect(find.text('Άδειος Α, Άδειος Β'), findsNothing);

    await tester.tap(
      find.text(
        '2 υπάλληλοι χωρίς προσωπικά στοιχεία — διαγράφονται χωρίς ερώτηση',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Άδειος Α, Άδειος Β'), findsOneWidget);
  });

  testWidgets('όταν ΟΛΟΙ είναι άδειοι τα ονόματα μένουν ορατά', (tester) async {
    await openWith(tester, [_inv('Άδειος Α'), _inv('Άδειος Β')]);

    // Η ονομαστική λίστα είναι η μόνη πληροφορία — δεν συμπτύσσεται.
    expect(find.text('Άδειος Α'), findsOneWidget);
    expect(find.text('Άδειος Β'), findsOneWidget);
  });

  testWidgets('η κάρτα δείχνει τι θα ρωτηθεί για τον καθένα', (tester) async {
    await openWith(tester, [
      _inv('Σοφία', phones: 1, equipment: 2),
      _inv('Νίκος', phones: 1),
    ]);

    expect(find.text('1 προσωπικό τηλέφωνο'), findsNWidgets(2));
    expect(find.text('2 προσωπικοί εξοπλισμοί'), findsOneWidget);
  });

  testWidgets('η ακύρωση επιστρέφει άρνηση', (tester) async {
    await openWith(tester, [_inv('Σοφία'), _inv('Νίκος')]);

    await tester.tap(find.text('Ακύρωση'));
    await tester.pumpAndSettle();

    expect(captured?.confirmed, isFalse);
  });

  testWidgets('χωρίς αφαίρεση επιστρέφονται όλοι οι υπάλληλοι', (tester) async {
    await openWith(tester, [
      _inv('Σοφία', id: 11, phones: 1),
      _inv('Νίκος', id: 22, phones: 1),
    ]);

    await tester.tap(find.text('Διαγραφή'));
    await tester.pumpAndSettle();

    expect(captured?.confirmed, isTrue);
    expect(captured?.keptUserIds, [11, 22]);
  });

  testWidgets('η αφαίρεση βγάζει τον υπάλληλο από το αποτέλεσμα', (
    tester,
  ) async {
    await openWith(tester, [
      _inv('Σοφία', id: 11, phones: 1),
      _inv('Νίκος', id: 22, phones: 1),
      _inv('Μαρία', id: 33, phones: 1),
    ]);

    await tester.tap(
      find.descendant(
        of: find.ancestor(of: find.text('Νίκος'), matching: find.byType(Card)),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Νίκος'), findsNothing);

    await tester.tap(find.text('Διαγραφή'));
    await tester.pumpAndSettle();

    expect(captured?.keptUserIds, [11, 33]);
  });

  testWidgets('η σύνοψη ακολουθεί την αφαίρεση αντί να λέει ψέματα', (
    tester,
  ) async {
    await openWith(tester, [
      _inv('Σοφία', id: 11, phones: 1),
      _inv('Νίκος', id: 22, phones: 1),
      _inv('Μαρία', id: 33, phones: 1),
    ]);

    expect(find.text('3 υπάλληλοι · 3 προσωπικά τηλέφωνα'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.ancestor(of: find.text('Σοφία'), matching: find.byType(Card)),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('2 από τα 3 επιλεγμένα · 2 προσωπικά τηλέφωνα'),
      findsOneWidget,
    );
  });

  testWidgets('η αφαίρεση μειώνει και τις ερωτήσεις που υπόσχεται', (
    tester,
  ) async {
    await openWith(tester, [
      _inv('Σοφία', id: 11, phones: 2),
      _inv('Νίκος', id: 22, phones: 1),
    ]);

    await tester.tap(
      find.descendant(
        of: find.ancestor(of: find.text('Σοφία'), matching: find.byType(Card)),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Θα σας ζητηθεί απόφαση για 1 στοιχείο πριν ολοκληρωθεί η διαγραφή.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('με έναν μόνο υπάλληλο δεν προσφέρεται αφαίρεση', (tester) async {
    await openWith(tester, [_inv('Μοναδικός', phones: 1)]);

    expect(find.byIcon(Icons.close), findsNothing);
  });
}
