// Μηνύματα διαγραφής υπαλλήλου — καθαρές συναρτήσεις.
//
//   flutter test test/features/directory/user_deletion_messages_test.dart

import 'package:call_logger/features/directory/services/user_deletion_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('employeeDisplayLabel', () {
    test('(β) χωρίς τμήμα → μόνο όνομα', () {
      expect(employeeDisplayLabel('Αναστασία Φούφα', null), 'Αναστασία Φούφα');
      expect(employeeDisplayLabel('Αναστασία Φούφα', '  '), 'Αναστασία Φούφα');
    });

    test('με τμήμα → Όνομα (Τμήμα)', () {
      expect(
        employeeDisplayLabel('Αναστασία Φούφα', 'Προμήθειες'),
        'Αναστασία Φούφα (Προμήθειες)',
      );
    });
  });

  group('userDeletionConfirmMessage', () {
    test('(α) 1 υπάλληλος', () {
      expect(
        userDeletionConfirmMessage(['Αναστασία Φούφα (Προμήθειες)']),
        'Διαγραφή υπαλλήλου «Αναστασία Φούφα (Προμήθειες)»;',
      );
      expect(userDeletionConfirmTitle(1), 'Διαγραφή υπαλλήλου');
    });

    test('(α) 2–5 υπάλληλοι με λίστα', () {
      final msg = userDeletionConfirmMessage(['Α (Τ1)', 'Β (Τ2)', 'Γ']);
      expect(msg.startsWith('Διαγραφή 3 υπαλλήλων:'), isTrue);
      expect(msg, contains('• Α (Τ1)'));
      expect(msg, contains('• Β (Τ2)'));
      expect(msg, contains('• Γ'));
      expect(userDeletionConfirmTitle(3), 'Διαγραφή υπαλλήλων');
    });

    test('(α) >5 → μόνο πλήθος', () {
      final labels = List.generate(6, (i) => 'Υ$i (Τ)');
      expect(userDeletionConfirmMessage(labels), 'Διαγραφή 6 υπαλλήλων;');
    });
  });

  group('Διακοπή στη μέση — τι ολοκληρώθηκε', () {
    test('ένας ολοκληρωμένος: ενικός', () {
      expect(
        userDeletionCompletedSummary(completed: 1, total: 9),
        'Ολοκληρώσατε 1 υπάλληλο από τους 9.',
      );
      expect(
        userDeletionApplyCompletedHint(1),
        'Κλείνει ο οδηγός και διαγράφεται ο 1 υπάλληλος που ολοκληρώσατε. Οι '
        'υπόλοιποι μένουν ανέγγιχτοι και επιλεγμένοι.',
      );
    });

    test('πολλοί ολοκληρωμένοι: πληθυντικός', () {
      expect(
        userDeletionCompletedSummary(completed: 3, total: 9),
        'Ολοκληρώσατε 3 υπαλλήλους από τους 9.',
      );
      expect(
        userDeletionApplyCompletedHint(3),
        'Κλείνει ο οδηγός και διαγράφονται οι 3 υπάλληλοι που ολοκληρώσατε. '
        'Οι υπόλοιποι μένουν ανέγγιχτοι και επιλεγμένοι.',
      );
    });
  });

  group('userDeletionSummaryMessage', () {
    test('(γ)(δ) ονόματα + ενέργειες με αναγνωριστικά', () {
      final msg = userDeletionSummaryMessage(
        employeeNames: ['Αναστασία Φούφα'],
        assetActions: const [
          UserDeletionAssetAction(
            kind: UserDeletionAssetActionKind.transfer,
            identifier: '2896',
            isPhone: true,
          ),
          UserDeletionAssetAction(
            kind: UserDeletionAssetActionKind.delete,
            identifier: '3874',
            isPhone: false,
          ),
        ],
      );
      expect(
        msg,
        'Διαγράφηκε Αναστασία Φούφα · μετακίνηση τηλεφώνου (2896) · '
        'διαγραφή εξοπλισμού (3874)',
      );
    });

    test('(δ) παραμονή ονοματίζει το αναγνωριστικό', () {
      final msg = userDeletionSummaryMessage(
        employeeNames: ['Νίκος'],
        assetActions: const [
          UserDeletionAssetAction(
            kind: UserDeletionAssetActionKind.keep,
            identifier: '2310',
            isPhone: true,
          ),
        ],
      );
      expect(msg, 'Διαγράφηκε Νίκος · παραμονή τηλεφώνου (2310)');
      expect(msg, isNot(contains('τηλεφώνων')));
    });

    test('πολλοί υπάλληλοι χωρίς ενέργειες', () {
      expect(
        userDeletionSummaryMessage(
          employeeNames: ['Α', 'Β'],
          assetActions: const [],
        ),
        'Διαγράφηκαν Α, Β',
      );
    });
  });

  group('Τμήμα που έμεινε κενό μετά τη διαγραφή', () {
    test('κανένα κενό τμήμα: καμία προσθήκη στο μήνυμα', () {
      expect(emptiedDepartmentsNotice(const []), isNull);
      expect(
        userDeletionSummaryMessage(
          employeeNames: ['Κόλια Μαρία'],
          assetActions: const [],
        ),
        'Διαγράφηκε Κόλια Μαρία',
      );
    });

    test('κενά ονόματα αγνοούνται — δεν παράγεται μήνυμα-φάντασμα', () {
      expect(emptiedDepartmentsNotice(const ['', '   ']), isNull);
    });

    test('ένα τμήμα: ενικός', () {
      expect(
        emptiedDepartmentsNotice(const ['Ακτινολογικό']),
        'Το τμήμα «Ακτινολογικό» έμεινε χωρίς κανένα εξάρτημα',
      );
    });

    test('δύο τμήματα: πληθυντικός με εισαγωγικά στο καθένα', () {
      expect(
        emptiedDepartmentsNotice(const ['Ακτινολογικό', 'Μαγειρείο']),
        'Τα τμήματα «Ακτινολογικό», «Μαγειρείο» έμειναν χωρίς κανένα εξάρτημα',
      );
    });

    test('το σενάριο της Κόλια Μαρίας: μπαίνει στο τέλος του snackbar', () {
      final msg = userDeletionSummaryMessage(
        employeeNames: ['Κόλια Μαρία'],
        assetActions: const [
          UserDeletionAssetAction(
            kind: UserDeletionAssetActionKind.delete,
            identifier: '3874',
            isPhone: false,
          ),
        ],
        emptiedDepartments: const ['Ακτινολογικό'],
      );
      expect(
        msg,
        'Διαγράφηκε Κόλια Μαρία · διαγραφή εξοπλισμού (3874) · '
        'Το τμήμα «Ακτινολογικό» έμεινε χωρίς κανένα εξάρτημα',
      );
    });

    test('χωρίς ενέργειες στοιχείων το μήνυμα παραμένει διαβάσιμο', () {
      expect(
        userDeletionSummaryMessage(
          employeeNames: ['Κόλια Μαρία'],
          assetActions: const [],
          emptiedDepartments: const ['Ακτινολογικό'],
        ),
        'Διαγράφηκε Κόλια Μαρία · '
        'Το τμήμα «Ακτινολογικό» έμεινε χωρίς κανένα εξάρτημα',
      );
    });
  });
}
