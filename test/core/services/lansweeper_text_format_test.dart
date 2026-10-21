import 'package:call_logger/core/services/lansweeper_text_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatInlineSolutionSteps', () {
    test('βήματα στη σειρά: κάθε βήμα σε γραμμή, το αποτέλεσμα σε παράγραφο', () {
      expect(
        formatInlineSolutionSteps(
          '1. Εντοπισμός της συντόμευσης της εφαρμογής στην επιφάνεια '
          'εργασίας. 2. Εκτέλεση εκ νέου της εφαρμογής Medico. Η λειτουργία '
          'της εφαρμογής επανήλθε κανονικά.',
        ),
        '1. Εντοπισμός της συντόμευσης της εφαρμογής στην επιφάνεια εργασίας.\n'
        '2. Εκτέλεση εκ νέου της εφαρμογής Medico.\n'
        '\n'
        'Η λειτουργία της εφαρμογής επανήλθε κανονικά.',
      );
    });

    test('χωρίς πρόταση αποτελέσματος δεν προστίθεται κενή παράγραφος', () {
      expect(
        formatInlineSolutionSteps('1. Λήψη του deamon. 2. Επανεκκίνηση.'),
        '1. Λήψη του deamon.\n2. Επανεκκίνηση.',
      );
    });

    test('εισαγωγή πριν από τα βήματα μένει σε δική της γραμμή', () {
      expect(
        formatInlineSolutionSteps('Ενέργειες: 1. Α. 2. Β. 3. Γ.'),
        'Ενέργειες:\n1. Α.\n2. Β.\n3. Γ.',
      );
    });

    test('κείμενο με αλλαγές γραμμής μένει όπως το έστησε ο χρήστης', () {
      const typed = '1. Λήψη.\n2. Επανεκκίνηση. Η εκτύπωση αποκαταστάθηκε.';
      expect(formatInlineSolutionSteps(typed), typed);
    });

    test('ένας μόνο αριθμός μέσα σε πρόταση δεν σπάει το κείμενο', () {
      const plain = 'Εγκατάσταση της έκδοσης 2. Λειτουργεί.';
      expect(formatInlineSolutionSteps(plain), plain);
    });

    test('αρίθμηση που δεν συνεχίζει από το 1 δεν θεωρείται βήματα', () {
      const plain = 'Αλλαγή στο γραφείο 3. Μετά 5. Τέλος.';
      expect(formatInlineSolutionSteps(plain), plain);
    });

    test('η μορφοποίηση δεύτερη φορά δεν αλλάζει τίποτα', () {
      final once = formatInlineSolutionSteps('1. Α. 2. Β. Επανήλθε.');
      expect(formatInlineSolutionSteps(once), once);
    });
  });

  group('lansweeperHtmlText', () {
    test('οι αλλαγές γραμμής φτάνουν ως <br>, και τα Windows \\r\\n', () {
      expect(
        lansweeperHtmlText('1. Α.\r\n2. Β.\n\nΤέλος.'),
        '1. Α.<br>2. Β.<br><br>Τέλος.',
      );
    });

    test('τα σύμβολα με ειδική σημασία δεν γίνονται εντολές μορφής', () {
      expect(lansweeperHtmlText('a < b & c > d'), 'a &lt; b &amp; c &gt; d');
    });
  });
}
