// Widget tests: διάλογος σύγκρουσης τοποθεσίας τηλεφώνου (μετακινούμενος).
//
//   flutter test test/features/directory/screens/widgets/user_phone_department_conflict_dialog_test.dart

import 'package:call_logger/core/directory/phone_department_policy.dart';
import 'package:call_logger/core/widgets/draggable_dialog_shell.dart';
import 'package:call_logger/features/directory/screens/widgets/user_phone_department_conflict_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_reporter.dart';

const _titleText = 'Σύγκρουση τοποθεσίας τηλεφώνου';

PhoneDepartmentConflict _sampleConflict() {
  return const PhoneDepartmentConflict(
    phone: '2511',
    existingDepartmentId: 7,
    existingDepartmentName: 'Αιμοδοσία',
    otherUserOwnerLabels: ['Σοφία Σπυροπούλου (Αιμοδοσία)'],
    hasDepartmentLocationConflict: true,
    hasOtherUserOwners: true,
  );
}

/// Τηλέφωνο που το κρατούν μόνο άλλοι υπάλληλοι (χωρίς κοινόχρηστο τμήματος).
PhoneDepartmentConflict _otherOwnersOnlyConflict({
  List<String> owners = const ['Βασίλης Πρόβος (Φαρμακείο)'],
}) {
  return PhoneDepartmentConflict(
    phone: '2914',
    otherUserOwnerLabels: owners,
    hasDepartmentLocationConflict: false,
    hasOtherUserOwners: true,
  );
}

Future<void> _openConflictDialog(
  WidgetTester tester, {
  PhoneDepartmentConflict? conflict,
  String userDisplayName = 'Φαρμακοποιός 1',
  String targetDepartmentName = 'Φαρμακείο',
  int? targetDepartmentId = 3,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showUserPhoneDepartmentConflictDialog(
                    context,
                    conflicts: [conflict ?? _sampleConflict()],
                    userDisplayName: userDisplayName,
                    targetDepartmentName: targetDepartmentName,
                    targetDepartmentId: targetDepartmentId,
                  );
                },
                child: const Text('Άνοιγμα'),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('Άνοιγμα'));
  await tester.pumpAndSettle();
}

Offset _shellTranslateOffset(WidgetTester tester) {
  // Το κέλυφος έχει το εξωτερικό Transform· το AlertDialog μπορεί να έχει κι άλλα.
  final transforms = tester.widgetList<Transform>(
    find.descendant(
      of: find.byType(DraggableDialogShell),
      matching: find.byType(Transform),
    ),
  );
  final transform = transforms.first;
  final m4 = transform.transform;
  return Offset(m4.storage[12], m4.storage[13]);
}

