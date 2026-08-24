// «Αλλαγή χρήστη» χωρίς επανεκκίνηση: η ενεργή ταυτότητα αλλάζει από τη
// μπάρα, όποιος τη δείχνει ενημερώνεται ζωντανά, και το Ιστορικό σφραγίζει
// με όποιον είναι ενεργός τη στιγμή της αποθήκευσης.
//
// Όλα τα σενάρια τρέχουν με αντικαταστάσιμα βήματα (χωρίς πραγματική βάση) —
// το φιλτράρισμα «μόνο ενεργά προφίλ» έχει δικό του τεστ στο
// operator_identity_test.dart.
//
//   flutter test test/features/operators/change_operator_flow_test.dart

import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/services/operator_identity.dart';
import 'package:call_logger/features/operators/services/selectable_profiles.dart';
import 'package:call_logger/features/operators/widgets/active_operator_chip.dart';
import 'package:call_logger/features/operators/widgets/change_operator_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Operator _operator(int id, String name) =>
    Operator(id: id, displayName: name, createdAt: DateTime(2026, 8, 20));

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Η επιλογή χρήστη γράφεται και στη μνήμη του υπολογιστή: κάθε τεστ
    // ξεκινά με άδεια, αλλιώς η επιλογή του ενός γίνεται αφετηρία του άλλου.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    CurrentOperator.reset();
  });
  tearDown(CurrentOperator.reset);

  group('Ταυτότητα συνεδρίας', () {
    test('η αλλαγή μέσα στη συνεδρία αλλάζει το όνομα σφράγισης', () {
      OperatorIdentity.activateForSession(_operator(1, 'Βασίλης'));
      expect(CurrentOperator.auditName, 'Βασίλης');

      OperatorIdentity.activateForSession(_operator(2, 'Μαρία'));
      expect(CurrentOperator.auditName, 'Μαρία');
    });

    test('η αλλαγή ειδοποιεί όσους παρακολουθούν την ταυτότητα', () {
      final seen = <String?>[];
      void listener() => seen.add(CurrentOperator.active?.displayName);
      CurrentOperator.listenable.addListener(listener);
      addTearDown(() => CurrentOperator.listenable.removeListener(listener));

      OperatorIdentity.activateForSession(_operator(1, 'Βασίλης'));
      OperatorIdentity.activateForSession(_operator(2, 'Μαρία'));
      CurrentOperator.reset();

      expect(seen, ['Βασίλης', 'Μαρία', null]);
    });
  });

  group('Ένδειξη στη μπάρα', () {
    testWidgets('δείχνει «Χωρίς χρήστη» και μετά το όνομα, ζωντανά', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActiveOperatorChip(extended: true, openDialog: (_) async {}),
          ),
        ),
      );

      expect(find.text('Χωρίς χρήστη'), findsOneWidget);

      // Η ταυτότητα αλλάζει «από αλλού» — η ένδειξη ακολουθεί χωρίς
      // εξωτερικό ξαναχτίσιμο.
      OperatorIdentity.activateForSession(_operator(1, 'Βασίλης'));
      await tester.pump();

      expect(find.text('Χωρίς χρήστη'), findsNothing);
      expect(find.text('Βασίλης'), findsOneWidget);
    });

    testWidgets('το πάτημα ανοίγει τον διάλογο αλλαγής', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActiveOperatorChip(
              extended: false,
              openDialog: (_) async => opened++,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(InkWell));
      await tester.pump();

      expect(opened, 1);
    });
  });

  group('Διάλογος «Αλλαγή χρήστη»', () {
    Future<void> openDialog(
      WidgetTester tester, {
      required List<Operator> profiles,
      OperatorProfileCreator? createProfile,
      List<Operator> workstationProfiles = const <Operator>[],
      Future<void> Function(String displayName)? keepOnlyCurrent,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showChangeOperatorDialog(
                  ctx,
                  loadProfiles: () async => SelectableProfiles(
                    profiles: profiles,
                    presence: const {},
                    workstationProfiles: workstationProfiles,
                  ),
                  createProfile:
                      createProfile ??
                      (name, bind) async => _operator(99, name),
                  keepOnlyCurrent: keepOnlyCurrent ?? (_) async {},
                ),
                child: const Text('άνοιγμα'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('άνοιγμα'));
      await tester.pumpAndSettle();
      expect(find.text('Αλλαγή χρήστη'), findsOneWidget);
    }

    testWidgets('επιλογή προφίλ → ενεργοποιείται και ο διάλογος κλείνει', (
      tester,
    ) async {
      OperatorIdentity.activateForSession(_operator(1, 'Βασίλης'));

      await openDialog(
        tester,
        profiles: [_operator(1, 'Βασίλης'), _operator(2, 'Μαρία')],
      );

      await tester.tap(find.text('Μαρία'));
      await tester.pumpAndSettle();

      expect(CurrentOperator.active?.id, 2);
      expect(CurrentOperator.auditName, 'Μαρία');
      expect(find.text('Αλλαγή χρήστη'), findsNothing);
    });

    testWidgets('δημιουργία νέου προφίλ μέσα από τον διάλογο', (tester) async {
      final created = <(String, bool)>[];

      await openDialog(
        tester,
        profiles: [_operator(1, 'Βασίλης')],
        createProfile: (name, bind) async {
          created.add((name, bind));
          return _operator(7, name);
        },
      );

      await tester.tap(find.text('Δεν είμαι στη λίστα'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Νίκος');
      await tester.tap(find.text('Συνέχεια'));
      await tester.pumpAndSettle();

      expect(created, hasLength(1));
      expect(created.single.$1, 'Νίκος');
      expect(find.text('Αλλαγή χρήστη'), findsNothing);
    });

    testWidgets('το «Άκυρο» κλείνει χωρίς να αλλάξει την ταυτότητα', (
      tester,
    ) async {
      OperatorIdentity.activateForSession(_operator(1, 'Βασίλης'));

      await openDialog(tester, profiles: [_operator(2, 'Μαρία')]);

      await tester.tap(find.text('Άκυρο'));
      await tester.pumpAndSettle();

      expect(CurrentOperator.active?.id, 1);
      expect(find.text('Αλλαγή χρήστη'), findsNothing);
    });

    testWidgets('με έναν μόνο χρήστη δεν προσφέρεται καθαρισμός', (
      tester,
    ) async {
      OperatorIdentity.activateForSession(_operator(1, 'Βασίλης'));

      await openDialog(
        tester,
        profiles: [_operator(2, 'Βλάσης')],
        workstationProfiles: [_operator(1, 'Βασίλης')],
      );

      expect(find.text('Εδώ κάθομαι μόνο εγώ'), findsNothing);
    });

    testWidgets('με δύο χρήστες, ο καθαρισμός κρατά τον τρέχοντα', (
      tester,
    ) async {
      // Ο συνάδελφος που κάθισε μια φορά δεν πρέπει να κάνει τον σταθμό να
      // ρωτά για έναν μήνα.
      OperatorIdentity.activateForSession(_operator(1, 'Βασίλης'));
      final kept = <String>[];

      await openDialog(
        tester,
        profiles: [_operator(2, 'Βλάσης')],
        workstationProfiles: [_operator(2, 'Βλάσης'), _operator(1, 'Βασίλης')],
        keepOnlyCurrent: (name) async => kept.add(name),
      );

      await tester.tap(find.text('Εδώ κάθομαι μόνο εγώ'));
      await tester.pumpAndSettle();

      expect(kept, ['Βασίλης']);
      expect(find.text('Αλλαγή χρήστη'), findsNothing);
    });
  });
}
