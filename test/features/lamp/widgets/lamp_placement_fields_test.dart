// Τα δύο συνδεδεμένα πεδία τοποθέτησης.
//
// Ελέγχεται η ΣΥΝΔΕΣΗ, όχι η εμφάνιση: το πεδίο υπαλλήλου κλειδωμένο μέχρι
// να οριστεί γραφείο, οι ομάδες που ξαναχτίζονται, και ότι το φίλτρο δεν
// αποκλείει τον υπόλοιπο κόσμο.
//
//   flutter test test/features/lamp/widgets/lamp_placement_fields_test.dart

import 'package:call_logger/core/database/old_database/lamp_placement_catalog.dart';
import 'package:call_logger/features/lamp/widgets/lamp_placement_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_reporter.dart';

void main() {
  const gynecology = 'Μαιευτική-Γυναικολογική Κλινική';
  const catalog = LampPlacementCatalog(
    offices: <LampPlacementOffice>[
      LampPlacementOffice(
        id: 27,
        officeName: 'Γραφείο Ιατρών Γυναικολογικής',
        departmentName: gynecology,
      ),
      LampPlacementOffice(
        id: 20,
        officeName: 'Πληροφορική',
        departmentName: 'Πληροφορικής',
      ),
    ],
    owners: <LampPlacementOwner>[
      LampPlacementOwner(
        id: 337,
        name: 'Ζούκας Λάμπρος',
        officeId: 27,
        officeName: 'Γραφείο Ιατρών Γυναικολογικής',
        departmentName: gynecology,
      ),
      LampPlacementOwner(
        id: 81,
        name: 'Καμπάς Νικόλαος',
        officeId: 182,
        officeName: 'Διευθυντής Γυναικολογικής',
        departmentName: gynecology,
        equipmentCount: 11,
      ),
      LampPlacementOwner(
        id: 26,
        name: 'Δασκαλοπούλου Ιωάννα',
        officeId: 20,
        officeName: 'Πληροφορική',
        departmentName: 'Πληροφορικής',
        equipmentCount: 3,
      ),
    ],
  );

  /// Στήνει τα πεδία και επιστρέφει πάντα την τρέχουσα κατάσταση.
  Future<LampPlacementDraft Function()> pump(
    WidgetTester tester, {
    int? officeId,
  }) async {
    var current = LampPlacementDraft(officeId: officeId);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => LampPlacementFields(
              catalog: catalog,
              draft: current,
              onChanged: (draft) => setState(() => current = draft),
            ),
          ),
        ),
      ),
    );
    return () => current;
  }

  Finder ownerField() => find.descendant(
    of: find.byKey(const Key('lamp_placement_owner_field')),
    matching: find.byType(TextField),
  );

  group('η απόφαση που βγαίνει από τα πεδία', () {
    test('μόνο γραφείο δεν αρκεί — ο υπάλληλος είναι υποχρεωτικός', () {
      expect(const LampPlacementDraft(officeId: 27).toInput(), isNull);
    });

    test('υπάρχων υπάλληλος από τη λίστα', () {
      final input = const LampPlacementDraft(
        officeId: 27,
        ownerId: 81,
      ).toInput();
      expect(input?.officeId, 27);
      expect(input?.ownerId, 81);
    });

    test('νέος υπάλληλος θέλει και επώνυμο και όνομα', () {
      const onlySurname = LampPlacementDraft(
        officeId: 27,
        creatingOwner: true,
        newOwnerLastName: 'Παπαδοπούλου',
      );
      expect(onlySurname.toInput(), isNull);

      final input = const LampPlacementDraft(
        officeId: 27,
        creatingOwner: true,
        newOwnerLastName: ' Παπαδοπούλου ',
        newOwnerFirstName: 'Θάνια',
      ).toInput();
      expect(input?.ownerId, isNull);
      expect(input?.newOwnerLastName, 'Παπαδοπούλου');
      expect(input?.newOwnerFirstName, 'Θάνια');
    });
  });

  testWidgets('το πεδίο υπαλλήλου είναι κλειδωμένο χωρίς γραφείο', (
    tester,
  ) async {
    await pump(tester);

    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('lamp_placement_owner_field')),
        matching: find.byType(TextField),
      ),
    );

    expect(field.enabled, isFalse);
    expect(field.decoration?.hintText, 'Διαλέξτε πρώτα γραφείο');
  });

  testWidgets('με γραφείο επιλεγμένο το πεδίο υπαλλήλου ξεκλειδώνει', (
    tester,
  ) async {
    await pump(tester, officeId: 27);

    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('lamp_placement_owner_field')),
        matching: find.byType(TextField),
      ),
    );

    expect(field.enabled, isTrue);
  });

  testWidgets('η επιλογή γραφείου ανεβάζει το id προς τα πάνω', (tester) async {
    int? reported;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LampPlacementFields(
            catalog: catalog,
            draft: const LampPlacementDraft(),
            onChanged: (draft) => reported = draft.officeId,
          ),
        ),
      ),
    );

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('lamp_placement_office_field')),
        matching: find.byType(TextField),
      ),
      'Πληροφορ',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('20 · Πληροφορική · Πληροφορικής').last);
    await tester.pumpAndSettle();

    expect(reported, 20);
  });

  testWidgets('η λίστα υπαλλήλων δείχνει τις ομάδες και τα πλήθη', (
    tester,
  ) async {
    await pump(tester, officeId: 27);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('lamp_placement_owner_field')),
        matching: find.byType(TextField),
      ),
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('lamp_placement_owner_field')),
        matching: find.byType(TextField),
      ),
      '',
    );
    await tester.pumpAndSettle();

    expect(find.text('Σε αυτό το γραφείο · 1'), findsOneWidget);
    expect(find.text('Στο τμήμα «$gynecology» · 1'), findsOneWidget);
    expect(
      find.text('Υπόλοιπη βάση · 1'),
      findsOneWidget,
      reason: greekExpectMsg(
        'Το φίλτρο του γραφείου βοηθά αλλά δεν κλειδώνει: ο σωστός κάτοχος '
        'μπορεί να ανήκει οπουδήποτε',
      ),
    );
    expect(find.text('11 εξοπλισμοί'), findsOneWidget);
  });

  testWidgets('η αλλαγή γραφείου μηδενίζει τον ήδη επιλεγμένο υπάλληλο', (
    tester,
  ) async {
    LampPlacementDraft? last;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LampPlacementFields(
            catalog: catalog,
            draft: const LampPlacementDraft(officeId: 27, ownerId: 81),
            onChanged: (draft) => last = draft,
          ),
        ),
      ),
    );

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('lamp_placement_office_field')),
        matching: find.byType(TextField),
      ),
      'Πληροφορ',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('20 · Πληροφορική · Πληροφορικής').last);
    await tester.pumpAndSettle();

    expect(last?.officeId, 20);
    expect(
      last?.ownerId,
      isNull,
      reason: greekExpectMsg(
        'Ο προηγούμενος υπάλληλος ανήκε σε άλλο τμήμα — αν έμενε, θα '
        'γραφόταν σιωπηλά λάθος ζεύγος',
      ),
    );
  });

  testWidgets(
    'όνομα που δεν υπάρχει προσφέρει «Νέος υπάλληλος» με δύο κουτάκια',
    (tester) async {
      final current = await pump(tester, officeId: 27);

      await tester.tap(ownerField());
      await tester.enterText(ownerField(), 'Θάνια');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('lamp_placement_new_owner_option')),
      );
      await tester.pumpAndSettle();

      expect(current().creatingOwner, isTrue);
      expect(current().toInput(), isNull);

      await tester.enterText(
        find.byKey(const Key('lamp_placement_new_owner_last_name')),
        'Παπαδοπούλου',
      );
      await tester.enterText(
        find.byKey(const Key('lamp_placement_new_owner_first_name')),
        'Θάνια',
      );
      await tester.pump();

      final input = current().toInput();
      expect(input?.officeId, 27);
      expect(input?.newOwnerLastName, 'Παπαδοπούλου');
      expect(input?.newOwnerFirstName, 'Θάνια');
    },
  );

  testWidgets('αλλαγή κειμένου μετά την επιλογή ακυρώνει τον υπάλληλο', (
    tester,
  ) async {
    final current = await pump(tester, officeId: 27);

    await tester.tap(ownerField());
    await tester.enterText(ownerField(), 'Καμπ');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Καμπάς Νικόλαος').last);
    await tester.pumpAndSettle();
    expect(current().ownerId, 81);

    await tester.enterText(ownerField(), 'Καμπάς Νίκος');
    await tester.pump();

    expect(
      current().toInput(),
      isNull,
      reason: greekExpectMsg(
        'Το όνομα στο πεδίο και ο υπάλληλος που θα γραφτεί πρέπει να '
        'συμφωνούν — αλλιώς αποθηκεύεται κάποιος που δεν φαίνεται',
      ),
    );
  });
}
