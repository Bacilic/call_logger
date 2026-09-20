// Η ερώτηση για τα τηλέφωνα ρωτά μόνο για ό,τι μπορεί όντως να ακολουθήσει.
//
// Τρεις ροές την κάνουν — μαζική μεταφορά, καρτέλα υπαλλήλου, γρήγορη
// συσχέτιση από την κλήση. Η πύλη ζει ΜΕΣΑ στην ερώτηση ώστε καμία να μην
// μπορεί να την ξεχάσει, όπως ακριβώς και στον εξοπλισμό.
//
//   flutter test test/features/directory/phone_fate_gate_test.dart

import 'package:call_logger/features/directory/models/catalog_validation_rules.dart';
import 'package:call_logger/features/directory/models/department_kind.dart';
import 'package:call_logger/features/directory/screens/widgets/asset_fate_on_department_change.dart';
import 'package:call_logger/features/directory/services/bulk_user_actions.dart';
import 'package:call_logger/features/directory/services/phone_transfer_split.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _kOpenButton = 'ASK_PHONE_FATE';
const _kQuestionTitle = 'Τηλέφωνα του υπαλλήλου';
const _kNoticeTitle = 'Τηλέφωνα του νοσοκομείου';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BulkTransferAssetFate? answer;
  late bool answered;

  Future<void> ask(
    WidgetTester tester,
    List<String> phones,
    DepartmentKind targetKind, {
    String? source,
    List<String> stayBlockedReasons = const [],
  }) async {
    answer = null;
    answered = false;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final split = splitPhonesForDepartmentChange(
      phones: phones,
      targetKind: targetKind,
      rules: const CatalogValidationRules(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  answer = await askPhoneFateOnDepartmentChange(
                    context,
                    split: split,
                    targetKind: targetKind,
                    userDisplayName: 'Βασιλική Κίτσιου',
                    sourceDepartmentName: source,
                    stayBlockedReasons: stayBlockedReasons,
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

  group('Τίποτα διαπραγματεύσιμο', () {
    testWidgets('μόνο εσωτερικά προς εταιρεία: ενημέρωση, όχι ερώτηση', (
      tester,
    ) async {
      await ask(
        tester,
        ['2986'],
        DepartmentKind.company,
        source: 'Γραφείο Κίνησης',
      );

      expect(
        find.text(_kQuestionTitle),
        findsNothing,
        reason: 'Δεν υπάρχει τίποτα να αποφασιστεί.',
      );
      expect(find.text(_kNoticeTitle), findsOneWidget);
      expect(
        find.textContaining('μένει στο τμήμα «Γραφείο Κίνησης»'),
        findsOneWidget,
        reason: 'Σιωπηλή αλλαγή δεδομένων δεν επιτρέπεται.',
      );
    });

    testWidgets('η ενημέρωση επιβεβαιώνεται και η μεταφορά προχωρά', (
      tester,
    ) async {
      await ask(tester, ['2986'], DepartmentKind.company);

      await tester.tap(find.text('Συνέχεια'));
      await tester.pumpAndSettle();

      expect(answered, isTrue);
      expect(answer, BulkTransferAssetFate.stayInOldDepartment);
    });

    testWidgets('η ακύρωση σταματά τη μεταφορά', (tester) async {
      await ask(tester, ['2986'], DepartmentKind.company);

      await tester.tap(find.text('Ακύρωση'));
      await tester.pumpAndSettle();

      expect(answer, isNull);
    });
  });

  group('Υπάρχει τι να ρωτηθεί', () {
    testWidgets('μικτός: ρωτά ΟΝΟΜΑΣΤΙΚΑ μόνο για το εξωτερικό', (
      tester,
    ) async {
      await ask(
        tester,
        ['2503', '2741022667'],
        DepartmentKind.company,
        source: 'Υποδιευθυντής Διοικητικού',
      );

      expect(find.text(_kQuestionTitle), findsOneWidget);
      expect(
        find.textContaining('Το 2503 είναι εσωτερικό του νοσοκομείου'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Τι θα γίνει το 2741022667;'),
        findsOneWidget,
        reason:
            'Με δύο τηλέφωνα στην καρτέλα, ένα σκέτο «τα τηλέφωνα» θα '
            'υποσχόταν απόφαση και για το εσωτερικό.',
      );
      expect(
        find.textContaining('Τι θα γίνουν τα τηλέφωνα του υπαλλήλου'),
        findsNothing,
      );
    });

    testWidgets('μικτός: οι επιλογές μπαίνουν σε ΕΝΙΚΟ', (tester) async {
      await ask(
        tester,
        ['2503', '2741022667'],
        DepartmentKind.company,
        source: 'Υποδιευθυντής Διοικητικού',
      );

      expect(
        find.text('Μένει στο τμήμα «Υποδιευθυντής Διοικητικού»'),
        findsOneWidget,
      );
      expect(find.text('Ακολουθεί τον υπάλληλο'), findsOneWidget);
      expect(find.text('Ακολουθούν τον υπάλληλο'), findsNothing);
    });

    testWidgets('πολλά ρωτούμενα: πληθυντικός και ονόματα', (tester) async {
      await ask(
        tester,
        ['2503', '2741022667', '2109999999'],
        DepartmentKind.company,
        source: 'Υποδιευθυντής Διοικητικού',
      );

      expect(
        find.textContaining('Τι θα γίνουν τα 2741022667, 2109999999;'),
        findsOneWidget,
      );
      expect(
        find.text('Μένουν στο τμήμα «Υποδιευθυντής Διοικητικού»'),
        findsOneWidget,
      );
    });

    testWidgets('το όνομα του τμήματος μπαίνει στην επιλογή', (tester) async {
      await ask(
        tester,
        ['2741022667', '2109999999'],
        DepartmentKind.company,
        source: 'Υποδιευθυντής Διοικητικού',
      );

      expect(
        find.text('Μένουν στο τμήμα «Υποδιευθυντής Διοικητικού»'),
        findsOneWidget,
      );
      expect(find.text('Μένουν στο παλιό τμήμα'), findsNothing);
    });

    testWidgets('χωρίς όνομα τμήματος: η μαζική διατύπωση', (tester) async {
      await ask(tester, ['2741022667', '2109999999'], DepartmentKind.company);

      expect(find.text('Μένουν στο παλιό τους τμήμα'), findsOneWidget);
    });

    testWidgets('ένα μόνο τηλέφωνο, χωρίς όνομα: ενικός', (tester) async {
      await ask(tester, ['2741022667'], DepartmentKind.company);

      expect(find.text('Μένει στο παλιό τους τμήμα'), findsOneWidget);
    });

    testWidgets('προς νοσοκομείο: καμία αναγγελία, όλα ρωτιούνται', (
      tester,
    ) async {
      await ask(
        tester,
        ['2986', '2741022667'],
        DepartmentKind.hospital,
        source: 'Αιμοδοσία',
      );

      expect(find.text(_kQuestionTitle), findsOneWidget);
      expect(find.textContaining('δεν ακολουθεί'), findsNothing);
    });

    testWidgets('η απάντηση επιστρέφεται όπως δόθηκε', (tester) async {
      await ask(tester, ['2741022667'], DepartmentKind.company);

      await tester.tap(find.text('Ακολουθεί τον υπάλληλο'));
      await tester.pumpAndSettle();

      expect(answer, BulkTransferAssetFate.follow);
    });
  });

  // Ο κανόνας εμποδίζει κάποιους αριθμούς να μείνουν πίσω (τους κρατά και
  // άλλος υπάλληλος, ή κάθονται ήδη σε τρίτο τμήμα). Ως τις 18/09/2026 ο λόγος
  // υπολογιζόταν και πετιόταν: ο χρήστης απαντούσε «μένουν» και η απάντηση
  // αγνοούνταν σιωπηλά για εκείνον τον αριθμό.
  group('Ό,τι δεν μπορεί να μείνει πίσω, λέγεται πριν την απάντηση', () {
    const blocked =
        'Το 2534 παραμένει στον υπάλληλο Βασιλική Κίτσιου — '
        'το χρησιμοποιεί επίσης: Μαρία Παπαδοπούλου.';

    testWidgets('ο λόγος εμφανίζεται μέσα στην ερώτηση', (tester) async {
      await ask(
        tester,
        ['2534', '6971234567'],
        DepartmentKind.hospital,
        stayBlockedReasons: const [blocked],
      );

      expect(find.text(_kQuestionTitle), findsOneWidget);
      expect(
        find.textContaining('το χρησιμοποιεί επίσης: Μαρία Παπαδοπούλου'),
        findsOneWidget,
        reason:
            'Ο χρήστης πρέπει να ξέρει τι ΔΕΝ πρόκειται να γίνει πριν '
            'διαλέξει, όχι μετά.',
      );
    });

    testWidgets('χωρίς εμπόδια, καμία επιπλέον γραμμή', (tester) async {
      await ask(tester, ['2534', '6971234567'], DepartmentKind.hospital);

      expect(find.text(_kQuestionTitle), findsOneWidget);
      expect(find.textContaining('παραμένει στον υπάλληλο'), findsNothing);
    });

    // Προς εταιρεία τα εσωτερικά δεν ρωτιούνται καθόλου — αλλά ο λόγος
    // εξακολουθεί να αφορά τον χρήστη και πρέπει να ειπωθεί στην ενημέρωση.
    testWidgets('ο λόγος λέγεται και όταν δεν υπάρχει ερώτηση', (tester) async {
      await ask(
        tester,
        ['2534'],
        DepartmentKind.company,
        stayBlockedReasons: const [blocked],
      );

      expect(find.text(_kNoticeTitle), findsOneWidget);
      expect(
        find.textContaining('το χρησιμοποιεί επίσης: Μαρία Παπαδοπούλου'),
        findsOneWidget,
      );
    });
  });
}
