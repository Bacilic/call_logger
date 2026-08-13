// Ο φρουρός στο ΕΝΑ σημείο: όταν το αρχείο βάσης αντικατασταθεί απ' έξω, το
// WAL δεν γράφεται πίσω σε αυτό.
//
// Το checkpoint είναι ακριβώς η πράξη που προκαλεί τη ζημιά: ράβει σελίδες της
// παλιάς βάσης πάνω στο νέο περιεχόμενο. Κάθε ροή που έκανε checkpoint περνά
// από το ίδιο σημείο, οπότε αρκεί να φυλαχθεί εκείνο.
//
//   flutter test test/core/database/database_replacement_checkpoint_guard_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Αντιγράφει τα bytes του [source] **πάνω** στο [target], όπως ακριβώς κάνει
/// ο Explorer των Windows.
///
/// Όχι `File.copy`: εκείνο θέλει να διαγράψει πρώτα τον προορισμό και σκοντάφτει
/// σε ανοιχτό αρχείο. Ο Explorer ανοίγει το υπάρχον αρχείο και ξαναγράφει το
/// περιεχόμενό του — γι' αυτό ακριβώς η αντικατάσταση περνά ενώ η βάση είναι
/// ανοιχτή, και γι' αυτό το SQLite δεν το μαθαίνει ποτέ.
void _overwriteInPlace({required String source, required String target}) {
  final bytes = File(source).readAsBytesSync();
  final handle = File(target).openSync(mode: FileMode.write);
  try {
    handle.writeFromSync(bytes);
    handle.truncateSync(bytes.length);
  } finally {
    handle.closeSync();
  }
}

/// Ξένη βάση, με άλλο περιεχόμενο από την ενεργή.
Future<String> _createForeignDatabase(Directory dir, String name) async {
  final path = p.join(dir.path, name);
  final db = await databaseFactory.openDatabase(path);
  await db.execute('CREATE TABLE ξένος (id INTEGER PRIMARY KEY, τιμή TEXT)');
  for (var i = 0; i < 60; i++) {
    await db.insert('ξένος', {'τιμή': 'εγγραφή $i'});
  }
  await db.close();
  return path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String activePath;

  setUpAll(() {
    initSqfliteFfiForTests();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseHelper.instance.closeConnection();
    tempDir = await Directory.systemTemp.createTemp('db_replacement_guard_');
    activePath = p.join(tempDir.path, 'ενεργή.db');
    await DatabaseHelper.bindTestDatabaseFile(activePath);
    // Άνοιγμα: εδώ καταγράφεται η ταυτότητα του αρχείου.
    await DatabaseHelper.instance.database;
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  test('η ανοιχτή βάση καταγράφει τη διαδρομή της', () async {
    expect(DatabaseHelper.instance.openedDatabasePath, activePath);
  });

  test('χωρίς αντικατάσταση ο φρουρός σιωπά', () async {
    expect(await DatabaseHelper.instance.databaseFileWasReplaced(), isFalse);
  });

  test('κανονική εγγραφή δεν ξυπνά τον φρουρό', () async {
    final db = await DatabaseHelper.instance.database;
    for (var i = 0; i < 30; i++) {
      await db.insert('categories', {'name': 'κατηγορία $i'});
    }

    expect(
      await DatabaseHelper.instance.databaseFileWasReplaced(),
      isFalse,
      reason:
          'Η κανονική χρήση —δική μας ή άλλου μηχανήματος— δεν επιτρέπεται να '
          'δώσει συναγερμό: θα κατέστρεφε την κοινόχρηστη λειτουργία.',
    );
  });

  test('αντικατάσταση του αρχείου ανιχνεύεται', () async {
    final foreign = await _createForeignDatabase(tempDir, 'ξένη.db');
    _overwriteInPlace(source: foreign, target: activePath);

    expect(await DatabaseHelper.instance.databaseFileWasReplaced(), isTrue);
  });

  test('κανονικό κλείσιμο εξακολουθεί να κατεβάζει το WAL στη βάση', () async {
    final db = await DatabaseHelper.instance.database;
    for (var i = 0; i < 40; i++) {
      await db.insert('categories', {'name': 'κανονική $i'});
    }

    await DatabaseHelper.instance.closeConnection();

    final wal = File('$activePath-wal');
    expect(
      !wal.existsSync() || wal.lengthSync() == 0,
      isTrue,
      reason:
          'Χωρίς αντικατάσταση το κλείσιμο οφείλει να γράψει κανονικά ό,τι '
          'εκκρεμεί — ο φρουρός δεν επιτρέπεται να σαμποτάρει τη ρουτίνα.',
    );
    expect(File('$activePath.orphan-wal').existsSync(), isFalse);
  });

  test('το ορφανό WAL φυλάγεται πριν ουδετεροποιηθεί', () async {
    final db = await DatabaseHelper.instance.database;
    for (var i = 0; i < 40; i++) {
      await db.insert('categories', {'name': 'προς φύλαξη $i'});
    }

    final foreign = await _createForeignDatabase(tempDir, 'ξένη3.db');
    _overwriteInPlace(source: foreign, target: activePath);
    await DatabaseHelper.instance.closeConnection();

    final kept = File('$activePath.orphan-wal');
    expect(
      kept.existsSync() && kept.lengthSync() > 0,
      isTrue,
      reason:
          'Το περιεχόμενο του WAL ανήκει σε βάση που χάθηκε — δεν το πετάμε '
          'αθόρυβα, το αφήνουμε δίπλα.',
    );
  });

  test(
    'το κλείσιμο μετά από αντικατάσταση δεν γράφει πίσω στο ξένο αρχείο',
    () async {
      // Εγγραφές που ζουν στο WAL και θα «κατέβαιναν» με checkpoint.
      final db = await DatabaseHelper.instance.database;
      for (var i = 0; i < 40; i++) {
        await db.insert('categories', {'name': 'προς WAL $i'});
      }

      final foreign = await _createForeignDatabase(tempDir, 'ξένη2.db');
      final foreignBytes = await File(foreign).readAsBytes();
      _overwriteInPlace(source: foreign, target: activePath);

      // Το κανονικό κλείσιμο — αυτό που τρέχει σε κάθε έξοδο εφαρμογής.
      await DatabaseHelper.instance.closeConnection();

      final afterBytes = await File(activePath).readAsBytes();
      expect(
        afterBytes.length,
        foreignBytes.length,
        reason: 'Το αρχείο άλλαξε μέγεθος: κάποιος έγραψε πάνω του.',
      );
      expect(
        afterBytes,
        orderedEquals(foreignBytes),
        reason:
            'Το checkpoint έγραψε σελίδες της παλιάς βάσης πάνω στο νέο '
            'αρχείο — αυτή ακριβώς είναι η καταστροφή που φυλάμε.',
      );
    },
  );
}
