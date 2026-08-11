// Unit test: η κοινή λογική καταχώρησης Lansweeper — ο κανόνας του διπλού
// ticket και το μήνυμα αποτελέσματος, που μοιράζονται και οι τρεις ροές.
//
//   flutter test test/features/history/lansweeper_registration_flow_test.dart

import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_registration_dialogs.dart';
import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_registration_flow.dart';
import 'package:flutter_test/flutter_test.dart';

/// Καταγράφει τι ρωτήθηκε, ώστε τα τεστ να ελέγχουν και τη ΣΕΙΡΑ των ερωτήσεων.
class _ScriptedDialogs {
  _ScriptedDialogs({
    required this.duplicateAnswers,
    this.changeIdAnswers = const [],
  });

  /// Απάντηση του διαλόγου διπλού, ανά κλήση.
  final List<DuplicateTicketAction> duplicateAnswers;

  /// Τι γράφει ο χρήστης στον διάλογο «Αλλαγή Ticket ID», ανά κλήση.
  final List<String?> changeIdAnswers;

  final List<String> duplicateChecks = [];
  final List<String> changeIdPrompts = [];
  int _duplicateIndex = 0;
  int _changeIdIndex = 0;

  Future<DuplicateTicketAction> checkDuplicate(String ticketId) async {
    duplicateChecks.add(ticketId);
    if (_duplicateIndex >= duplicateAnswers.length) {
      fail('Ζητήθηκε έλεγχος διπλού περισσότερες φορές από όσες ορίστηκαν.');
    }
    return duplicateAnswers[_duplicateIndex++];
  }

  Future<String?> askForDifferentId(String currentTicketId) async {
    changeIdPrompts.add(currentTicketId);
    if (_changeIdIndex >= changeIdAnswers.length) {
      fail('Ζητήθηκε νέο id περισσότερες φορές από όσες ορίστηκαν.');
    }
    return changeIdAnswers[_changeIdIndex++];
  }
}

