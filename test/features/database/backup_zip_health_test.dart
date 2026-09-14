// Χαλασμένο αντίγραφο έναντι αντιγράφου χωρίς βάση μέσα.
//
// Σενάριο 13/09 (Δ3): το zip κόπηκε στη μέση — διακοπή αντιγραφής από
// δικτυακό φάκελο — και η εφαρμογή απάντησε «Δεν βρέθηκε αρχείο βάσης (.db)
// μέσα στο zip». Το μήνυμα κατηγορεί την ΕΠΙΛΟΓΗ του χειριστή, ενώ το λάθος
// είναι στο ίδιο το αρχείο. Ο αποκωδικοποιητής δεν βοηθά: σε κομμένο ή σε
// άσχετο αρχείο δεν πετάει τίποτα, επιστρέφει άδειο αρχειοθέτη.
//
//   flutter test test/features/database/backup_zip_health_test.dart

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:call_logger/features/database/services/backup_zip_candidate_selection.dart';
import 'package:call_logger/features/database/services/backup_zip_health.dart';
import 'package:call_logger/features/database/services/backup_zip_inventory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('zip-health-');
  });

  tearDown(() {
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Πραγματικό zip με μία βάση μέσα.
  List<int> healthyBytes() {
    final archive = Archive();
    final db = List<int>.filled(4096, 7);
    archive.addFile(ArchiveFile('call_logger.db', db.length, db));
    return ZipEncoder().encode(archive);
  }

  /// Έγκυρο zip χωρίς καμία εγγραφή.
  List<int> emptyArchiveBytes() => ZipEncoder().encode(Archive());

  String write(String name, List<int> bytes) {
    final path = p.join(root.path, name);
    File(path).writeAsBytesSync(bytes, flush: true);
    return path;
  }

  group('τι είναι αυτό το αρχείο', () {
    test('υγιές zip περνά', () {
      expect(inspectBackupArchiveBytes(healthyBytes()), BackupArchiveHealth.ok);
    });

    test('έγκυρο zip χωρίς αρχεία περνά κι αυτό', () {
      // Δεν έχει βάση μέσα, αλλά ΔΙΑΒΑΖΕΤΑΙ — το «δεν βρέθηκε .db» είναι εδώ
      // η αλήθεια, και πρέπει να επιβιώσει.
      expect(
        inspectBackupArchiveBytes(emptyArchiveBytes()),
        BackupArchiveHealth.ok,
      );
    });

    test('κομμένο στη μέση: χαλασμένο', () {
      final bytes = healthyBytes();
      expect(
        inspectBackupArchiveBytes(bytes.sublist(0, bytes.length ~/ 2)),
        BackupArchiveHealth.truncated,
      );
    });

    test('κομμένο λίγο πριν το τέλος: πάλι χαλασμένο', () {
      // Η παγίδα: η υπογραφή τέλους ΥΠΑΡΧΕΙ, αλλά η εγγραφή της είναι κομμένη
      // (7 από τα 22 bytes). Έλεγχος που ψάχνει μόνο την υπογραφή το χάνει.
      final bytes = healthyBytes();
      expect(
        inspectBackupArchiveBytes(bytes.sublist(0, (bytes.length * 9) ~/ 10)),
        BackupArchiveHealth.truncated,
      );
    });

    test('αρχείο που δεν είναι zip', () {
      expect(
        inspectBackupArchiveBytes(List<int>.filled(500, 65)),
        BackupArchiveHealth.notAnArchive,
      );
    });

    test('κενό αρχείο', () {
      expect(
        inspectBackupArchiveBytes(const <int>[]),
        BackupArchiveHealth.empty,
      );
    });
  });

  group('τι διαβάζει ο χειριστής', () {
    Future<String?> messageFor(String path) async {
      final inventory = await inventoryBackupZip(path);
      return decideBackupZipCandidateSelection(inventory).failureMessage;
    }

    test(
      'κομμένο zip: λέει ότι είναι χαλασμένο, όχι ότι δεν βρήκε βάση',
      () async {
        final bytes = healthyBytes();
        final path = write('κομμένο.zip', bytes.sublist(0, bytes.length ~/ 2));

        final message = await messageFor(path);
        expect(message, isNotNull);
        expect(
          message,
          isNot(contains('Δεν βρέθηκε αρχείο βάσης')),
          reason: 'Κατηγορούσε την επιλογή του χειριστή',
        );
        expect(message, contains('χαλασμ'));
        expect(
          message,
          contains('παλαιότερο'),
          reason: 'Χωρίς διέξοδο, η σωστή διάγνωση δεν βοηθά σε τίποτα',
        );
      },
    );

    test('αρχείο που δεν είναι zip: το λέει καθαρά', () async {
      final path = write('κείμενο.zip', List<int>.filled(500, 65));
      final message = await messageFor(path);
      expect(message, isNotNull);
      expect(message, isNot(contains('Δεν βρέθηκε αρχείο βάσης')));
      expect(message, contains('δεν είναι'));
    });

    test('κενό αρχείο: το λέει κι αυτό', () async {
      final path = write('άδειο.zip', const <int>[]);
      final message = await messageFor(path);
      expect(message, contains('κενό'));
    });

    test('έγκυρο zip χωρίς βάση: το παλιό μήνυμα ΕΠΙΒΙΩΝΕΙ', () async {
      final path = write('χωρίς_βάση.zip', emptyArchiveBytes());
      expect(
        await messageFor(path),
        contains('Δεν βρέθηκε αρχείο βάσης'),
        reason: 'Εδώ το αρχείο διαβάστηκε μια χαρά — απλώς δεν είχε βάση',
      );
    });

    test('υγιές zip με βάση: καμία αποτυχία', () async {
      final path = write('καλό.zip', healthyBytes());
      expect(await messageFor(path), isNull);
    });
  });
}
