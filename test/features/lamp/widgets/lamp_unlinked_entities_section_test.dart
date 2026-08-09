// Ενότητα «Χωρίς συνδεδεμένο εξοπλισμό»: μεταφορά και σήμα κενής εγγραφής.
//
//   flutter test test/features/lamp/widgets/lamp_unlinked_entities_section_test.dart

import 'package:call_logger/core/database/old_database/lamp_unlinked_entities.dart';
import 'package:call_logger/features/lamp/widgets/lamp_unlinked_entities_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_reporter.dart';

void main() {
  LampUnlinkedEntity owner({bool empty = false, int id = 327}) =>
      buildLampUnlinkedEntity(LampUnlinkedEntityKind.owner, <String, Object?>{
        'id': id,
        'last_name': 'Αβραμοπούλου',
        'first_name': 'Αλέκα',
        'phones': empty ? null : '2963',
        'e_mail': null,
        'office_name': 'Φαρμακείο',
        'department_name': 'Φαρμακείο',
      })!;

  LampUnlinkedEntity contract() => buildLampUnlinkedEntity(
    LampUnlinkedEntityKind.contract,
    <String, Object?>{'id': 12, 'contract_name': 'Συντήρηση 2019'},
  )!;

  Future<List<LampUnlinkedEntity>> pump(
    WidgetTester tester,
    List<LampUnlinkedEntity> entities, {
    bool withHandler = true,
  }) async {
    final transferred = <LampUnlinkedEntity>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LampUnlinkedEntitiesSection(
              entities: entities,
              onTransfer: withHandler ? transferred.add : null,
            ),
          ),
        ),
      ),
    );
    return transferred;
  }

  testWidgets('ιδιοκτήτης έχει κουμπί μεταφοράς που καλεί τον χειριστή', (
    tester,
  ) async {
    final entity = owner();
    final transferred = await pump(tester, <LampUnlinkedEntity>[entity]);

    await tester.tap(
      find.byKey(const Key('lamp_unlinked_transfer_owner_327')),
    );
    await tester.pump();

    expect(transferred, <LampUnlinkedEntity>[entity]);
  });

  testWidgets('σύμβαση ΔΕΝ έχει κουμπί μεταφοράς', (tester) async {
    await pump(tester, <LampUnlinkedEntity>[contract()]);

    expect(
      find.byKey(const Key('lamp_unlinked_transfer_contract_12')),
      findsNothing,
      reason: greekExpectMsg(
        'Οι συμβάσεις δεν υπάρχουν ως οντότητες στην κανονική βάση — κουμπί '
        'που οδηγεί σε βέβαιη άρνηση είναι χειρότερο από απουσία κουμπιού',
      ),
    );
  });

  testWidgets('σήμα «κενή εγγραφή» μόνο όταν λείπουν τα στοιχεία', (
    tester,
  ) async {
    await pump(tester, <LampUnlinkedEntity>[owner()]);
    expect(find.byKey(const Key('lamp_unlinked_empty_badge')), findsNothing);

    await pump(tester, <LampUnlinkedEntity>[owner(empty: true)]);
    expect(find.byKey(const Key('lamp_unlinked_empty_badge')), findsOneWidget);
  });

  testWidgets('η κενή εγγραφή κρατά το κουμπί μεταφοράς της', (tester) async {
    final entity = owner(empty: true);
    final transferred = await pump(tester, <LampUnlinkedEntity>[entity]);

    await tester.tap(
      find.byKey(const Key('lamp_unlinked_transfer_owner_327')),
    );
    await tester.pump();

    expect(
      transferred,
      <LampUnlinkedEntity>[entity],
      reason: greekExpectMsg(
        'Το σήμα είναι πληροφορία, όχι απαγόρευση — ο Διευθυντής αποφασίζει',
      ),
    );
  });

  testWidgets('χωρίς χειριστή δεν εμφανίζονται κουμπιά', (tester) async {
    await pump(
      tester,
      <LampUnlinkedEntity>[owner()],
      withHandler: false,
    );

    expect(find.text('Μεταφορά'), findsNothing);
  });
}
