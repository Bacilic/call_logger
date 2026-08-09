// Οι υποδείξεις κανόνων της γρήγορης καταχώρησης ζουν μέσα στην περιγραφή
// της εκκρεμότητας, σε δικές τους γραμμές.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/tasks/quick_add_validation_hints_test.dart

import 'package:call_logger/features/tasks/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

Task _taskWithDescription(String description) {
  return Task(
    title: 'Γρήγορη προσθήκη',
    description: description,
    dueDate: '2026-08-07 12:00:00',
    status: 'open',
  );
}

/// Περιγραφή όπως τη χτίζει η γρήγορη καταχώρηση με υποδείξεις.
String _quickAddDescriptionWith(List<String> hints) {
  const core = 'Προσθήκη νέου καλούντα: 3π με τηλέφωνο: 3122 στο τμήμα: 2545';
  if (hints.isEmpty) return '${Task.quickAddTag} $core';
  final block = hints.map((h) => '${Task.validationHintPrefix}$h').join('\n');
  return '${Task.quickAddTag} $core\n${Task.validationHintHeader}\n$block';
}

void main() {
  group('cleanDescription — οι γραμμές υποδείξεων επιβιώνουν', () {
    test('οι αλλαγές γραμμής ΔΕΝ συμπτύσσονται', () {
      final task = _taskWithDescription(
        _quickAddDescriptionWith([
          'Τηλέφωνο — Το 3122 δεν ξεκινά από 22–29',
          'Τμήμα — Το «2545» μοιάζει με αριθμό ή τηλέφωνο',
        ]),
      );
      final lines = task.cleanDescription.split('\n');
      expect(
        lines.length,
        4,
        reason: greekExpectMsg(
          'Περιγραφή + επικεφαλίδα + δύο υποδείξεις = τέσσερις γραμμές',
        ),
      );
      expect(lines.first, startsWith('Προσθήκη νέου καλούντα'));
      expect(lines[1], Task.validationHintHeader);
    });

    test('η εσωτερική ετικέτα αφαιρείται', () {
      final task = _taskWithDescription(_quickAddDescriptionWith(const []));
      expect(task.cleanDescription.contains(Task.quickAddTag), isFalse);
      expect(task.isQuickAdd, isTrue);
    });

    test('τα πολλαπλά κενά μέσα στη γραμμή εξακολουθούν να καθαρίζονται', () {
      final task = _taskWithDescription(
        '${Task.quickAddTag}   Προσθήκη    νέου   καλούντα',
      );
      expect(task.cleanDescription, 'Προσθήκη νέου καλούντα');
    });
  });

  group('validationHintLines — ανάγνωση των υποδείξεων', () {
    test('επιστρέφει τις γραμμές χωρίς το πρόθεμα', () {
      final task = _taskWithDescription(
        _quickAddDescriptionWith([
          'Όνομα — Ξεκινά από ψηφίο ή σύμβολο',
          'Τηλέφωνο — Το 3122 δεν ξεκινά από 22–29',
        ]),
      );
      expect(task.validationHintLines, [
        'Όνομα — Ξεκινά από ψηφίο ή σύμβολο',
        'Τηλέφωνο — Το 3122 δεν ξεκινά από 22–29',
      ]);
    });

    test('καθαρή καταχώρηση: καμία γραμμή υπόδειξης', () {
      final task = _taskWithDescription(_quickAddDescriptionWith(const []));
      expect(task.validationHintLines, isEmpty);
    });

    test('εκκρεμότητα χωρίς περιγραφή δεν σκάει', () {
      final task = Task(
        title: 'Χωρίς περιγραφή',
        dueDate: '2026-08-07 12:00:00',
        status: 'open',
      );
      expect(task.cleanDescription, '');
      expect(task.validationHintLines, isEmpty);
    });

    test('κανονική εκκρεμότητα κλήσης δεν επηρεάζεται', () {
      final task = _taskWithDescription('Ο εκτυπωτής δεν τυπώνει');
      expect(task.validationHintLines, isEmpty);
      expect(task.cleanDescription, 'Ο εκτυπωτής δεν τυπώνει');
    });
  });

  group('withQuickAddTag — ο δείκτης κρύβεται και επιστρέφει', () {
    test(
      'η φόρμα δείχνει καθαρό κείμενο και η αποθήκευση το ξανασφραγίζει',
      () {
        final stored = _taskWithDescription(_quickAddDescriptionWith(const []));

        // Ό,τι βλέπει ο χρήστης στη φόρμα.
        final shown = stored.cleanDescription;
        expect(shown, isNot(contains(Task.quickAddTag)));

        // Ό,τι γράφεται πίσω μετά από επεξεργασία.
        final saved = Task.withQuickAddTag('$shown — συμπλήρωση');
        expect(saved, startsWith(Task.quickAddTag));

        final reloaded = _taskWithDescription(saved!);
        expect(
          reloaded.isQuickAdd,
          isTrue,
          reason:
              'Χωρίς τον δείκτη θα χάνονταν τα κουμπιά γρήγορης επεξεργασίας',
        );
        expect(reloaded.cleanDescription, endsWith('συμπλήρωση'));
      },
    );

    test('δεν διπλασιάζει δείκτη που υπάρχει ήδη', () {
      final withTag = '${Task.quickAddTag} Κείμενο';
      expect(Task.withQuickAddTag(withTag), withTag);
    });

    test('άδεια περιγραφή κρατά μόνο τον δείκτη', () {
      expect(Task.withQuickAddTag(''), Task.quickAddTag);
      expect(Task.withQuickAddTag(null), Task.quickAddTag);
    });

    test('οι υποδείξεις επιβιώνουν του κύκλου κρύψιμο → αποθήκευση', () {
      final stored = _taskWithDescription(
        _quickAddDescriptionWith(const [
          'Τηλέφωνο — Το 3122 δεν ξεκινά από 22–29',
        ]),
      );

      final roundTripped = _taskWithDescription(
        Task.withQuickAddTag(stored.cleanDescription)!,
      );

      expect(roundTripped.validationHintLines, hasLength(1));
      expect(
        roundTripped.validationHintLines.single,
        'Τηλέφωνο — Το 3122 δεν ξεκινά από 22–29',
      );
    });
  });
}
