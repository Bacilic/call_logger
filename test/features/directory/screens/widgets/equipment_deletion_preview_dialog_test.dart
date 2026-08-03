// Προεπισκόπηση μαζικής διαγραφής εξοπλισμού: τι δείχνει και τι επιστρέφει.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/screens/widgets/equipment_deletion_preview_dialog_test.dart

import 'package:call_logger/features/directory/screens/widgets/equipment_deletion_preview_dialog.dart';
import 'package:call_logger/features/directory/services/equipment_deletion_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

var _nextId = 0;

EquipmentDeletionSummary _eq(
  String code, {
  int? id,
  String? owner,
  String? department,
  String? phone,
  int calls = 0,
  int tasks = 0,
  DateTime? lastCallAt,
  DateTime? lastTaskAt,
}) {
  return EquipmentDeletionSummary(
    equipmentId: id ?? ++_nextId,
    code: code,
    ownerName: owner,
    departmentName: department,
    phone: phone,
    callCount: calls,
    taskCount: tasks,
    lastCallAt: lastCallAt,
    lastTaskAt: lastTaskAt,
  );
}

void main() {
  EquipmentDeletionPreviewResult? captured;

  Future<void> openWith(
    WidgetTester tester,
    List<EquipmentDeletionSummary> summaries,
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
                captured = await showEquipmentDeletionPreviewDialog(
                  context: ctx,
                  summaries: summaries,
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

  testWidgets('ο εξοπλισμός δεν εμφανίζεται ποτέ ως σκέτος αριθμός', (
    tester,
  ) async {
    await openWith(tester, [
      _eq('3602', owner: 'Μαρία Α', calls: 1),
      _eq('3603', department: 'Αιμοδοσία', calls: 1),
      _eq('3604', calls: 1),
    ]);

    expect(find.text('3602 → Μαρία Α'), findsOneWidget);
    expect(find.text('3603 → τμήμα Αιμοδοσία'), findsOneWidget);
    expect(find.text('3604 → χωρίς κάτοχο και τμήμα'), findsOneWidget);
  });

  testWidgets('το μεγάλο όνομα συντομεύεται αλλά κρατά το επώνυμο', (
    tester,
  ) async {
    await openWith(tester, [
      _eq('3602', owner: 'Κωνσταντίνα Παπαδοπούλου', calls: 1),
    ]);

    expect(find.text('3602 → Κω. Παπαδοπούλου'), findsOneWidget);
  });

  testWidgets('ένας εξοπλισμός: καμία σύνοψη — το πλήθος δεν λέει τίποτα', (
    tester,
  ) async {
    await openWith(tester, [_eq('3602', owner: 'Μαρία Α', calls: 1)]);

    expect(find.textContaining('1 εξοπλισμός ·'), findsNothing);
  });

  testWidgets('η σύνοψη μετρά κατόχους, κλήσεις και εκκρεμότητες', (
    tester,
  ) async {
    await openWith(tester, [
      _eq('3602', owner: 'Μαρία Α', calls: 4),
      _eq('3603', department: 'Αιμοδοσία', tasks: 1),
      _eq('3604'),
    ]);

    expect(
      find.text(
        '3 εξοπλισμοί · 1 με κάτοχο · 4 κλήσεις ιστορικού · 1 εκκρεμότητα',
      ),
      findsOneWidget,
    );
  });

  testWidgets('η κάρτα δείχνει τι αφήνει πίσω του και πότε', (tester) async {
    await openWith(tester, [
      _eq(
        '3604',
        owner: 'Μαρία Α',
        phone: '2898',
        calls: 4,
        tasks: 1,
        lastCallAt: DateTime(2026, 6, 12),
        lastTaskAt: DateTime(2026, 7, 28),
      ),
    ]);

    expect(find.text('τηλ. 2898'), findsOneWidget);
    expect(
      find.text('4 κλήσεις ιστορικού (τελευταία 12/06/2026)'),
      findsOneWidget,
    );
    expect(find.text('1 εκκρεμότητα (τελευταία 28/07/2026)'), findsOneWidget);
  });

  testWidgets('με δύο ζώνες εμφανίζονται επικεφαλίδες με πλήθη', (
    tester,
  ) async {
    await openWith(tester, [
      _eq('3602', owner: 'Μαρία Α', calls: 1),
      _eq('3603', owner: 'Νίκος Β', tasks: 1),
      _eq('3604', owner: 'Άννα Γ'),
    ]);

    expect(
      find.text('Με ιστορικό ή ανοιχτές εκκρεμότητες (2)'),
      findsOneWidget,
    );
    expect(find.text('1 εξοπλισμός χωρίς κανένα ίχνος χρήσης'), findsOneWidget);
  });

  testWidgets('με μία μόνο ζώνη δεν μπαίνουν επικεφαλίδες', (tester) async {
    await openWith(tester, [
      _eq('3602', owner: 'Μαρία Α', calls: 1),
      _eq('3603', owner: 'Νίκος Β', calls: 1),
    ]);

    expect(find.textContaining('Με ιστορικό'), findsNothing);
    expect(find.text('3602 → Μαρία Α'), findsOneWidget);
  });

  testWidgets('οι άιχνοι μαζεύονται σε πτυσσόμενη γραμμή, με τον κάτοχό τους', (
    tester,
  ) async {
    await openWith(tester, [
      _eq('3602', owner: 'Μαρία Α', calls: 1),
      _eq('3603', department: 'Αιμοδοσία'),
      _eq('3604', owner: 'Νίκος Β'),
    ]);

    expect(find.text('3603 → τμήμα Αιμοδοσία'), findsNothing);

    await tester.tap(find.text('2 εξοπλισμοί χωρίς κανένα ίχνος χρήσης'));
    await tester.pumpAndSettle();

    expect(find.text('3603 → τμήμα Αιμοδοσία'), findsOneWidget);
    expect(find.text('3604 → Νίκος Β'), findsOneWidget);
  });

  testWidgets('όταν ΚΑΝΕΝΑΣ δεν αφήνει ίχνη η λίστα μένει ορατή', (
    tester,
  ) async {
    await openWith(tester, [
      _eq('3603', owner: 'Μαρία Α'),
      _eq('3604', owner: 'Νίκος Β'),
    ]);

    expect(find.text('3603 → Μαρία Α'), findsOneWidget);
    expect(find.text('3604 → Νίκος Β'), findsOneWidget);
  });

  testWidgets('με πολύ εξοπλισμό τα κουμπιά μένουν προσιτά χωρίς κύλιση', (
    tester,
  ) async {
    await openWith(tester, [
      for (var i = 1; i <= 40; i++) _eq('EQ-$i', owner: 'Χρήστης $i', calls: 1),
    ]);

    expect(find.text('Ακύρωση'), findsOneWidget);
    expect(find.text('Διαγραφή'), findsOneWidget);
    expect(find.textContaining('40 εξοπλισμοί'), findsOneWidget);
  });

  testWidgets('η ακύρωση επιστρέφει άρνηση', (tester) async {
    await openWith(tester, [_eq('1', owner: 'Α'), _eq('2', owner: 'Β')]);

    await tester.tap(find.text('Ακύρωση'));
    await tester.pumpAndSettle();

    expect(captured?.confirmed, isFalse);
  });

  testWidgets('χωρίς αφαίρεση επιστρέφεται όλος ο εξοπλισμός', (tester) async {
    await openWith(tester, [
      _eq('1', id: 11, owner: 'Α', calls: 1),
      _eq('2', id: 22, owner: 'Β', calls: 1),
    ]);

    await tester.tap(find.text('Διαγραφή'));
    await tester.pumpAndSettle();

    expect(captured?.confirmed, isTrue);
    expect(captured?.keptEquipmentIds, [11, 22]);
  });

  testWidgets('η αφαίρεση βγάζει τον εξοπλισμό από το αποτέλεσμα', (
    tester,
  ) async {
    await openWith(tester, [
      _eq('1', id: 11, owner: 'Α', calls: 1),
      _eq('2', id: 22, owner: 'Β', calls: 1),
      _eq('3', id: 33, owner: 'Γ', calls: 1),
    ]);

    await tester.tap(
      find.descendant(
        of: find.ancestor(of: find.text('2 → Β'), matching: find.byType(Card)),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 → Β'), findsNothing);

    await tester.tap(find.text('Διαγραφή'));
    await tester.pumpAndSettle();

    expect(captured?.keptEquipmentIds, [11, 33]);
  });

  testWidgets('η σύνοψη ακολουθεί την αφαίρεση αντί να λέει ψέματα', (
    tester,
  ) async {
    await openWith(tester, [
      _eq('1', id: 11, owner: 'Α', calls: 1),
      _eq('2', id: 22, owner: 'Β', calls: 1),
      _eq('3', id: 33, owner: 'Γ', calls: 1),
    ]);

    expect(
      find.text('3 εξοπλισμοί · 3 με κάτοχο · 3 κλήσεις ιστορικού'),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.ancestor(of: find.text('1 → Α'), matching: find.byType(Card)),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('2 από τα 3 επιλεγμένα · 2 με κάτοχο · 2 κλήσεις ιστορικού'),
      findsOneWidget,
    );
  });

  testWidgets('με έναν μόνο εξοπλισμό δεν προσφέρεται αφαίρεση', (
    tester,
  ) async {
    await openWith(tester, [_eq('Μοναδικός', owner: 'Α', calls: 1)]);

    expect(find.byIcon(Icons.close), findsNothing);
  });
}
