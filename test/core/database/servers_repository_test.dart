// Ο πίνακας διακομιστών κρατά δύο κανόνες που, αν σπάσουν, χαλάνε την επιλογή
// στόχου στην «Αποσύνδεση χρήστη»:
//   • προεπιλεγμένος είναι ΠΑΝΤΑ ακριβώς ένας
//   • μετά από αφαίρεση δεν μένει η λίστα χωρίς προεπιλογή
//
//   flutter test test/core/database/servers_repository_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/servers_repository.dart';
import 'package:call_logger/core/models/managed_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('ServersRepository', () {
    late ServersRepository repo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('servers_repo_test_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/servers.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('servers');
      repo = ServersRepository(DatabaseHelper.instance);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<int> add(
      String name,
      String host, {
      bool isDefault = false,
      String password = 'κωδικός',
    }) {
      return repo.insert(
        ManagedServer(
          id: 0,
          name: name,
          host: host,
          adminUser: 'Administrator',
          adminPassword: password,
          isDefault: isDefault,
          sortOrder: 0,
        ),
      );
    }

    test('η προσθήκη δίνει διαδοχική σειρά ταξινόμησης', () async {
      await add('Πρώτος', '10.0.0.1');
      await add('Δεύτερος', '10.0.0.2');

      final all = await repo.getAll();
      expect(all.map((s) => s.sortOrder), [1, 2]);
    });

    test('νέα προεπιλογή σβήνει την προηγούμενη', () async {
      final first = await add('Πρώτος', '10.0.0.1', isDefault: true);
      final second = await add('Δεύτερος', '10.0.0.2', isDefault: true);

      final all = await repo.getAll();
      final defaults = all.where((s) => s.isDefault).map((s) => s.id).toList();
      expect(defaults, [second]);
      expect((await repo.getById(first))!.isDefault, isFalse);
    });

    test('η επεξεργασία σε προεπιλογή μεταφέρει τη σήμανση', () async {
      final first = await add('Πρώτος', '10.0.0.1', isDefault: true);
      final second = await add('Δεύτερος', '10.0.0.2');

      final target = (await repo.getById(second))!;
      await repo.update(target.copyWith(isDefault: true));

      expect((await repo.getById(first))!.isDefault, isFalse);
      expect((await repo.getById(second))!.isDefault, isTrue);
    });

    test('η αφαίρεση της προεπιλογής την περνά στον επόμενο', () async {
      // Χωρίς αυτό, η επίλυση στόχου θα έμενε χωρίς εφεδρεία και ο διάλογος
      // θα άνοιγε χωρίς προτεινόμενο διακομιστή.
      final first = await add('Πρώτος', '10.0.0.1', isDefault: true);
      final second = await add('Δεύτερος', '10.0.0.2');

      await repo.softDelete(first);

      final all = await repo.getAll();
      expect(all.map((s) => s.id), [second]);
      expect(all.single.isDefault, isTrue);
    });

    test('η αφαίρεση συμπυκνώνει τη σειρά χωρίς κενά', () async {
      final a = await add('Α', '10.0.0.1');
      await add('Β', '10.0.0.2');
      await add('Γ', '10.0.0.3');

      await repo.softDelete(a);

      final all = await repo.getAll();
      expect(all.map((s) => s.sortOrder), [1, 2]);
    });

    test('ο διαγραμμένος δεν επιστρέφεται στη λίστα', () async {
      final id = await add('Φευγάτος', '10.0.0.9');
      await repo.softDelete(id);

      expect(await repo.getAll(), isEmpty);
      // Παραμένει όμως προσβάσιμος με id: ανοιχτός διάλογος μπορεί να τον
      // κρατά ακόμη και δεν πρέπει να δείχνει κενό όνομα.
      expect((await repo.getById(id))!.name, 'Φευγάτος');
    });

    test('διακομιστής χωρίς κωδικό δηλώνεται ως ελλιπής', () async {
      final id = await add('Χωρίς', '10.0.0.7', password: '');

      expect((await repo.getById(id))!.hasCredentials, isFalse);
    });
  });
}
