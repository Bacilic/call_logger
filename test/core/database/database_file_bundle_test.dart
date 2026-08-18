// Κοινός μηχανισμός αρχείων βάσης (κύριο + sidecars) — χωρίς SQLite.
//
//   flutter test test/core/database/database_file_bundle_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_file_bundle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('db_file_bundle_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('renameDatabaseBundle', () {
    test('μετονομάζει κύριο αρχείο και τα υπαρκτά sidecars', () async {
      final mainPath = p.join(tempDir.path, 'call_logger.db');
      await File(mainPath).writeAsString('main');
      await File('$mainPath-wal').writeAsString('wal');
      await File('$mainPath-shm').writeAsString('shm');

      await renameDatabaseBundle(
        mainPath,
        'call_logger_pre_restore_25-07-2026.db',
      );

      final renamed = p.join(
        tempDir.path,
        'call_logger_pre_restore_25-07-2026.db',
      );
      expect(await File(mainPath).exists(), isFalse);
      expect(await File(renamed).exists(), isTrue);
      expect(await File(renamed).readAsString(), 'main');
      expect(await File('$renamed-wal').exists(), isTrue);
      expect(await File('$renamed-shm').exists(), isTrue);
      expect(await File('$mainPath-wal').exists(), isFalse);
      expect(await File('$mainPath-shm').exists(), isFalse);
    });

    test('αδιαφορεί για sidecars που δεν υπάρχουν', () async {
      final mainPath = p.join(tempDir.path, 'solo.db');
      await File(mainPath).writeAsString('solo');

      await renameDatabaseBundle(mainPath, 'solo_moved.db');

      final renamed = p.join(tempDir.path, 'solo_moved.db');
      expect(await File(renamed).exists(), isTrue);
      expect(await File('$renamed-wal').exists(), isFalse);
      expect(await File('$renamed-shm').exists(), isFalse);
    });
  });

  group('deleteDatabaseSidecars', () {
    test('σβήνει τα συνοδά, ποτέ το κύριο αρχείο', () async {
      final mainPath = p.join(tempDir.path, 'keep.db');
      await File(mainPath).writeAsString('keep');
      await File('$mainPath-wal').writeAsString('wal');
      await File('$mainPath-shm').writeAsString('shm');

      await deleteDatabaseSidecars(mainPath);

      expect(await File(mainPath).exists(), isTrue);
      expect(await File(mainPath).readAsString(), 'keep');
      expect(await File('$mainPath-wal').exists(), isFalse);
      expect(await File('$mainPath-shm').exists(), isFalse);
    });

    test('δεν αποτυγχάνει όταν λείπουν sidecars', () async {
      final mainPath = p.join(tempDir.path, 'noside.db');
      await File(mainPath).writeAsString('ok');

      await expectLater(deleteDatabaseSidecars(mainPath), completes);
      expect(await File(mainPath).exists(), isTrue);
    });
  });

  group('resolveUniqueTimestampedFileName', () {
    test('χωρίς σύγκρουση επιστρέφει όνομα με ημερομηνία', () {
      final name = resolveUniqueTimestampedFileName(
        directory: tempDir.path,
        baseName: 'call_logger',
        suffix: '_pre_restore_',
        extension: '.db',
        now: DateTime(2026, 7, 25, 14, 32, 7),
        fileExists: (_) => false,
      );

      expect(name, 'call_logger_pre_restore_25-07-2026.db');
    });

    test('κλιμακώνει ημερομηνία → HH-mm → HH-mm-ss → αριθμό', () {
      final occupied = <String>{
        p.join(tempDir.path, 'call_logger_pre_restore_25-07-2026.db'),
        p.join(tempDir.path, 'call_logger_pre_restore_25-07-2026_14-32.db'),
        p.join(tempDir.path, 'call_logger_pre_restore_25-07-2026_14-32-07.db'),
      };

      final name = resolveUniqueTimestampedFileName(
        directory: tempDir.path,
        baseName: 'call_logger',
        suffix: '_pre_restore_',
        extension: '.db',
        now: DateTime(2026, 7, 25, 14, 32, 7),
        fileExists: occupied.contains,
      );

      expect(name, 'call_logger_pre_restore_25-07-2026_14-32-07_2.db');
    });
  });

  group('το -journal του κλασικού ημερολογίου', () {
    test('μετονομάζεται μαζί με το κύριο αρχείο', () async {
      // Ένα «-journal» που θα έμενε πίσω περιγράφει ημιτελή εγγραφή σε βάση
      // που δεν βρίσκεται πια εκεί.
      final mainPath = p.join(tempDir.path, 'call_logger.db');
      await File(mainPath).writeAsString('main');
      await File('$mainPath-journal').writeAsString('journal');

      await renameDatabaseBundle(mainPath, 'metonomasmeni.db');

      final renamed = p.join(tempDir.path, 'metonomasmeni.db');
      expect(await File('$mainPath-journal').exists(), isFalse);
      expect(await File('$renamed-journal').exists(), isTrue);
      expect(await File('$renamed-journal').readAsString(), 'journal');
    });

    test('σβήνεται μαζί με τα υπόλοιπα συνοδά', () async {
      // Το σενάριο που το κάνει κρίσιμο: κατάρρευση αφήνει «-journal», μετά
      // γίνεται επαναφορά από αντίγραφο. Αν το «-journal» της ΠΑΛΙΑΣ βάσης
      // μείνει δίπλα στη ΝΕΑ, το SQLite θα το εφαρμόσει σαν δικό της.
      final mainPath = p.join(tempDir.path, 'call_logger.db');
      await File(mainPath).writeAsString('main');
      await File('$mainPath-wal').writeAsString('wal');
      await File('$mainPath-shm').writeAsString('shm');
      await File('$mainPath-journal').writeAsString('journal');

      await deleteDatabaseSidecars(mainPath);

      expect(await File(mainPath).exists(), isTrue, reason: 'το κύριο μένει');
      for (final suffix in kDatabaseSidecarSuffixes) {
        expect(
          await File('$mainPath$suffix').exists(),
          isFalse,
          reason: 'έμεινε συνοδό $suffix',
        );
      }
    });

    test('η λίστα συνοδών καλύπτει και τους δύο τρόπους ημερολογίου', () {
      expect(kDatabaseSidecarSuffixes, containsAll(<String>['-wal', '-shm']));
      expect(kDatabaseSidecarSuffixes, contains('-journal'));
    });
  });
}
