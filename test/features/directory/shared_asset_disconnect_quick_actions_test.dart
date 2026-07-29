// Μετρητής βημάτων, γρήγορες επιλογές και ρητή ακύρωση στη ροή αποδέσμευσης.
//
//   flutter test test/features/directory/shared_asset_disconnect_quick_actions_test.dart --timeout 30s

import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/screens/widgets/shared_asset_disconnect_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _deptName = 'Γραμματεία';

final _departments = <DepartmentModel>[
  DepartmentModel(id: 1, name: _deptName),
  DepartmentModel(id: 2, name: 'Αποθήκη Πληροφορικής'),
];

/// Καμία σύνδεση — κρατά το τεστ μακριά από πραγματική βάση.
Future<List<String>> _noReferences({
  required bool isPhone,
  required String value,
}) async => const <String>[];

/// Σταθερό ιστορικό ανά στοιχείο, χωρίς βάση.
Future<AssetHistoryLinks> _noHistory(AssetDisconnectItem item) async =>
    const AssetHistoryLinks();

Future<void> _openFlow(
  WidgetTester tester, {
  required List<String> phones,
  required List<String> equipmentCodes,
  required void Function(SharedAssetDisconnectBatchResult?) onResult,
  AssetDisconnectSession? session,
  bool allowKeepInDepartment = true,
  AssetHistoryLinksLookup? historyLookup,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () async {
              final result = await showSharedAssetDisconnectFlow(
                context: context,
                sourceDepartmentId: 1,
                sourceDepartmentName: _deptName,
                phones: phones,
                equipmentCodes: equipmentCodes,
                availableDepartments: _departments,
                mode: SharedAssetDisconnectMode.personalPhone,
                personalPhoneUserDisplayName: 'Μαρία Παπά',
                allowKeepInDepartment: allowKeepInDepartment,
                session: session,
                referenceLookup: _noReferences,
                historyLookup: historyLookup ?? _noHistory,
              );
              onResult(result);
            },
            child: const Text('OPEN'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ο μετρητής δείχνει τη θέση στη ροή', (tester) async {
    await _openFlow(
      tester,
      phones: const ['2510', '2511'],
      equipmentCodes: const ['EQ100'],
      onResult: (_) {},
    );

    expect(find.text('Βήμα 1 από 3'), findsOneWidget);
  });

  testWidgets('ένα μοναδικό στοιχείο δεν δείχνει μετρητή', (tester) async {
    await _openFlow(
      tester,
      phones: const ['2510'],
      equipmentCodes: const [],
      onResult: (_) {},
    );

    expect(find.textContaining('Βήμα '), findsNothing);
  });

  testWidgets(
    'ο μετρητής μετρά ΟΛΗ την ενέργεια όταν η συνεδρία έρχεται απ έξω',
    (tester) async {
      // Δέκα υπάλληλοι: 12 τηλέφωνα + 6 εξοπλισμοί. Η κλήση αφορά μόνο τα δύο
      // τηλέφωνα του πρώτου υπαλλήλου, αλλά ο μετρητής λέει την αλήθεια.
      final session = AssetDisconnectSession(
        items: <AssetDisconnectItem>[
          for (var i = 0; i < 12; i++) AssetDisconnectItem.phone('25${10 + i}'),
          for (var i = 0; i < 6; i++)
            AssetDisconnectItem.equipment('EQ${100 + i}'),
        ],
        cancelScopeDescription: 'η διαγραφή 10 υπαλλήλων',
      );

      await _openFlow(
        tester,
        phones: const ['2510', '2511'],
        equipmentCodes: const [],
        session: session,
        onResult: (_) {},
      );

      expect(find.text('Βήμα 1 από 18'), findsOneWidget);
      // Πρώτο βήμα: «όλα», όχι «υπόλοιπα» — δεν έχει απαντηθεί τίποτα ακόμα.
      expect(
        find.text('…ή μία απάντηση για όλα τα 18 στοιχεία'),
        findsOneWidget,
      );
    },
  );

  testWidgets('«Διαγραφή όλων» κλείνει τη ροή χωρίς άλλη ερώτηση', (
    tester,
  ) async {
    SharedAssetDisconnectBatchResult? result;
    await _openFlow(
      tester,
      phones: const ['2510', '2511', '2512'],
      equipmentCodes: const ['EQ100', 'EQ101'],
      onResult: (r) => result = r,
    );

    await tester.tap(find.text('Διαγραφή όλων (5)'));
    await tester.pumpAndSettle();

    expect(
      find.text('Διαγραφή 5 στοιχείων χωρίς άλλη ερώτηση'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Θα διαγραφούν 3 τηλέφωνα και 2 εξοπλισμοί'),
      findsOneWidget,
    );

    await tester.tap(find.text('Ναι, εφαρμογή σε όλα'));
    await tester.pumpAndSettle();

    // Κανένας άλλος διάλογος: η ροή τελείωσε στο πρώτο βήμα.
    expect(find.byType(AlertDialog), findsNothing);
    expect(result, isNotNull);
    expect(result!.phonesToDelete, ['2510', '2511', '2512']);
    expect(result!.equipmentToDelete, ['EQ100', 'EQ101']);
  });

  testWidgets('«Διαγραφή όλων των τηλεφώνων» αφήνει τον εξοπλισμό να ρωτηθεί', (
    tester,
  ) async {
    SharedAssetDisconnectBatchResult? result;
    await _openFlow(
      tester,
      phones: const ['2510', '2511'],
      equipmentCodes: const ['EQ100'],
      onResult: (r) => result = r,
    );

    await tester.tap(find.text('Διαγραφή όλων των τηλεφώνων (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ναι, εφαρμογή σε όλα'));
    await tester.pumpAndSettle();

    // Ο εξοπλισμός ρωτιέται κανονικά — και είναι το τελευταίο βήμα.
    expect(find.text('Αποδέσμευση κοινόχρηστου εξοπλισμού'), findsOneWidget);
    expect(find.text('Βήμα 3 από 3'), findsOneWidget);
    expect(
      find.text('Επιλέξτε ενέργεια για αυτόν τον εξοπλισμό'),
      findsOneWidget,
    );

    await tester.tap(find.text('Παραμονή στο $_deptName'));
    await tester.pumpAndSettle();

    expect(result!.phonesToDelete, ['2510', '2511']);
    expect(result!.equipmentToKeep, ['EQ100']);
    expect(result!.equipmentToDelete, isEmpty);
  });

  testWidgets('η γρήγορη επιλογή είναι διαθέσιμη μόνο με ≥2 στοιχεία', (
    tester,
  ) async {
    await _openFlow(
      tester,
      phones: const ['2510'],
      equipmentCodes: const [],
      onResult: (_) {},
    );

    expect(find.textContaining('μία απάντηση για'), findsNothing);
    // Οι ατομικές ενέργειες όμως είναι πάντα εκεί, στο σώμα του διαλόγου.
    expect(find.text('Επιλέξτε ενέργεια για αυτό το τηλέφωνο'), findsOneWidget);
    expect(find.text('Διαγραφή'), findsOneWidget);
  });

  testWidgets('η Ακύρωση δηλώνει τι ακυρώνει και επιτρέπει επιστροφή', (
    tester,
  ) async {
    SharedAssetDisconnectBatchResult? result;
    var resultReported = false;
    await _openFlow(
      tester,
      phones: const ['2510', '2511'],
      equipmentCodes: const [],
      session: AssetDisconnectSession(
        items: const [
          AssetDisconnectItem.phone('2510'),
          AssetDisconnectItem.phone('2511'),
        ],
        cancelScopeDescription: 'η διαγραφή 10 υπαλλήλων',
      ),
      onResult: (r) {
        result = r;
        resultReported = true;
      },
    );

    await tester.tap(find.text('Ακύρωση'));
    await tester.pumpAndSettle();

    expect(find.text('Ακύρωση όλων;'), findsOneWidget);
    expect(
      find.textContaining('Θα ακυρωθεί η διαγραφή 10 υπαλλήλων.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Τίποτα δεν έχει γραφτεί ακόμα στη βάση.'),
      findsOneWidget,
    );

    // «Συνέχεια» επιστρέφει στο ίδιο βήμα — τίποτα δεν χάθηκε.
    await tester.tap(find.text('Συνέχεια'));
    await tester.pumpAndSettle();
    expect(find.text('Βήμα 1 από 2'), findsOneWidget);
    expect(resultReported, isFalse);

    // «Ακύρωση όλων» τερματίζει τη ροή χωρίς αποτέλεσμα.
    await tester.tap(find.text('Ακύρωση'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ακύρωση όλων'));
    await tester.pumpAndSettle();

    expect(resultReported, isTrue);
    expect(result, isNull);
  });

  testWidgets('«Παραμονή — όλα» λείπει όταν τα τμήματα διαφέρουν', (
    tester,
  ) async {
    await _openFlow(
      tester,
      phones: const ['2510', '2511'],
      equipmentCodes: const [],
      session: AssetDisconnectSession(
        items: const [
          AssetDisconnectItem.phone(
            '2510',
            ownerName: 'Μαρία Παπά',
            departmentId: 1,
            departmentName: 'Γραμματεία',
          ),
          AssetDisconnectItem.phone(
            '2511',
            ownerName: 'Άννα Κορδαλή',
            departmentId: 9,
            departmentName: 'Άδειες',
          ),
        ],
      ),
      onResult: (_) {},
    );

    // Η ατομική παραμονή μένει — αφορά ΕΝΑ στοιχείο με γνωστό τμήμα.
    expect(find.text('Παραμονή στο $_deptName'), findsOneWidget);
    // Η καθολική φεύγει: τίποτα δεν «παραμένει» σε τμήμα που δεν ανήκει.
    expect(find.textContaining('— όλα ('), findsNothing);
    expect(find.textContaining('ανήκουν σε 2 τμήματα'), findsOneWidget);
  });

  testWidgets('«Παραμονή — όλα» εμφανίζεται όταν το τμήμα είναι κοινό', (
    tester,
  ) async {
    await _openFlow(
      tester,
      phones: const ['2510', '2511'],
      equipmentCodes: const [],
      session: AssetDisconnectSession(
        items: const [
          AssetDisconnectItem.phone(
            '2510',
            departmentId: 1,
            departmentName: _deptName,
          ),
          AssetDisconnectItem.phone(
            '2511',
            departmentId: 1,
            departmentName: _deptName,
          ),
        ],
      ),
      onResult: (_) {},
    );

    expect(find.text('Παραμονή στο $_deptName — όλα (2)'), findsOneWidget);
    expect(find.textContaining('ανήκουν σε'), findsNothing);
  });

  testWidgets('η επιβεβαίωση δείχνει ΟΛΑ τα στοιχεία με κάτοχο και ιστορικό', (
    tester,
  ) async {
    await _openFlow(
      tester,
      phones: const ['2216'],
      equipmentCodes: const ['2101', '462', '470', '526', '531'],
      session: AssetDisconnectSession(
        items: const [
          AssetDisconnectItem.phone(
            '2216',
            ownerName: 'Καλλιρρόη Βλαχάκη',
            departmentId: 4,
            departmentName: 'Ψυχιατρική',
          ),
          AssetDisconnectItem.equipment(
            '2101',
            ownerName: 'Βασιλική Οικονόμου',
            departmentId: 2,
            departmentName: 'Ακτινολογικό',
          ),
          AssetDisconnectItem.equipment(
            '462',
            ownerName: 'Μαρία Άγνωστη',
            departmentId: 1,
            departmentName: 'Γραμματεία',
          ),
          AssetDisconnectItem.equipment(
            '470',
            ownerName: 'Άννα Κορδαλή',
            departmentId: 9,
            departmentName: 'Άδειες',
          ),
          AssetDisconnectItem.equipment(
            '526',
            departmentId: 9,
            departmentName: 'Άδειες',
          ),
          AssetDisconnectItem.equipment(
            '531',
            ownerName: 'Ελένη Δημητριάδη',
            departmentId: 9,
            departmentName: 'Άδειες',
          ),
        ],
      ),
      historyLookup: (item) async => item.value == '2101'
          ? const AssetHistoryLinks(calls: 3)
          : const AssetHistoryLinks(),
      onResult: (_) {},
    );

    await tester.tap(find.text('Διαγραφή όλων (6)'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Θα διαγραφούν 1 τηλέφωνο και 5 εξοπλισμοί'),
      findsOneWidget,
    );
    // Και το έκτο στοιχείο φαίνεται — καμία κοπή στα 5.
    expect(find.textContaining('Ελένη Δημητριάδη'), findsOneWidget);
    expect(find.textContaining('κοινόχρηστο'), findsOneWidget);
    expect(find.textContaining('…και'), findsNothing);
    // Ιστορικό μόνο εκεί που υπάρχει — ο κάτοχος δεν είναι «σύνδεση».
    expect(find.textContaining('3 κλήσεις'), findsOneWidget);
  });
}
