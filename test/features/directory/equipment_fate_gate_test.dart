// Η ερώτηση «ο εξοπλισμός ακολουθεί ή μένει;» δεν γίνεται όταν ο προορισμός
// δεν μπορεί να κρατά μηχανήματα.
//
// Το «Ακολουθεί» προς εταιρεία ήταν υπόσχεση που δεν τηρείται: το μηχάνημα
// έμενε χρεωμένο σε άνθρωπο που δεν δικαιούται να το κρατά. Η μαζική μεταφορά
// είχε τη δική της πύλη· η καρτέλα του υπαλλήλου και η γρήγορη συσχέτιση από
// την κλήση όχι.
//
// Η πύλη ζει πλέον ΜΕΣΑ στην ερώτηση, ώστε καμία ροή να μην μπορεί να την
// ξεχάσει — και αυτό ακριβώς φυλάει το τεστ.
//
//   flutter test test/features/directory/equipment_fate_gate_test.dart

import 'package:call_logger/features/directory/models/department_kind.dart';
import 'package:call_logger/features/directory/screens/widgets/asset_fate_on_department_change.dart';
import 'package:call_logger/features/directory/services/bulk_user_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _kOpenButton = 'ASK_EQUIPMENT_FATE';
const _kDialogTitle = 'Εξοπλισμός του υπαλλήλου';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BulkTransferAssetFate? answer;
  late bool answered;

  Future<void> ask(WidgetTester tester, DepartmentKind targetKind) async {
    answer = null;
    answered = false;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  answer = await askEquipmentFateOnDepartmentChange(
                    context,
                    targetKind: targetKind,
                    userDisplayName: 'Αντώνης Δαμωράκης',
                  );
                  answered = true;
                },
                child: const Text(_kOpenButton),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text(_kOpenButton));
    await tester.pumpAndSettle();
  }

  group('Προορισμός που ΔΕΝ κρατά μηχανήματα', () {
    testWidgets('εταιρεία: καμία ερώτηση, ο εξοπλισμός μένει πίσω', (
      tester,
    ) async {
      await ask(tester, DepartmentKind.company);

      expect(
        find.text(_kDialogTitle),
        findsNothing,
        reason:
            'Το «Ακολουθεί» θα ήταν υπόσχεση που δεν τηρείται — δεν '
            'προσφέρεται καν.',
      );
      expect(answered, isTrue);
      expect(answer, BulkTransferAssetFate.stayInOldDepartment);
    });
  });

  group('Προορισμός που κρατά μηχανήματα', () {
    testWidgets('τμήμα νοσοκομείου: η ερώτηση γίνεται κανονικά', (
      tester,
    ) async {
      await ask(tester, DepartmentKind.hospital);

      expect(find.text(_kDialogTitle), findsOneWidget);
      expect(find.text('Ακολουθεί στο νέο τμήμα'), findsOneWidget);
      expect(find.text('Μένει στο παλιό τμήμα'), findsOneWidget);
    });

    testWidgets('εξωτερική μονάδα: κρατά μηχανήματα, άρα ρωτά', (tester) async {
      await ask(tester, DepartmentKind.externalUnit);

      expect(
        find.text(_kDialogTitle),
        findsOneWidget,
        reason:
            'Το Κέντρο Υγείας δουλεύει με δικά μας μηχανήματα — η διάκριση '
            'είναι η ΚΑΤΟΧΗ, όχι το κτίριο.',
      );
    });

    testWidgets('η απάντηση επιστρέφεται όπως δόθηκε', (tester) async {
      await ask(tester, DepartmentKind.hospital);

      await tester.tap(find.text('Ακολουθεί στο νέο τμήμα'));
      await tester.pumpAndSettle();

      expect(answer, BulkTransferAssetFate.follow);
    });
  });
}
