// Τα πεδία δημιουργίας σύμβασης.
//
// Ελέγχεται η σύνδεση: το όνομα προσυμπληρωμένο, ο προμηθευτής από τη λίστα
// και όχι ελεύθερο κείμενο, η κατηγορία προαιρετική.
//
//   flutter test test/features/lamp/widgets/lamp_contract_fields_test.dart

import 'package:call_logger/core/database/old_database/lamp_placement_catalog.dart';
import 'package:call_logger/features/lamp/widgets/lamp_contract_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_reporter.dart';

void main() {
  const catalog = LampPlacementCatalog(
    offices: <LampPlacementOffice>[],
    owners: <LampPlacementOwner>[],
    suppliers: <LampContractLookupEntry>[
      LampContractLookupEntry(id: 5, name: 'Infotechnica SA'),
      LampContractLookupEntry(id: 42, name: 'MULTILAB AE'),
    ],
    contractCategories: <LampContractLookupEntry>[
      LampContractLookupEntry(id: 1, name: 'Προμήθεια'),
      LampContractLookupEntry(id: 2, name: 'Δωρεά'),
    ],
  );

  Future<TextEditingController> pump(
    WidgetTester tester, {
    required void Function({int? supplierId, int? categoryId}) onChanged,
    String initialName = '30236',
  }) async {
    final controller = TextEditingController(text: initialName);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LampContractFields(
            catalog: catalog,
            nameController: controller,
            supplierId: null,
            categoryId: null,
            onChanged: onChanged,
          ),
        ),
      ),
    );
    return controller;
  }

  testWidgets('το όνομα εμφανίζεται προσυμπληρωμένο', (tester) async {
    await pump(tester, onChanged: ({supplierId, categoryId}) {});

    final field = tester.widget<TextField>(
      find.byKey(const Key('lamp_contract_name_field')),
    );

    expect(field.controller?.text, '30236');
  });

  testWidgets('η επιλογή προμηθευτή ανεβάζει το αναγνωριστικό', (tester) async {
    int? reported;
    await pump(
      tester,
      onChanged: ({supplierId, categoryId}) => reported = supplierId,
    );

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('lamp_contract_supplier_field')),
        matching: find.byType(TextField),
      ),
      'multi',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('MULTILAB AE').last);
    await tester.pumpAndSettle();

    expect(
      reported,
      42,
      reason: greekExpectMsg(
        'Ο προμηθευτής διαλέγεται από τους υπάρχοντες· ελεύθερο κείμενο θα '
        'δημιουργούσε δεύτερη ορθογραφία του ίδιου',
      ),
    );
  });

  testWidgets('η κατηγορία έχει και κενή επιλογή', (tester) async {
    int? reported = 99;
    await pump(
      tester,
      onChanged: ({supplierId, categoryId}) => reported = categoryId,
    );

    await tester.tap(find.byKey(const Key('lamp_contract_category_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Δωρεά').last);
    await tester.pumpAndSettle();

    expect(reported, 2);
  });

  testWidgets('η αναζήτηση προμηθευτή αγνοεί πεζά-κεφαλαία', (tester) async {
    expect(catalog.searchSuppliers('INFO').single.id, 5);
    expect(catalog.searchSuppliers('').length, 2);
  });
}
