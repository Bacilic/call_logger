// Ένα αντίγραφο δεν είναι επιτυχές επειδή γράφτηκε — είναι επιτυχές αν ανοίγει.
//
// Ως τώρα η δημιουργία τελείωνε με «Το αντίγραφο ολοκληρώθηκε» μόλις γραφόταν
// το αρχείο. Δίσκος που γέμισε, δίκτυο που κόπηκε ή βάση που αντιγράφηκε ενώ
// κάποιος έγραφε δίνουν αρχείο που υπάρχει — και η ζημιά φαινόταν μόνο την
// ώρα της επαναφοράς.
//
//   flutter test test/features/database/backup_verification_test.dart

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:call_logger/features/database/services/backup_verification.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory root;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    root = Directory.systemTemp.createTempSync('backup-verify-');
  });

  tearDown(() {
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Μια πραγματική βάση SQLite με λίγο περιεχόμενο μέσα.
  Future<List<int>> healthyDatabaseBytes() async {
    final path = p.join(root.path, 'seed.db');
    final db = await databaseFactory.openDatabase(path);
    await db.execute('CREATE TABLE calls (id INTEGER PRIMARY KEY, note TEXT)');
    await db.insert('calls', {'note': 'δοκιμή'});
    await db.close();
    final bytes = File(path).readAsBytesSync();
    File(path).deleteSync();
    return bytes;
  }

  Future<String> writeZip(String name, List<int> dbBytes) async {
    final archive = Archive()
      ..addFile(ArchiveFile('call_logger.db', dbBytes.length, dbBytes));
    final path = p.join(root.path, name);
    File(path).writeAsBytesSync(ZipEncoder().encode(archive));
    return path;
  }

  group('επαλήθευση αντιγράφου', () {
    test('υγιές .zip με βάση μέσα περνά', () async {
      final path = await writeZip('full.zip', await healthyDatabaseBytes());

      final result = await verifyBackupArtifact(path);

      expect(result.status, BackupVerificationStatus.ok);
      expect(result.isBroken, isFalse);
    });

    test('υγιές .db περνά', () async {
      final path = p.join(root.path, 'quick.db');
      File(path).writeAsBytesSync(await healthyDatabaseBytes());

      final result = await verifyBackupArtifact(path);

      expect(result.status, BackupVerificationStatus.ok);
    });

    test('κενό αρχείο είναι χαλασμένο, όχι απλώς άδειο', () async {
      final path = p.join(root.path, 'empty.zip');
      File(path).writeAsBytesSync(<int>[]);

      final result = await verifyBackupArtifact(path);

      expect(result.status, BackupVerificationStatus.brokenArchive);
      expect(result.isBroken, isTrue);
      expect(result.message, isNotNull);
    });

    test('κομμένο zip πιάνεται πριν από κάθε αποκωδικοποίηση', () async {
      final full = await writeZip('cut.zip', await healthyDatabaseBytes());
      final bytes = File(full).readAsBytesSync();
      File(
        full,
      ).writeAsBytesSync(bytes.sublist(0, (bytes.length * 0.6).round()));

      final result = await verifyBackupArtifact(full);

      expect(result.status, BackupVerificationStatus.brokenArchive);
    });

    test('zip χωρίς βάση μέσα δεν περνά για αντίγραφο', () async {
      final archive = Archive()
        ..addFile(ArchiveFile('readme.txt', 3, <int>[1, 2, 3]));
      final path = p.join(root.path, 'nodb.zip');
      File(path).writeAsBytesSync(ZipEncoder().encode(archive));

      final result = await verifyBackupArtifact(path);

      expect(result.status, BackupVerificationStatus.brokenArchive);
    });

    test('αρχείο που δεν υπάρχει αναφέρεται ως χαλασμένο', () async {
      final result = await verifyBackupArtifact(
        p.join(root.path, 'δεν-υπάρχει.zip'),
      );

      expect(result.status, BackupVerificationStatus.brokenArchive);
    });

    test('ο έλεγχος δεν αφήνει σκουπίδια δίπλα στο αντίγραφο', () async {
      final path = await writeZip('clean.zip', await healthyDatabaseBytes());

      await verifyBackupArtifact(path);

      final leftovers = root
          .listSync()
          .map((entity) => p.basename(entity.path))
          .toList();
      expect(leftovers, ['clean.zip']);
    });
  });

  group('σήμανση χαλασμένου', () {
    test('το αρχείο μετονομάζεται αντί να σβηστεί', () async {
      final path = p.join(root.path, 'broken.zip');
      File(path).writeAsBytesSync(<int>[1, 2, 3]);

      final marked = await markBackupArtifactAsBroken(path);

      expect(marked, isNotNull);
      expect(File(path).existsSync(), isFalse);
      expect(File(marked!).existsSync(), isTrue);
      expect(p.basename(marked), contains(kBrokenBackupNameMarker));
      expect(p.extension(marked), '.zip');
    });

    test('δεύτερο χαλασμένο με το ίδιο όνομα δεν σβήνει το πρώτο', () async {
      final path = p.join(root.path, 'same.zip');

      File(path).writeAsBytesSync(<int>[1]);
      final first = await markBackupArtifactAsBroken(path);

      File(path).writeAsBytesSync(<int>[2]);
      final second = await markBackupArtifactAsBroken(path);

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first, isNot(second));
      expect(File(first!).existsSync(), isTrue);
      expect(File(second!).existsSync(), isTrue);
    });
  });
}
