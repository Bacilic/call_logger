// Διάλογος «Τι θα συμβεί»: πότε εμφανίζεται η σύνοψη και τι επιστρέφει.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/screens/widgets/department_deletion_preview_dialog_test.dart

import 'package:call_logger/features/directory/screens/widgets/department_deletion_preview_dialog.dart';
import 'package:call_logger/features/directory/services/department_deletion_inventory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

var _nextId = 0;

DepartmentDeletionInventory _inv(
  String name, {
  int? id,
  List<String> employees = const [],
  List<String> sharedPhones = const [],
}) {
  return DepartmentDeletionInventory(
    departmentId: id ?? ++_nextId,
    departmentName: name,
    employeeNames: employees,
    employeeOwnedPhoneCount: 0,
    employeeOwnedEquipmentCount: 0,
    sharedPhones: sharedPhones,
    sharedEquipmentCodes: const [],
  );
}

void main() {
  DepartmentDeletionPreviewResult? captured;

  Future<void> openWith(
    WidgetTester tester,
    List<DepartmentDeletionInventory> inventories,
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
                captured = await showDepartmentDeletionPreviewDialog(
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

  testWidgets('ένα τμήμα: καμία σύνοψη — το πλήθος δεν λέει τίποτα', (
    tester,
  ) async {
    await openWith(tester, [
      _inv('Αιμοδοσία', sharedPhones: ['2101']),
    ]);

    expect(find.text('Αιμοδοσία'), findsOneWidget);
    expect(find.textContaining('1 τμήμα ·'), findsNothing);
  });

  testWidgets('πολλά τμήματα: η σύνοψη δείχνει το μέγεθος της πράξης', (
    tester,
  ) async {
    await openWith(tester, [
      _inv('Αιμοδοσία', employees: ['Σοφία'], sharedPhones: ['2101']),
      _inv('Ακτινολογικό', sharedPhones: ['2102']),
      _inv('Αξονικός'),
    ]);

    expect(
      find.text('3 τμήματα · 1 υπάλληλος · 2 κοινόχρηστα τηλέφωνα'),
      findsOneWidget,
    );
  });

  testWidgets('με πολλά τμήματα τα κουμπιά μένουν προσιτά χωρίς κύλιση', (
    tester,
  ) async {
    await openWith(tester, [
      for (var i = 1; i <= 40; i++) _inv('Τμήμα $i', sharedPhones: ['210$i']),
    ]);

    // Χωρίς όριο ύψους ο διάλογος ξεπερνούσε την οθόνη και τα κουμπιά έβγαιναν
    // εκτός οπτικού πεδίου· τώρα κυλάει μόνο η λίστα.
    expect(find.text('Ακύρωση'), findsOneWidget);
    expect(find.text('Μεταφορά όλων σε ένα τμήμα…'), findsOneWidget);
    expect(find.textContaining('40 τμήματα'), findsOneWidget);
  });

  testWidgets('τα άδεια τμήματα μαζεύονται σε μία γραμμή, όχι σε κάρτες', (
    tester,
  ) async {
    await openWith(tester, [
      _inv('Αιμοδοσία', employees: ['Σοφία']),
      _inv('Άδειο Α'),
      _inv('Άδειο Β'),
      _inv('Άδειο Γ'),
    ]);

    expect(
      find.text('3 τμήματα χωρίς εξαρτήματα — διαγράφονται χωρίς ερώτηση'),
      findsOneWidget,
    );
    // Τα ονόματά τους υπάρχουν, αλλά κρυμμένα μέχρι να ζητηθούν.
    expect(find.text('Άδειο Α, Άδειο Β, Άδειο Γ'), findsNothing);
    expect(find.text('Αιμοδοσία'), findsOneWidget);
  });

  testWidgets('η πτυσσόμενη γραμμή αποκαλύπτει τα ονόματα των άδειων', (
    tester,
  ) async {
    await openWith(tester, [
      _inv('Αιμοδοσία', employees: ['Σοφία']),
      _inv('Άδειο Α'),
      _inv('Άδειο Β'),
    ]);

    await tester.tap(
      find.text('2 τμήματα χωρίς εξαρτήματα — διαγράφονται χωρίς ερώτηση'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Άδειο Α, Άδειο Β'), findsOneWidget);
  });

  testWidgets('με δύο ζώνες εμφανίζονται επικεφαλίδες με πλήθη', (
    tester,
  ) async {
    await openWith(tester, [
      _inv('Αιμοδοσία', employees: ['Σοφία']),
      _inv('Ακτινολογικό', sharedPhones: ['2102']),
      _inv('Αξονικός', sharedPhones: ['2103']),
    ]);

    expect(find.text('Με υπαλλήλους (1)'), findsOneWidget);
    expect(
      find.text('Με κοινόχρηστα τηλέφωνα ή εξοπλισμό (2)'),
      findsOneWidget,
    );
  });

  testWidgets('με μία μόνο ζώνη δεν μπαίνουν επικεφαλίδες', (tester) async {
    await openWith(tester, [
      _inv('Ακτινολογικό', sharedPhones: ['2102']),
      _inv('Αξονικός', sharedPhones: ['2103']),
    ]);

    expect(find.textContaining('Με κοινόχρηστα'), findsNothing);
    expect(find.text('Ακτινολογικό'), findsOneWidget);
  });

  testWidgets('η ακύρωση επιστρέφει cancel', (tester) async {
    await openWith(tester, [_inv('Α'), _inv('Β')]);

    await tester.tap(find.text('Ακύρωση'));
    await tester.pumpAndSettle();

    expect(captured?.choice, DepartmentDeletionChoice.cancel);
  });

  testWidgets('χωρίς εξαρτήματα εμφανίζεται σκέτη «Διαγραφή»', (tester) async {
    await openWith(tester, [_inv('Α'), _inv('Β')]);

    expect(find.text('Διαγραφή'), findsOneWidget);
    expect(find.text('Αναλυτικά (ανά οντότητα)'), findsNothing);

    await tester.tap(find.text('Διαγραφή'));
    await tester.pumpAndSettle();

    expect(captured?.choice, DepartmentDeletionChoice.detailed);
  });

  testWidgets('χωρίς αφαίρεση επιστρέφονται όλα τα τμήματα', (tester) async {
    await openWith(tester, [
      _inv('Α', id: 11, sharedPhones: ['1']),
      _inv('Β', id: 22, sharedPhones: ['2']),
    ]);

    await tester.tap(find.text('Μεταφορά όλων σε ένα τμήμα…'));
    await tester.pumpAndSettle();

    expect(captured?.keptDepartmentIds, [11, 22]);
  });

  testWidgets('η αφαίρεση βγάζει το τμήμα από το αποτέλεσμα', (tester) async {
    await openWith(tester, [
      _inv('Αιμοδοσία', id: 11, sharedPhones: ['1']),
      _inv('Ακτινολογικό', id: 22, sharedPhones: ['2']),
      _inv('Αξονικός', id: 33, sharedPhones: ['3']),
    ]);

    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('Ακτινολογικό'),
          matching: find.byType(Card),
        ),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ακτινολογικό'), findsNothing);

    await tester.tap(find.text('Μεταφορά όλων σε ένα τμήμα…'));
    await tester.pumpAndSettle();

    expect(captured?.keptDepartmentIds, [11, 33]);
  });

  testWidgets('η σύνοψη ακολουθεί την αφαίρεση αντί να λέει ψέματα', (
    tester,
  ) async {
    await openWith(tester, [
      _inv('Α', id: 11, employees: ['Σοφία'], sharedPhones: ['1']),
      _inv('Β', id: 22, sharedPhones: ['2']),
      _inv('Γ', id: 33, sharedPhones: ['3']),
    ]);

    expect(
      find.text('3 τμήματα · 1 υπάλληλος · 3 κοινόχρηστα τηλέφωνα'),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.ancestor(of: find.text('Α'), matching: find.byType(Card)),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('2 από τα 3 επιλεγμένα · 2 κοινόχρηστα τηλέφωνα'),
      findsOneWidget,
    );
  });

  testWidgets('μετά από αφαίρεση η σύνοψη λέει «Ν από τα Μ επιλεγμένα»', (
    tester,
  ) async {
    await openWith(tester, [
      _inv('Α', id: 11, sharedPhones: ['1']),
      _inv('Β', id: 22, sharedPhones: ['2']),
      _inv('Γ', id: 33, sharedPhones: ['3']),
    ]);

    await tester.tap(
      find.descendant(
        of: find.ancestor(of: find.text('Α'), matching: find.byType(Card)),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('2 από τα 3 επιλεγμένα · 2 κοινόχρηστα τηλέφωνα'),
      findsOneWidget,
    );
  });

  testWidgets('όλα άδεια: η σύνοψη παραλείπεται ως διπλή πληροφορία', (
    tester,
  ) async {
    await openWith(tester, [_inv('Α'), _inv('Β'), _inv('Γ')]);

    expect(
      find.text('3 τμήματα χωρίς εξαρτήματα — διαγράφονται χωρίς ερώτηση'),
      findsOneWidget,
    );
    // Η σύνοψη «3 τμήματα» δεν θα πρόσθετε τίποτα.
    expect(find.text('3 τμήματα'), findsNothing);
  });

  testWidgets('με ένα μόνο τμήμα δεν προσφέρεται αφαίρεση', (tester) async {
    await openWith(tester, [
      _inv('Μοναδικό', sharedPhones: ['1']),
    ]);

    expect(find.byIcon(Icons.close), findsNothing);
  });
}