void main() {
  group('UserPhoneDepartmentConflictDialog · σαφήνεια μηνυμάτων', () {
    testWidgets('η πολιτική διατυπώνεται ως «ένας αριθμός σε ένα τμήμα»', (
      tester,
    ) async {
      await _openConflictDialog(tester);

      expect(
        find.text(
          'Το τμήμα του υπαλλήλου είναι «Φαρμακείο». Τα παρακάτω τηλέφωνα '
          'συγκρούονται με την πολιτική: ένας αριθμός ανήκει μόνο σε ένα '
          'τμήμα. Επιλέξτε ενέργεια ή ακυρώστε.',
        ),
        findsOneWidget,
        reason: greekExpectMsg(
          'Το εισαγωγικό μήνυμα πρέπει να λέει ότι ο αριθμός ανήκει σε ένα '
          'τμήμα, όχι ότι κάθε τμήμα έχει έναν αριθμό',
        ),
      );
    });

    testWidgets(
      'χωρίς τμήμα υπαλλήλου το μήνυμα δεν επικαλείται την πολιτική τμημάτων',
      (tester) async {
        await _openConflictDialog(
          tester,
          conflict: _otherOwnersOnlyConflict(),
          userDisplayName: 'Βασίλης Δροσούλης',
          targetDepartmentName: '',
          targetDepartmentId: null,
        );

        expect(
          find.text(
            'Ο υπάλληλος δεν έχει τμήμα. Επιλέξτε ενέργεια ή ακυρώστε.',
          ),
          findsOneWidget,
          reason: greekExpectMsg(
            'Χωρίς τμήμα, η αναφορά στην πολιτική «ένας αριθμός ανά τμήμα» '
            'είναι άστοχη και παραλείπεται',
          ),
        );
        expect(
          find.textContaining('ένας αριθμός ανήκει μόνο σε ένα τμήμα'),
          findsNothing,
        );
      },
    );

    testWidgets('η ετικέτα ονομάζει κάτοχο και προορισμό με το τμήμα τους', (
      tester,
    ) async {
      await _openConflictDialog(
        tester,
        conflict: _otherOwnersOnlyConflict(),
        userDisplayName: 'Βίκυ Κίτσιου',
        targetDepartmentName: 'Γραφείο Κίνησης',
        targetDepartmentId: 4,
      );

      expect(
        find.text(
          'Αφαίρεση από Βασίλης Πρόβος (Φαρμακείο) και σύνδεση με '
          'Βίκυ Κίτσιου (Γραφείο Κίνησης)',
        ),
        findsOneWidget,
        reason: greekExpectMsg(
          'Η ετικέτα πρέπει να ονομάζει ρητά από ποιον αφαιρείται ο αριθμός '
          'και σε ποιον δίνεται',
        ),
      );
    });

    testWidgets('η μεταφορά κοινόχρηστου δηλώνει και την αφαίρεση κατόχων', (
      tester,
    ) async {
      await _openConflictDialog(tester);

      expect(
        find.text(
          'Αφαίρεση από Αιμοδοσία (κοινόχρηστο) και από '
          'Σοφία Σπυροπούλου (Αιμοδοσία) και σύνδεση με '
          'Φαρμακοποιός 1 (Φαρμακείο)',
        ),
        findsOneWidget,
        reason: greekExpectMsg(
          'Η μεταφορά κοινόχρηστου αφαιρεί και τους άλλους κατόχους — '
          'η ετικέτα οφείλει να το δηλώνει',
        ),
      );
    });

    testWidgets('πάνω από τρεις κάτοχοι συμπτύσσονται σε πλήθος', (
      tester,
    ) async {
      await _openConflictDialog(
        tester,
        conflict: _otherOwnersOnlyConflict(
          owners: const [
            'Άννα Πατσαρίκα (Ακτινολογικό)',
            'Βασίλης Πρόβος (Φαρμακείο)',
            'Γεωργία Παπαγεωργίου (Γραμματεία)',
            'Δήμητρα Νομικού (Αιμοδοσία)',
            'Ελένη Πλακογιάννη (Χειρουργείο)',
          ],
        ),
        userDisplayName: 'Βίκυ Κίτσιου',
        targetDepartmentName: 'Γραφείο Κίνησης',
        targetDepartmentId: 4,
      );

      expect(
        find.text(
          'Αφαίρεση από Άννα Πατσαρίκα (Ακτινολογικό), '
          'Βασίλης Πρόβος (Φαρμακείο), Γεωργία Παπαγεωργίου (Γραμματεία) '
          'και άλλους 2 χρήστες και σύνδεση με Βίκυ Κίτσιου (Γραφείο Κίνησης)',
        ),
        findsOneWidget,
        reason: greekExpectMsg(
          'Με πολλούς κατόχους η ετικέτα δείχνει τρία ονόματα και τους '
          'υπόλοιπους ως πλήθος',
        ),
      );
    });
  });

  group('UserPhoneDepartmentConflictDialog · εικονίδια οντοτήτων', () {
    testWidgets('κοινόχρηστο χωρίς κατόχους δείχνει τμήμα, όχι υπάλληλο', (
      tester,
    ) async {
      await _openConflictDialog(
        tester,
        conflict: const PhoneDepartmentConflict(
          phone: '2511',
          existingDepartmentId: 7,
          existingDepartmentName: 'Αιμοδοσία',
          hasDepartmentLocationConflict: true,
          hasOtherUserOwners: false,
        ),
      );

      expect(
        find.byIcon(Icons.apartment_outlined),
        findsOneWidget,
        reason: greekExpectMsg(
          'Το κοινόχρηστο τηλέφωνο τμήματος δείχνει εικονίδιο τμήματος',
        ),
      );
      expect(
        find.byIcon(Icons.person_outline),
        findsNothing,
        reason: greekExpectMsg(
          'Χωρίς κατόχους-υπαλλήλους δεν εμφανίζεται εικονίδιο υπαλλήλου',
        ),
      );
      expect(find.text('Αιμοδοσία'), findsOneWidget);
    });

    testWidgets('τηλέφωνο μόνο με κατόχους δείχνει υπάλληλο, όχι τμήμα', (
      tester,
    ) async {
      await _openConflictDialog(tester, conflict: _otherOwnersOnlyConflict());

      expect(
        find.byIcon(Icons.person_outline),
        findsOneWidget,
        reason: greekExpectMsg(
          'Οι κάτοχοι-υπάλληλοι δείχνονται με εικονίδιο υπαλλήλου',
        ),
      );
      expect(
        find.byIcon(Icons.apartment_outlined),
        findsNothing,
        reason: greekExpectMsg(
          'Χωρίς κοινόχρηστο τμήματος δεν εμφανίζεται εικονίδιο τμήματος',
        ),
      );
      expect(find.text('Βασίλης Πρόβος (Φαρμακείο)'), findsOneWidget);
    });
  });

  group('UserPhoneDepartmentConflictDialog · μετακίνηση', () {
    testWidgets('τυλίγεται σε DraggableDialogShell με τον τίτλο σύγκρουσης', (
      tester,
    ) async {
      await _openConflictDialog(tester);

      expect(
        find.byType(DraggableDialogShell),
        findsOneWidget,
        reason: greekExpectMsg(
          'Ο διάλογος σύγκρουσης πρέπει να χρησιμοποιεί DraggableDialogShell',
        ),
      );
      expect(find.text(_titleText), findsOneWidget);
      expect(
        _shellTranslateOffset(tester),
        Offset.zero,
        reason: greekExpectMsg('Αρχική μετατόπιση μηδενική'),
      );
    });

    testWidgets('σύρσιμο από τον τίτλο μετακινεί τον διάλογο σύγκρουσης', (
      tester,
    ) async {
      await _openConflictDialog(tester);

      const delta = Offset(40, 28);
      await tester.drag(find.text(_titleText), delta);
      await tester.pump();

      final offset = _shellTranslateOffset(tester);
      expect(
        offset.dx,
        closeTo(delta.dx, 0.5),
        reason: greekExpectMsg(
          'Το σύρσιμο από τον τίτλο πρέπει να μετακινεί τον διάλογο',
        ),
      );
      expect(
        offset.dy,
        closeTo(delta.dy, 0.5),
        reason: greekExpectMsg(
          'Το σύρσιμο από τον τίτλο πρέπει να μετακινεί τον διάλογο',
        ),
      );
    });
  });
}
