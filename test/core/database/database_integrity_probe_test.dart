// Ο έλεγχος ακεραιότητας απαντά στο ερώτημα που κανένα διαγνωστικό πρόσβασης
// δεν αγγίζει: «στέκει αυτό που περιέχει το αρχείο;».
//
// Τα άλλα probes ρωτούν αν το αρχείο υπάρχει, διαβάζεται και γράφεται. Ένα
// αντίγραφο που κόπηκε στη μέση περνά και τα τρία.
//
//   flutter test test/core/database/database_integrity_probe_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_integrity_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Βάση με αρκετές σελίδες ώστε το κόψιμο να αφαιρεί πραγματικά δεδομένα.
Future<String> _createDb(Directory dir, String name) async {
  final path = p.join(dir.path, name);
  final db = await openDatabase(path, singleInstance: false);
  await db.execute('CREATE TABLE sample (id INTEGER PRIMARY KEY, note TEXT)');
  final batch = db.batch();
  for (var i = 0; i < 4000; i++) {
    batch.insert('sample', {'note': 'γραμμή γεμίσματος $i'});
  }
  await batch.commit(noResult: true);
  await db.close();
  return path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    initSqfliteFfiForTests();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('db_integrity_probe_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('υγιής βάση: ο έλεγχος λέει εντάξει και δεν παράγει θόρυβο', () async {
    final path = await _createDb(tempDir, 'ygiis.db');

    final outcome = await runDatabaseIntegrityProbe(path);

    expect(outcome.status, DatabaseIntegrityStatus.ok);
    expect(outcome.isCorrupt, isFalse);
    expect(outcome.rawMessage, isNull);
  });

  test('αρχείο κομμένο στη μέση: ποτέ «εντάξει», και κρατά το ωμό κείμενο', () async {
    final path = await _createDb(tempDir, 'kommeno.db');
    final file = File(path);
    final full = await file.readAsBytes();
    expect(full.length, greaterThan(40000), reason: 'χρειάζονται πολλές σελίδες');

    // Ό,τι αφήνει πίσω της μια αντιγραφή που δεν ολοκληρώθηκε.
    await file.writeAsBytes(full.sublist(0, full.length ~/ 2));

    final outcome = await runDatabaseIntegrityProbe(path);

    expect(outcome.status, isNot(DatabaseIntegrityStatus.ok));
    expect(outcome.rawMessage, isNotNull);
    expect(outcome.rawMessage!.trim(), isNotEmpty);
  });

  test('ανύπαρκτο αρχείο: άγνοια, ΠΟΤΕ κατηγορία για ζημιά', () async {
    final missing = p.join(tempDir.path, 'den_yparxei.db');

    final outcome = await runDatabaseIntegrityProbe(missing);

    expect(outcome.status, DatabaseIntegrityStatus.inconclusive);
    expect(outcome.isCorrupt, isFalse);
  });

  test('αργό άνοιγμα: το όριο δίνει άγνοια, όχι ζημιά', () async {
    final path = await _createDb(tempDir, 'argi.db');

    final outcome = await runDatabaseIntegrityProbe(
      path,
      timeout: const Duration(milliseconds: 1),
      open: (_) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        throw StateError('δεν πρέπει να φτάσει εδώ');
      },
    );

    expect(outcome.status, DatabaseIntegrityStatus.inconclusive);
    expect(outcome.isCorrupt, isFalse);
  });
}