void main() {
  group('resolveTicketIdWithoutDuplicate', () {
    test('κενός υποψήφιος: επιστρέφεται κενό ΧΩΡΙΣ έλεγχο διπλού', () async {
      final dialogs = _ScriptedDialogs(duplicateAnswers: const []);

      final result = await resolveTicketIdWithoutDuplicate(
        candidate: '   ',
        checkDuplicate: dialogs.checkDuplicate,
        askForDifferentId: dialogs.askForDifferentId,
      );

      expect(result, '');
      expect(
        dialogs.duplicateChecks,
        isEmpty,
        reason: 'Καταχώρηση χωρίς ticket δεν μπορεί να είναι διπλή',
      );
    });

    test('μη διπλό: επιστρέφεται ο αριθμός, καθαρισμένος από κενά', () async {
      final dialogs = _ScriptedDialogs(
        duplicateAnswers: const [DuplicateTicketAction.proceed],
      );

      final result = await resolveTicketIdWithoutDuplicate(
        candidate: '  17132  ',
        checkDuplicate: dialogs.checkDuplicate,
        askForDifferentId: dialogs.askForDifferentId,
      );

      expect(result, '17132');
      expect(dialogs.duplicateChecks, ['17132']);
      expect(dialogs.changeIdPrompts, isEmpty);
    });

    test('«Άκυρο» στον διάλογο διπλού: null (καμία σήμανση)', () async {
      final dialogs = _ScriptedDialogs(
        duplicateAnswers: const [DuplicateTicketAction.cancel],
      );

      final result = await resolveTicketIdWithoutDuplicate(
        candidate: '17132',
        checkDuplicate: dialogs.checkDuplicate,
        askForDifferentId: dialogs.askForDifferentId,
      );

      expect(result, isNull);
    });

    test('«Αλλαγή id»: ο νέος αριθμός ελέγχεται και επιστρέφεται', () async {
      final dialogs = _ScriptedDialogs(
        duplicateAnswers: const [
          DuplicateTicketAction.changeId,
          DuplicateTicketAction.proceed,
        ],
        changeIdAnswers: const ['17133'],
      );

      final result = await resolveTicketIdWithoutDuplicate(
        candidate: '17132',
        checkDuplicate: dialogs.checkDuplicate,
        askForDifferentId: dialogs.askForDifferentId,
      );

      expect(result, '17133');
      expect(
        dialogs.duplicateChecks,
        ['17132', '17133'],
        reason: 'Ο νέος αριθμός δεν εξαιρείται από τον έλεγχο',
      );
      expect(
        dialogs.changeIdPrompts,
        ['17132'],
        reason: 'Ο διάλογος αλλαγής ανοίγει με τον τρέχοντα αριθμό',
      );
    });

    test('αλυσιδωτές αλλαγές: ο έλεγχος επαναλαμβάνεται ώσπου να καθαρίσει', () async {
      final dialogs = _ScriptedDialogs(
        duplicateAnswers: const [
          DuplicateTicketAction.changeId,
          DuplicateTicketAction.changeId,
          DuplicateTicketAction.proceed,
        ],
        changeIdAnswers: const ['17133', '17134'],
      );

      final result = await resolveTicketIdWithoutDuplicate(
        candidate: '17132',
        checkDuplicate: dialogs.checkDuplicate,
        askForDifferentId: dialogs.askForDifferentId,
      );

      expect(result, '17134');
      expect(dialogs.duplicateChecks, ['17132', '17133', '17134']);
      expect(dialogs.changeIdPrompts, ['17132', '17133']);
    });

    test('«Άκυρο» στον διάλογο αλλαγής: null (καμία σήμανση)', () async {
      final dialogs = _ScriptedDialogs(
        duplicateAnswers: const [DuplicateTicketAction.changeId],
        changeIdAnswers: const [null],
      );

      final result = await resolveTicketIdWithoutDuplicate(
        candidate: '17132',
        checkDuplicate: dialogs.checkDuplicate,
        askForDifferentId: dialogs.askForDifferentId,
      );

      expect(result, isNull);
    });

    test(
      'σβήσιμο του αριθμού στην αλλαγή: γίνεται δεκτό ως «χωρίς ticket», '
      'χωρίς νέα πρόταση αριθμού',
      () async {
        final dialogs = _ScriptedDialogs(
          duplicateAnswers: const [DuplicateTicketAction.changeId],
          changeIdAnswers: const [''],
        );

        final result = await resolveTicketIdWithoutDuplicate(
          candidate: '17132',
          checkDuplicate: dialogs.checkDuplicate,
          askForDifferentId: dialogs.askForDifferentId,
        );

        expect(result, '');
        expect(
          dialogs.duplicateChecks,
          ['17132'],
          reason: 'Το κενό δεν ξαναελέγχεται για διπλό',
        );
        expect(
          dialogs.changeIdPrompts,
          ['17132'],
          reason: 'Η ρητή επιλογή «χωρίς ticket» δεν ακυρώνεται με νέα ερώτηση',
        );
      },
    );
  });

  group('registrationSuccessMessage', () {
    test('μία κλήση με ticket', () {
      expect(
        registrationSuccessMessage(count: 1, ticketId: '17132'),
        'Η κλήση επισημάνθηκε ως καταχωρημένη (ticket #17132).',
      );
    });

    test('μία κλήση χωρίς ticket: ο αριθμός παραλείπεται εντελώς', () {
      expect(
        registrationSuccessMessage(count: 1, ticketId: ''),
        'Η κλήση επισημάνθηκε ως καταχωρημένη.',
      );
    });

    test('πολλές κλήσεις με ticket', () {
      expect(
        registrationSuccessMessage(count: 4, ticketId: '17132'),
        '4 κλήσεις επισημάνθηκαν ως καταχωρημένες (ticket #17132).',
      );
    });

    test('πολλές κλήσεις χωρίς ticket', () {
      expect(
        registrationSuccessMessage(count: 4, ticketId: ''),
        '4 κλήσεις επισημάνθηκαν ως καταχωρημένες.',
      );
    });
  });
}
