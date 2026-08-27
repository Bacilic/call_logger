// Τι λέει ο διάλογος αποτυχίας αντιγράφου — και τι ΔΕΝ λέει πια.
//
// Το συμβόλαιο: «Η αποτυχία ενός αντιγράφου φτάνει στον χρήστη με την αιτία
// της, τη διαδρομή της και μια διέξοδο — μία φορά.» Πριν, το μήνυμα ήταν
// «ελέγξτε τον φάκελο προορισμού και τα δικαιώματα»: ζητούσε από τον άνθρωπο
// έναν έλεγχο που η ίδια η εφαρμογή ξέρει να κάνει, και δεν κατονόμαζε καν
// τον φάκελο.
//
//   flutter test test/features/database/backup_failed_dialog_test.dart

import 'package:call_logger/features/database/utils/backup_destination_folder_validator.dart';
import 'package:call_logger/features/database/utils/backup_schedule_utils.dart';
import 'package:call_logger/features/database/widgets/backup_failed_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

const _dest = r'\\server\backups\call_logger';

String _explain(BackupDestinationValidationKind kind, {String dest = _dest}) =>
    backupFailureExplanation(destination: dest, kind: kind);

void main() {
  group('Η εξήγηση κατονομάζει τον φάκελο', () {
    test('η διαδρομή εμφανίζεται πάντα, όποια κι αν είναι η αιτία', () {
      for (final kind in BackupDestinationValidationKind.values) {
        expect(
          _explain(kind),
          contains(_dest),
          reason: 'Χωρίς τη διαδρομή, ο χρήστης δεν ξέρει τι να κοιτάξει.',
        );
      }
    });

    test('χωρίς ορισμένο φάκελο, το λέει αντί να δείχνει κενή διαδρομή', () {
      final text = _explain(
        BackupDestinationValidationKind.missingDirectory,
        dest: '   ',
      );

      expect(text, contains('Δεν έχει οριστεί φάκελος'));
      expect(text, isNot(contains('Φάκελος προορισμού:')));
    });
  });

  group('Η εξήγηση λέει ΤΙ φταίει, χωρίς να ρωτά τον χρήστη', () {
    test('δεν ζητά από τον χρήστη τον έλεγχο που κάναμε ήδη', () {
      for (final kind in BackupDestinationValidationKind.values) {
        expect(
          _explain(kind).toLowerCase(),
          isNot(contains('ελέγξτε')),
          reason: 'Ο έλεγχος έγινε ζωντανά· δεν ανατίθεται στον χρήστη.',
        );
      }
    });

    test('φάκελος που λείπει: το λέει και δίνει πιθανή αιτία', () {
      final text = _explain(BackupDestinationValidationKind.missingDirectory);

      expect(text, contains('δεν υπάρχει'));
      expect(text, contains('αποσυνδεδεμένος δίσκος'));
    });

    test('άρνηση πρόσβασης: ξεχωρίζει από τον φάκελο που λείπει', () {
      final denied = _explain(BackupDestinationValidationKind.accessDenied);

      expect(denied, contains('δικαίωμα εγγραφής'));
      expect(denied, isNot(contains('δεν υπάρχει')));
    });

    test('διαδρομή προς αρχείο: το λέει ρητά', () {
      expect(
        _explain(BackupDestinationValidationKind.notADirectory),
        contains('αρχείο, όχι σε φάκελο'),
      );
    });

    test('φάκελος εντάξει: ΔΕΝ εφευρίσκει αιτία που δεν ξέρει', () {
      final text = _explain(BackupDestinationValidationKind.ok);

      expect(text, contains('προσβάσιμος'));
      expect(text, contains('κάτι άλλο'));
      // Δεν ισχυρίζεται πρόβλημα φακέλου εκεί που δεν υπάρχει.
      expect(text, isNot(contains('δεν υπάρχει')));
      expect(text, isNot(contains('δικαίωμα')));
    });

    test(
      'κάθε αιτία δίνει διαφορετικό κείμενο — καμία δεν είναι γενικόλογη',
      () {
        final texts = BackupDestinationValidationKind.values
            .map((k) => _explain(k))
            .toSet();

        expect(texts.length, BackupDestinationValidationKind.values.length);
      },
    );
  });

  group('Οι επιλογές του χρήστη', () {
    test('υπάρχει διέξοδος, όχι μόνο «ξαναδοκίμασε» και «άσ το»', () {
      expect(
        BackupFailedChoice.values,
        containsAll(<BackupFailedChoice>[
          BackupFailedChoice.ignore,
          BackupFailedChoice.runNow,
          BackupFailedChoice.changeFolder,
        ]),
      );
    });
  });

  group('Μία ειδοποίηση ανά αποτυχία, όχι δύο', () {
    bool announce(String? previous, String current) =>
        BackupScheduleStatus.shouldAnnounce(
          previous: previous,
          current: current,
        );

    test('η αναβάθμιση «απέτυχε» → «λείπει ο φάκελος» ΔΕΝ ξαναρωτά', () {
      // Ο περιοδικός έλεγχος βαφτίζει την ίδια αποτυχία· ο χρήστης έχει ήδη
      // δει τον διάλογο.
      expect(
        announce(
          BackupScheduleStatus.failed,
          BackupScheduleStatus.folderMissing,
        ),
        isFalse,
      );
    });

    test('πρώτη αποτυχία: ειδοποιεί', () {
      expect(
        announce(BackupScheduleStatus.none, BackupScheduleStatus.failed),
        isTrue,
      );
      expect(announce(null, BackupScheduleStatus.folderMissing), isTrue);
      expect(
        announce(BackupScheduleStatus.success, BackupScheduleStatus.failed),
        isTrue,
      );
    });

    test('η επιτυχία δεν διακόπτει ποτέ τον χρήστη', () {
      expect(
        announce(BackupScheduleStatus.failed, BackupScheduleStatus.success),
        isFalse,
      );
      expect(
        announce(BackupScheduleStatus.failed, BackupScheduleStatus.none),
        isFalse,
      );
    });

    test('ίδια κατάσταση δύο φορές: μία ειδοποίηση', () {
      expect(
        announce(BackupScheduleStatus.failed, BackupScheduleStatus.failed),
        isFalse,
      );
    });

    test('νέα αποτυχία μετά από επιτυχία ειδοποιεί ξανά', () {
      // Καθάρισε στο μεταξύ — αυτό είναι ΑΛΛΟ συμβάν.
      expect(
        announce(
          BackupScheduleStatus.success,
          BackupScheduleStatus.folderMissing,
        ),
        isTrue,
      );
    });
  });
}
