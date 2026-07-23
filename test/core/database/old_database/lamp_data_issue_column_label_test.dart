import 'package:call_logger/core/database/old_database/lamp_data_issue_type_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lampDataIssueColumnDisplayLabel', () {
    test('null επιστρέφει «-»', () {
      expect(lampDataIssueColumnDisplayLabel(null), '-');
    });

    test('κενό επιστρέφει «-»', () {
      expect(lampDataIssueColumnDisplayLabel(''), '-');
      expect(lampDataIssueColumnDisplayLabel('   '), '-');
    });

    test('άγνωστη στήλη επιστρέφει το όνομα ως έχει', () {
      expect(lampDataIssueColumnDisplayLabel('foo'), 'foo');
    });

    test('χάρτης 9 πεδίων — βασικά ονόματα', () {
      expect(lampDataIssueColumnDisplayLabel('office'), 'γραφείο');
      expect(lampDataIssueColumnDisplayLabel('owner'), 'υπάλληλος');
      expect(lampDataIssueColumnDisplayLabel('model'), 'μοντέλο');
      expect(lampDataIssueColumnDisplayLabel('contract'), 'συμβόλαιο');
      expect(lampDataIssueColumnDisplayLabel('set_master'), 'κύριος εξοπλισμός');
      expect(lampDataIssueColumnDisplayLabel('asset_no'), 'αριθμός παγίου');
      expect(lampDataIssueColumnDisplayLabel('serial_no'), 'σειριακός αριθμός');
      expect(lampDataIssueColumnDisplayLabel('ip_address'), 'διεύθυνση IP');
      expect(lampDataIssueColumnDisplayLabel('network_name'), 'όνομα δικτύου');
    });

    test('case-insensitive (π.χ. OFFICE → γραφείο)', () {
      expect(lampDataIssueColumnDisplayLabel('OFFICE'), 'γραφείο');
      expect(lampDataIssueColumnDisplayLabel(' Asset_No '), 'αριθμός παγίου');
    });
  });

  group('lampDataIssueMessageDisplayText', () {
    test('παλιά μηνύματα office/contract → γραφείο/συμβόλαιο', () {
      expect(
        lampDataIssueMessageDisplayText(
          'Η τιμή δεν αντιστοιχεί σε έγκυρο ID για office.',
        ),
        'Η τιμή δεν αντιστοιχεί σε έγκυρο ID για γραφείο.',
      );
      expect(
        lampDataIssueMessageDisplayText(
          'Η τιμή δεν αντιστοιχεί σε έγκυρο ID για contract.',
        ),
        'Η τιμή δεν αντιστοιχεί σε έγκυρο ID για συμβόλαιο.',
      );
    });

    test('set_master / code → κύριος εξοπλισμός / κωδικό', () {
      expect(
        lampDataIssueMessageDisplayText(
          'Το set_master δεν αντιστοιχεί σε έγκυρο code εξοπλισμού.',
        ),
        contains('κύριος εξοπλισμός'),
      );
      expect(
        lampDataIssueMessageDisplayText(
          'Το set_master δεν αντιστοιχεί σε έγκυρο code εξοπλισμού.',
        ),
        contains('κωδικό'),
      );
      expect(
        lampDataIssueMessageDisplayText(
          'Το set_master δεν αντιστοιχεί σε έγκυρο code εξοπλισμού.',
        ),
        isNot(contains('set_master')),
      );
    });
  });
}
