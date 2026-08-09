import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/directory/screens/widgets/user_form_equipment_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

UserEquipmentChipEntry _entry(EquipmentModel equipment, {int owners = 1}) =>
    (equipment: equipment, ownerCount: owners);

Future<void> _pumpChips(
  WidgetTester tester, {
  required List<UserEquipmentChipEntry> entries,
  void Function(EquipmentModel)? onTap,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: UserFormEquipmentChips(
          entries: entries,
          onTapEquipment: onTap ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('κάθε εξοπλισμός εμφανίζεται με τον κωδικό του', (tester) async {
    await _pumpChips(
      tester,
      entries: [
        _entry(EquipmentModel(id: 1, code: '3917', type: 'Υπολογιστής')),
        _entry(EquipmentModel(id: 2, code: '4102', type: 'Εκτυπωτής')),
      ],
    );

    expect(find.text('3917'), findsOneWidget);
    expect(find.text('4102'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('κλικ σε chip ειδοποιεί με τον εξοπλισμό που πατήθηκε', (
    tester,
  ) async {
    EquipmentModel? tapped;
    await _pumpChips(
      tester,
      entries: [
        _entry(EquipmentModel(id: 1, code: '3917')),
        _entry(EquipmentModel(id: 2, code: '4102')),
      ],
      onTap: (e) => tapped = e,
    );

    await tester.tap(find.text('4102'));
    await tester.pump();

    expect(tapped?.id, 2);
  });

  testWidgets('υπάλληλος χωρίς εξοπλισμό βλέπει ρητό μήνυμα, όχι κενό', (
    tester,
  ) async {
    await _pumpChips(tester, entries: const []);

    expect(find.text('Δεν κουβαλά εξοπλισμό.'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('εξοπλισμός χωρίς επιπλέον στοιχεία δεν παίρνει υπόδειξη', (
    tester,
  ) async {
    await _pumpChips(
      tester,
      entries: [_entry(EquipmentModel(id: 1, code: '3698'))],
    );

    expect(find.byType(Tooltip), findsNothing);
  });

  group('Υπόδειξη chip', () {
    test('δεν επαναλαμβάνει τον κωδικό — τον γράφει ήδη το chip', () {
      final text = userEquipmentChipTooltip(
        _entry(
          EquipmentModel(
            id: 1,
            code: '3917',
            type: 'Υπολογιστής',
            location: '1ος - Γραφεία',
          ),
        ),
      );

      expect(text, 'Υπολογιστής — 1ος - Γραφεία');
    });

    test('σκέτος κωδικός χωρίς τύπο και τοποθεσία δεν δίνει υπόδειξη', () {
      expect(
        userEquipmentChipTooltip(_entry(EquipmentModel(id: 1, code: '3698'))),
        isNull,
      );
    });

    test('ο κοινόχρηστος εξοπλισμός το δηλώνει με το πλήθος κατόχων', () {
      final text = userEquipmentChipTooltip(
        _entry(EquipmentModel(id: 1, code: '4102'), owners: 3),
      );

      expect(text, 'Κοινόχρηστος: τον κρατούν 3 υπάλληλοι.');
    });

    test('τύπος και κοινόχρηστος μπαίνουν σε δικές τους γραμμές', () {
      final text = userEquipmentChipTooltip(
        _entry(
          EquipmentModel(id: 1, code: '4102', type: 'Εκτυπωτής'),
          owners: 2,
        ),
      );

      expect(text, 'Εκτυπωτής\nΚοινόχρηστος: τον κρατούν 2 υπάλληλοι.');
    });
  });
}
