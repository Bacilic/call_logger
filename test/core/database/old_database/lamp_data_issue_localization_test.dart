import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_data_issue_type_labels.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Μηνύματα ελέγχου ακεραιότητας / εισαγωγής για non_numeric_fk · unknown_id
/// (ίδια μορφή με old_equipment_repository / old_excel_importer).
String _integrityFkUserMessage(String column) {
  return 'Η τιμή δεν αντιστοιχεί σε έγκυρο ID για '
      '${lampDataIssueColumnDisplayLabel(column)}.';
}

void main() {
  final repoRoot = Directory.current.path;
  final equipmentRepoPath = p.join(
    repoRoot,
    'lib',
    'core',
    'database',
    'old_database',
    'old_equipment_repository.dart',
  );
  final excelImporterPath = p.join(
    repoRoot,
    'lib',
    'core',
    'database',
    'old_database',
    'old_excel_importer.dart',
  );
  final fkAnalyzerPath = p.join(
    repoRoot,
    'lib',
    'core',
    'database',
    'old_database',
    'lamp_issue_fk_analyzer.dart',
  );
  final manualReviewDialogPath = p.join(
    repoRoot,
    'lib',
    'features',
    'lamp',
    'widgets',
    'lamp_issue_manual_review_dialog.dart',
  );

  group('Λάμπα · εξελληνισμός οδηγού «Μη αριθμητικό Κλειδί Αναφοράς»', () {
    test(
      'αναπαραγωγή: τα αγγλικά ονόματα στηλών υπάρχουν ως κλειδιά χάρτη',
      () {
        // Πρώτα επιβεβαιώνουμε ότι τα αγγλικά identifiers παραμένουν
        // ως κλειδιά (όχι ως εμφανιζόμενο κείμενο).
        expect(lampDataIssueColumnDisplayLabel('office'), 'γραφείο');
        expect(lampDataIssueColumnDisplayLabel('contract'), 'συμβόλαιο');
        expect(
          lampDataIssueColumnDisplayLabel('set_master'),
          'κύριος εξοπλισμός',
        );
      },
    );

    test('μήνυμα ελέγχου για office/contract περιέχει ελληνικές ετικέτες '
        '(όχι office/contract)', () {
      final officeMessage = _integrityFkUserMessage('office');
      expect(officeMessage, contains('γραφείο'));
      expect(officeMessage, isNot(contains('office')));

      final contractMessage = _integrityFkUserMessage('contract');
      expect(contractMessage, contains('συμβόλαιο'));
      expect(contractMessage, isNot(contains('contract')));
    });

    test('πηγές integrity/import χρησιμοποιούν lampDataIssueColumnDisplayLabel '
        'και ελληνικό μήνυμα κύριου εξοπλισμού', () {
      final equipmentRepo = File(equipmentRepoPath).readAsStringSync();
      final excelImporter = File(excelImporterPath).readAsStringSync();

      expect(equipmentRepo, contains('lampDataIssueColumnDisplayLabel'));
      expect(excelImporter, contains('lampDataIssueColumnDisplayLabel'));
      expect(equipmentRepo, isNot(contains('έγκυρο ID για office.')));
      expect(equipmentRepo, isNot(contains(r'έγκυρο ID για $col.')));
      expect(excelImporter, isNot(contains(r'έγκυρο ID για ${fk.column}.')));

      const greekSetMaster =
          'Ο κύριος εξοπλισμός δεν αντιστοιχεί σε έγκυρο κωδικό εξοπλισμού.';
      expect(equipmentRepo, contains(greekSetMaster));
      expect(excelImporter, contains(greekSetMaster));
      expect(
        equipmentRepo,
        isNot(
          contains('Το set_master δεν αντιστοιχεί σε έγκυρο code εξοπλισμού.'),
        ),
      );
      expect(
        excelImporter,
        isNot(
          contains('Το set_master δεν αντιστοιχεί σε έγκυρο code εξοπλισμού.'),
        ),
      );
    });

    test('ετικέτες αποσύνδεσης υπαλλήλου χωρίς original_text / '
        'υπάλληλος_original_text', () {
      final analyzer = File(fkAnalyzerPath).readAsStringSync();

      expect(
        analyzer,
        contains('Αποσύνδεση υπαλλήλου και εκκαθάριση του αρχικού κειμένου'),
      );
      expect(
        analyzer,
        isNot(
          contains(
            'Αποσύνδεση υπαλλήλου και διατήρηση κειμένου στο original_text',
          ),
        ),
      );
      expect(
        analyzer,
        isNot(
          contains('Αποσύνδεση υπαλλήλου και εκκαθάριση owner_original_text'),
        ),
      );
      expect(analyzer, isNot(contains('υπάλληλος_original_text')));
    });

    test(
      'διάλογος χειροκίνητης επισκόπησης δεν διαφθείρει ταυτότητες με replaceAll',
      () {
        final dialog = File(manualReviewDialogPath).readAsStringSync();
        expect(dialog, isNot(contains("replaceAll('owner'")));
        expect(dialog, isNot(contains("replaceAll('last_name'")));
        expect(dialog, isNot(contains("replaceAll('first_name'")));
      },
    );
  });

  group('lampDataIssueMessageDisplayText', () {
    test('παλιό μήνυμα με αγγλικές στήλες εξελληνίζεται', () {
      final text = lampDataIssueMessageDisplayText(
        'Διπλότυπο (model, serial_no): (410, SN-1) σε 2 εγγραφές.',
      );

      expect(text, contains('μοντέλο'));
      expect(text, contains('σειριακός αριθμός'));
      expect(text, isNot(contains('model')));
      expect(text, isNot(contains('serial_no')));
    });

    test('μήνυμα σε μορφή «ετικέτα=τιμή» επιστρέφεται αυτούσιο', () {
      const message =
          'Διπλότυπος συνδυασμός μοντέλου και σειριακού — '
          'μοντέλο=Model A (1) · σειριακός αριθμός=SN-1 · σε 2 εγγραφές.';

      expect(lampDataIssueMessageDisplayText(message), message);
    });

    test('όνομα δεδομένων που συμπίπτει με στήλη δεν αλλοιώνεται', () {
      // Ρεαλιστικό μοντέλο «Microsoft Office»: χωρίς τη δικλείδα θα γινόταν
      // «Microsoft γραφείο».
      const message =
          'Διπλότυπος συνδυασμός μοντέλου και σειριακού — '
          'μοντέλο=Microsoft Office (77) · σειριακός αριθμός=SN-9 · '
          'σε 2 εγγραφές.';

      final text = lampDataIssueMessageDisplayText(message);

      expect(text, contains('Microsoft Office (77)'));
      expect(text, isNot(contains('Microsoft γραφείο')));
    });

    test('κενό ή null μήνυμα δίνει παύλα', () {
      expect(lampDataIssueMessageDisplayText(null), '-');
      expect(lampDataIssueMessageDisplayText('   '), '-');
    });
  });
}
