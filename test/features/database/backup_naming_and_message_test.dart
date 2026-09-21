// Τα δύο καθαρά κομμάτια της δημιουργίας αντιγράφου, τεστάριστα χωριστά.
//
// Ως τη διάσπαση της 19/09 ζούσαν και τα δύο μέσα σε μέθοδο 210 γραμμών που
// χρειαζόταν ανοιχτή βάση, ρυθμίσεις και δίσκο για να τρέξει — οπότε δεν
// υπήρχε τρόπος να ρωτηθεί «πώς θα λέγεται το αρχείο;» ή «τι θα πει το
// μήνυμα;» χωρίς να γίνει πραγματικό αντίγραφο. Γι' αυτό ακριβώς το μήνυμα
// είχε καταφέρει να λέει ψέματα για τη βάση Λάμπας.
//
//   flutter test test/features/database/backup_naming_and_message_test.dart

import 'package:call_logger/features/database/models/database_backup_settings.dart';
import 'package:call_logger/features/database/services/backup_artifact_naming.dart';
import 'package:call_logger/features/database/services/backup_completion_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('η κρίση ενός φορητού κομματιού', () {
    PortablePartVerdict judge(int added, int failed) => judgePortablePart(
      label: 'εικόνες χαρτών',
      emptyReason: 'δεν βρέθηκε καμία',
      outcome: PortablePartOutcome(added: added, failed: failed),
    );

    test('μπήκαν όλα → σκέτο στα περιεχόμενα', () {
      final verdict = judge(4, 0);

      expect(verdict.included, 'εικόνες χαρτών');
      expect(verdict.missing, isNull);
    });

    test('μπήκαν κάποια → στα περιεχόμενα, με τον αριθμό όσων λείπουν', () {
      final verdict = judge(4, 2);

      expect(verdict.included, 'εικόνες χαρτών (2 αρχεία δεν μπήκαν)');
      expect(
        verdict.missing,
        isNull,
        reason: 'το κομμάτι υπάρχει μέσα — απλώς όχι ολόκληρο',
      );
    });

    test('δεν μπήκε κανένα από όσα υπήρχαν → στα ελλείποντα', () {
      final verdict = judge(0, 3);

      expect(verdict.included, isNull);
      expect(verdict.missing, 'εικόνες χαρτών (3 αρχεία δεν διαβάστηκαν)');
    });

    test('δεν υπήρχε τίποτα → λέγεται, με τον δικό του λόγο', () {
      final verdict = judge(0, 0);

      expect(verdict.included, isNull);
      expect(
        verdict.missing,
        'εικόνες χαρτών (δεν βρέθηκε καμία)',
        reason: 'ο χρήστης το ζήτησε· μπορεί να σημαίνει ότι κάτι χάθηκε',
      );
    });

    test('ένα μόνο αρχείο δεν γράφεται στον πληθυντικό', () {
      expect(judge(2, 1).included, 'εικόνες χαρτών (1 αρχείο δεν μπήκε)');
      expect(judge(0, 1).missing, 'εικόνες χαρτών (1 αρχείο δεν διαβάστηκε)');
    });

    test('κάθε κομμάτι μιλά τη δική του γλώσσα όταν λείπει', () {
      expect(
        judgePortablePart(
          label: 'λεξικό',
          emptyReason: 'δεν βρέθηκε αρχείο λεξικού',
          outcome: const PortablePartOutcome.nothingFound(),
        ).missing,
        'λεξικό (δεν βρέθηκε αρχείο λεξικού)',
      );
    });
  });

  group('ονοματοδοσία αντιγράφου', () {
    final moment = DateTime(2026, 9, 19, 14, 5);

    test('η ώρα μπροστά, όπως στην προτεινόμενη μορφή', () {
      final paths = resolveBackupArtifactPaths(
        destinationDirectory: r'D:\backups',
        baseName: 'call_logger_hosp',
        namingFormat: DatabaseBackupNamingFormat.dateTimeThenBase,
        now: moment,
      );

      expect(paths.stem, '2026-09-19_14-05_call_logger_hosp');
      expect(
        p.basename(paths.databasePath),
        '2026-09-19_14-05_call_logger_hosp.db',
      );
    });

    test('το όνομα της βάσης μπροστά, στην εναλλακτική μορφή', () {
      final paths = resolveBackupArtifactPaths(
        destinationDirectory: r'D:\backups',
        baseName: 'call_logger_hosp',
        namingFormat: DatabaseBackupNamingFormat.baseThenDateTime,
        now: moment,
      );

      expect(paths.stem, 'call_logger_hosp_2026-09-19_14-05');
    });

    test('το .db και το .zip μοιράζονται το ίδιο όνομα', () {
      final paths = resolveBackupArtifactPaths(
        destinationDirectory: r'D:\backups',
        baseName: 'base',
        namingFormat: DatabaseBackupNamingFormat.dateTimeThenBase,
        now: moment,
      );

      expect(
        p.basenameWithoutExtension(paths.databasePath),
        p.basenameWithoutExtension(paths.archivePath),
      );
      expect(p.extension(paths.databasePath), '.db');
      expect(p.extension(paths.archivePath), '.zip');
    });

    test('και τα δύο κάθονται στον φάκελο προορισμού', () {
      final paths = resolveBackupArtifactPaths(
        destinationDirectory: r'D:\backups\nightly',
        baseName: 'base',
        namingFormat: DatabaseBackupNamingFormat.dateTimeThenBase,
        now: moment,
      );

      expect(p.dirname(paths.databasePath), p.normalize(r'D:\backups\nightly'));
      expect(p.dirname(paths.archivePath), p.normalize(r'D:\backups\nightly'));
    });

    test('η χρονοσφραγίδα ταξινομείται αλφαβητικά κατά χρόνο', () {
      final earlier = formatBackupStamp(DateTime(2026, 9, 19, 9, 5));
      final later = formatBackupStamp(DateTime(2026, 9, 19, 14, 5));

      expect(earlier.compareTo(later), lessThan(0));
    });
  });

  group('μήνυμα ολοκλήρωσης', () {
    test('πλήρες αντίγραφο απαριθμεί ό,τι μπήκε', () {
      final message = buildBackupCompletionMessage(
        isFull: true,
        wantsBundle: true,
        includedParts: const ['εικόνες χαρτών', 'λεξικό'],
        missingParts: const [],
      );

      expect(message, contains('πλήρες'));
      expect(message, contains('εικόνες χαρτών, λεξικό'));
      expect(message, isNot(contains('Δεν μπήκε')));
    });

    test('ό,τι δεν μπήκε αναφέρεται ρητά', () {
      final message = buildBackupCompletionMessage(
        isFull: true,
        wantsBundle: true,
        includedParts: const ['λεξικό'],
        missingParts: const ['βάση Λάμπας (κλειδωμένο αρχείο)'],
      );

      expect(message, contains('λεξικό'));
      expect(message, contains('Δεν μπήκε: βάση Λάμπας (κλειδωμένο αρχείο).'));
    });

    test('ό,τι δεν μπήκε ΔΕΝ εμφανίζεται ως περιεχόμενο', () {
      final message = buildBackupCompletionMessage(
        isFull: true,
        wantsBundle: true,
        includedParts: const [],
        missingParts: const ['βάση Λάμπας (δεν βρέθηκε το αρχείο της)'],
      );

      // Το σφάλμα που γέννησε αυτό το τεστ: η λίστα περιεχομένων χτιζόταν από
      // τις ρυθμίσεις, οπότε έγραφε «(βάση Λάμπας)» για κάτι που έλειπε.
      expect(message, isNot(contains('ολοκληρώθηκε (')));
      expect(message, contains('Δεν μπήκε'));
    });

    test('γρήγορο αντίγραφο εξηγεί γιατί δεν πήρε τα φορητά', () {
      final message = buildBackupCompletionMessage(
        isFull: false,
        wantsBundle: true,
        includedParts: const [],
        missingParts: const [],
      );

      expect(message, contains('γρήγορο'));
      expect(message, contains('δεν'));
    });

    test('χωρίς αίτημα φορητών, το μήνυμα μένει σκέτο', () {
      final message = buildBackupCompletionMessage(
        isFull: false,
        wantsBundle: false,
        includedParts: const [],
        missingParts: const [],
      );

      expect(message, 'Το αντίγραφο ολοκληρώθηκε.');
    });

    test('πολλές παραλείψεις χωρίζονται καθαρά', () {
      final message = buildBackupCompletionMessage(
        isFull: true,
        wantsBundle: true,
        includedParts: const [],
        missingParts: const ['βάση Λάμπας (α)', 'εκκαθάριση παλαιών (β)'],
      );

      expect(message, contains('βάση Λάμπας (α)· εκκαθάριση παλαιών (β).'));
    });
  });

  group('μήνυμα χαλασμένου αντιγράφου', () {
    test('λέει την αιτία, την τύχη του αρχείου και το ωμό σφάλμα', () {
      final message = buildBrokenBackupMessage(
        reason: 'Η βάση μέσα στο αντίγραφο είναι χαλασμένη.',
        wasMarked: true,
        rawDetail: 'SqliteException(11): database disk image is malformed',
      );

      expect(message, startsWith('Η βάση μέσα στο αντίγραφο είναι χαλασμένη.'));
      expect(message, contains('σημαδεύτηκε ως χαλασμένο'));
      expect(message, contains('malformed'));
    });

    test('όταν η μετονομασία δεν έγινε, το λέει', () {
      final message = buildBrokenBackupMessage(
        reason: 'Το αντίγραφο δεν αποσυμπιέζεται.',
        wasMarked: false,
        rawDetail: null,
      );

      expect(message, contains('έμεινε ως έχει'));
      expect(message, isNot(contains('σημαδεύτηκε')));
    });

    test('χωρίς αιτία, μπαίνει γενική πρόταση αντί για κενό', () {
      final message = buildBrokenBackupMessage(
        reason: null,
        wasMarked: true,
        rawDetail: '   ',
      );

      expect(message, startsWith('Το αντίγραφο δεν πέρασε τον έλεγχο.'));
      expect(message.trim(), isNot(endsWith(':')));
    });
  });
}
