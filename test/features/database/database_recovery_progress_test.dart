// Οι αργές ανακάμψεις βάσης δείχνουν ότι δουλεύουν.
//
// Οι δύο οθόνες ανάκαμψης κλείνουν τον διάλογο επιλογής και μετά αντιγράφουν
// ολόκληρο το αρχείο ή το ανοίγουν με μετάπτωση. Χωρίς ένδειξη, ο χρήστης
// κοιτά μια οθόνη που δεν σαλεύει — και ξαναπατά.
//
//   flutter test test/features/database/database_recovery_progress_test.dart

import 'dart:async';
import 'dart:io';

import 'package:call_logger/features/database/widgets/database_recovery_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Στήνει μια οθόνη και επιστρέφει context που ζει όσο το τεστ.
  Future<BuildContext> mountHost(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captured = context;
            return const Scaffold(body: Text('οθόνη σφάλματος'));
          },
        ),
      ),
    );
    return captured;
  }

  testWidgets('η ένδειξη μένει όσο τρέχει η δουλειά και φεύγει μετά', (
    tester,
  ) async {
    final context = await mountHost(tester);
    final gate = Completer<String>();

    final result = withDatabaseRecoveryProgress(
      context,
      'Δημιουργείται αντίγραφο της βάσης…',
      () => gate.future,
    );
    await tester.pump();

    expect(find.text('Δημιουργείται αντίγραφο της βάσης…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete('τελείωσε');
    expect(await result, 'τελείωσε');
    await tester.pumpAndSettle();

    expect(find.text('Δημιουργείται αντίγραφο της βάσης…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  // Το κρίσιμο: αν η δουλειά πετάξει και η ένδειξη μείνει, η οθόνη που υπάρχει
  // για να ξεμπλοκάρει την εφαρμογή γίνεται η ίδια το μπλοκάρισμα.
  testWidgets('η ένδειξη φεύγει ΚΑΙ όταν η δουλειά αποτύχει', (tester) async {
    final context = await mountHost(tester);
    final gate = Completer<void>();

    final result = withDatabaseRecoveryProgress(
      context,
      'Υποβαθμίζεται η βάση…',
      () => gate.future,
    );
    await tester.pump();
    expect(find.text('Υποβαθμίζεται η βάση…'), findsOneWidget);

    gate.completeError(StateError('ο δίσκος γέμισε'));
    await expectLater(result, throwsA(isA<StateError>()));
    await tester.pumpAndSettle();

    expect(find.text('Υποβαθμίζεται η βάση…'), findsNothing);
  });

  // Η δουλειά αγγίζει το αρχείο της βάσης: μια ακύρωση στη μέση θα άφηνε
  // μισοτελειωμένο αντίγραφο χωρίς να το ξέρει κανείς.
  testWidgets('η ένδειξη δεν κλείνει με πάτημα έξω από αυτήν', (tester) async {
    final context = await mountHost(tester);
    final gate = Completer<void>();

    final result = withDatabaseRecoveryProgress(
      context,
      'Ελέγχεται η υποβαθμισμένη βάση…',
      () => gate.future,
    );
    await tester.pump();

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(find.text('Ελέγχεται η υποβαθμισμένη βάση…'), findsOneWidget);

    gate.complete();
    await result;
    await tester.pumpAndSettle();
    expect(find.text('Ελέγχεται η υποβαθμισμένη βάση…'), findsNothing);
  });

  testWidgets('η τιμή της δουλειάς επιστρέφεται αυτούσια', (tester) async {
    final context = await mountHost(tester);

    final value = await withDatabaseRecoveryProgress(
      context,
      'Γίνεται κάτι…',
      () async => 42,
    );
    await tester.pumpAndSettle();

    expect(value, 42);
  });

  // Ο βοηθός αξίζει μόνο αν τον περνούν ΟΛΑ τα αργά βήματα. Έλεγχος πηγαίου
  // κώδικα και όχι συμπεριφοράς: το ζητούμενο είναι «ποιος τυλίγει τι»,
  // δηλαδή σύνδεση, όχι υπολογισμός.
  test('κάθε αργό βήμα ανάκαμψης περνά από την ένδειξη', () {
    // Οι σκέτες μορφές που έτρεχαν ως τις 19/09/2026 — καμία δεν επιτρέπεται.
    const bareCalls = <String, List<String>>{
      'lib/features/database/widgets/schema_upgrade_consent_dialog.dart': [
        'await createCopy(',
        'await openAndVerify(',
      ],
      'lib/features/database/widgets/database_newer_recovery_dialog.dart': [
        'await downgradeCopyToAppVersion(',
        'await downgradeDatabaseFileToAppVersion(',
        'await setAndVerifyDatabasePath(',
      ],
    };

    bareCalls.forEach((path, calls) {
      final source = File(
        '${Directory.current.path}${Platform.pathSeparator}'
        '${path.replaceAll('/', Platform.pathSeparator)}',
      ).readAsStringSync();

      expect(
        source.contains('withDatabaseRecoveryProgress('),
        isTrue,
        reason: 'Το «$path» δεν δείχνει καθόλου ότι δουλεύει.',
      );
      for (final call in calls) {
        expect(
          source.contains(call),
          isFalse,
          reason:
              'Το «$path» τρέχει «$call» χωρίς ένδειξη. Σε μεγάλη βάση ή σε '
              'φάκελο δικτύου η οθόνη μένει ακίνητη για δευτερόλεπτα και ο '
              'χρήστης ξαναπατά.',
        );
      }
    });
  });
}
