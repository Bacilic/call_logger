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

  Future<({int? officeId, int? ownerId})> pump(
    WidgetTester tester, {
    int? officeId,
  }) async {
    var current = (officeId: officeId, ownerId: null as int?);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => LampPlacementFields(
              catalog: catalog,
              officeId: current.officeId,
              ownerId: current.ownerId,
              onChanged: ({officeId, ownerId}) => setState(
                () => current = (officeId: officeId, ownerId: ownerId),
              ),
            ),
          ),
        ),
      ),
    );
    return current;
  }

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
            officeId: null,
            ownerId: null,
            onChanged: ({officeId, ownerId}) => reported = officeId,
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
    ({int? officeId, int? ownerId})? last;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LampPlacementFields(
            catalog: catalog,
            officeId: 27,
            ownerId: 81,
            onChanged: ({officeId, ownerId}) =>
                last = (officeId: officeId, ownerId: ownerId),
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
}
