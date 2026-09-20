// Το συμβόλαιο που δηλώνει το ίδιο το αρχείο της συσκευασίας: «ό,τι δηλώνεται
// ως περιεχόμενο μπήκε πράγματι μέσα». Εδώ φυλάγεται.
//
//   flutter test test/features/database/backup_bundle_declares_what_entered_test.dart

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:call_logger/features/database/models/database_backup_settings.dart';
import 'package:call_logger/features/database/services/backup_portable_bundle.dart';
import 'package:call_logger/features/database/utils/portable_backup_availability.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ο χρήστης έχει ζητήσει **όλα** τα φορητά, και η διαθεσιμότητα λέει ότι
/// υπάρχουν — δηλαδή η ρύθμιση είναι αναμμένη και για τα τέσσερα.
const _availability = PortableBackupAvailability(
  hasMapImages: true,
  hasToolImages: true,
  hasLoadedLexicon: true,
  hasLampDbInPortableDataBase: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late String dbPath;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bundle_truth_');
    dbPath = '${dir.path}/call_logger.db';
    await File(dbPath).writeAsBytes(List<int>.filled(64, 7));
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<BackupBundleOutcome> pack() {
    return writeFullBackupArchive(
      archivePath: '${dir.path}/backup.zip',
      databaseFilePath: dbPath,
      sourceDatabasePath: dbPath,
      settings: DatabaseBackupSettings.defaults().copyWith(
        includeMapImagesInBackup: true,
        includeToolImages: true,
        includeLexicon: true,
        includeLampDb: true,
      ),
      availability: _availability,
    );
  }

  Set<String> entriesOf(String zipPath) {
    final archive = ZipDecoder().decodeBytes(File(zipPath).readAsBytesSync());
    return archive.files.map((f) => f.name).toSet();
  }

  test(
    'κομμάτι που δεν έβαλε ΚΑΝΕΝΑ αρχείο δεν δηλώνεται ως περιεχόμενο',
    () async {
      // Οι φάκελοι των φορητών δεν υπάρχουν στο περιβάλλον του τεστ, οπότε
      // καμία εικόνα και κανένα λεξικό δεν μπαίνει στο zip. Η λίστα
      // περιεχομένων δεν επιτρέπεται να τα ονομάσει.
      final outcome = await pack();
      final entries = entriesOf('${dir.path}/backup.zip');

      expect(
        entries.any((e) => e.startsWith('maps_images/')),
        isFalse,
        reason: 'προϋπόθεση: καμία εικόνα χάρτη δεν μπήκε',
      );

      expect(
        outcome.includedParts,
        isNot(contains('εικόνες χαρτών')),
        reason: 'δηλώθηκε περιεχόμενο που δεν μπήκε ποτέ μέσα',
      );
      expect(outcome.includedParts, isNot(contains('εικονίδια εργαλείων')));
      expect(outcome.includedParts, isNot(contains('λεξικό')));
    },
  );

  test('η βάση και η ταυτότητα μπαίνουν πάντα', () async {
    await pack();
    final entries = entriesOf('${dir.path}/backup.zip');

    expect(entries, contains('call_logger.db'));
    expect(entries.length, greaterThanOrEqualTo(2));
  });
}
