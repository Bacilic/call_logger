// Σενάριο πεδίου 12/08/2026: κλήση «Άγνωστου» σε τμήμα με γενικό λογαριασμό.
// Η φόρμα έδειχνε «Αιτών: gnk\docpath1», αλλά το ticket έβγαινε με τον πράκτορα
// — η προεπισκόπηση και η αποστολή έλυναν το ίδιο ερώτημα με άλλο τρόπο.
//
// Το αρχείο φυλάει ΤΗ ΜΙΑ υλοποίηση που πλέον τροφοδοτεί και τις δύο.
//
//   flutter test test/core/services/lansweeper_call_requester_resolution_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/user_repository.dart';
import 'package:call_logger/core/services/lansweeper_call_requester_resolution.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

const _kPathologyId = 28;
const _kPathologyName = 'Παθολογική';
const _kDoc1 = r'gnk\docpath1';
const _kDoc2 = r'gnk\docpath2';

/// Δύο γενικοί λογαριασμοί, όπως τους αποθηκεύει η φόρμα τμήματος.
const _kTwoAccounts =
    '[{"username":"gnk\\\\docpath1","label":"Γιατρός Παθολογικής 1"},'
    '{"username":"gnk\\\\docpath2","label":"Γιατρός Παθολογικής 2"}]';

const _kOneAccount =
    '[{"username":"gnk\\\\docpath1","label":"Γιατρός Παθολογικής 1"}]';

CallModel _call({int? callerId, String? callerText}) {
  return CallModel(
    date: '2026-07-23',
    time: '10:26',
    issue: 'δεν εκτυπώνει',
    callerId: callerId,
    callerText: callerText,
    departmentText: _kPathologyName,
  );
}

void main() {
  late Database db;
  late UserRepository users;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('requester_resolution_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/requester.db');
    db = await DatabaseHelper.instance.database;
    users = UserRepository(db);
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  LookupService lookupWith(String? accounts) {
    final svc = LookupService.instance;
    svc.resetForReload();
    svc.injectInMemoryCatalogForTests(
      users: const [],
      equipment: const [],
      departmentRows: [
        DepartmentModel(
          id: _kPathologyId,
          name: _kPathologyName,
          lansweeperUsernames: accounts,
        ),
      ],
    );
    return svc;
  }

  test(
    'κλήση Άγνωστου σε τμήμα με ΕΝΑΝ λογαριασμό: αιτών ο λογαριασμός',
    () async {
      final options = await resolveLansweeperRequesterForCalls(
        userRepository: users,
        lookup: lookupWith(_kOneAccount),
        calls: [_call(callerText: 'Άγνωστος')],
      );

      expect(
        options.selectedUsername,
        _kDoc1,
        reason:
            'αυτό ακριβώς δείχνει η γραμμή «Στο ticket» — αν η αποστολή δεν το '
            'στείλει, η φόρμα λέει ψέματα',
      );
    },
  );

  test('με ΔΥΟ λογαριασμούς προεπιλέγεται ο πρώτος και είναι επιλέξιμο', () async {
    final options = await resolveLansweeperRequesterForCalls(
      userRepository: users,
      lookup: lookupWith(_kTwoAccounts),
      calls: [_call(callerText: 'Άγνωστος')],
    );

    expect(options.selectedUsername, _kDoc1);
    expect(options.candidates.map((c) => c.account.username), [_kDoc1, _kDoc2]);
    expect(options.isChoosable, isTrue);
  });

  test('τμήμα χωρίς λογαριασμούς: κανένας αιτών, το ticket μένει ως ήταν', () async {
    final options = await resolveLansweeperRequesterForCalls(
      userRepository: users,
      lookup: lookupWith(null),
      calls: [_call(callerText: 'Άγνωστος')],
    );

    expect(options.selectedUsername, isNull);
    expect(options.isChoosable, isFalse);
  });

  test('σπασμένος αποθηκευμένος λογαριασμός καθαρίζεται στην ανάγνωση', () async {
    final options = await resolveLansweeperRequesterForCalls(
      userRepository: users,
      lookup: lookupWith(
        '[{"username":"Γιατρός Παθολογικής 1 gnk\\\\docpath1"}]',
      ),
      calls: [_call(callerText: 'Άγνωστος')],
    );

    expect(
      options.selectedUsername,
      _kDoc1,
      reason: 'το κενό μέσα στο αναγνωριστικό δεν φτάνει ποτέ στο Lansweeper',
    );
  });

  // Ο μοναδικός λογαριασμός τμήματος έμπαινε αυτόματα χωρίς να εμφανίζεται ο
  // επιλογέας: σωστή πρόταση, αλλά αμετάκλητη. Υπάρχουν υπάλληλοι που δεν
  // ανήκουν στον τομέα και δουλεύουν με τον γενικό λογαριασμό — εκεί η
  // πρόταση πρέπει να μένει πρόταση.
  test('ένας λογαριασμός τμήματος: μπαίνει, αλλά μένει αλλάξιμος', () async {
    final options = await resolveLansweeperRequesterForCalls(
      userRepository: users,
      lookup: lookupWith(_kOneAccount),
      calls: [_call(callerText: 'Άγνωστος')],
    );

    expect(options.selectedUsername, _kDoc1);
    expect(
      options.isChoosable,
      isTrue,
      reason: 'χωρίς επιλογέα ο αιτών φεύγει χωρίς δυνατότητα αλλαγής',
    );
  });

  test('χωρίς κλήσεις δεν προκύπτει αιτών', () async {
    final options = await resolveLansweeperRequesterForCalls(
      userRepository: users,
      lookup: lookupWith(_kOneAccount),
      calls: const [],
    );

    expect(options.selectedUsername, isNull);
  });

  // Στην κλήση δεν προλαβαίνει πάντα να γραφτεί το όνομα· την ώρα της
  // καταχώρησης όμως ο χρήστης αναγνωρίζει ποιος τηλεφώνησε. Οι συνάδελφοι του
  // τμήματος μπαίνουν ως ΠΡΟΤΑΣΗ — ποτέ ως σιωπηλή προεπιλογή.
  group('συνάδελφοι τμήματος σε κλήση Άγνωστου', () {
    setUp(() async {
      await db.delete('users');
      await db.insert('departments', {
        'id': _kPathologyId,
        'name': _kPathologyName,
        'name_key': _kPathologyName.toLowerCase(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    Future<void> addUser({
      required String lastName,
      required String firstName,
      String? username,
      int isDeleted = 0,
    }) async {
      await db.insert('users', {
        'last_name': lastName,
        'first_name': firstName,
        'department_id': _kPathologyId,
        'lansweeper_username': username,
        'is_deleted': isDeleted,
      });
    }

    test('προσφέρονται, αλλά προεπιλογή μένει ο λογαριασμός τμήματος', () async {
      await addUser(
        lastName: 'Νικολαράκη',
        firstName: 'Αναστασία',
        username: r'gnk\a.nikolaraki',
      );

      final options = await resolveLansweeperRequesterForCalls(
        userRepository: users,
        lookup: lookupWith(_kOneAccount),
        calls: [_call(callerText: 'Άγνωστος')],
      );

      expect(
        options.selectedUsername,
        _kDoc1,
        reason: 'ο απρόσωπος λογαριασμός δεν χρεώνει αίτημα σε κανέναν',
      );
      expect(
        options.candidates.map((c) => c.account.username),
        containsAll([_kDoc1, r'gnk\a.nikolaraki']),
      );
      expect(
        options.candidates
            .where((c) => c.isSuggestionOnly)
            .map((c) => c.account.username),
        [r'gnk\a.nikolaraki'],
      );
    });

    test('χωρίς λογαριασμό τμήματος η προεπιλογή μένει κενή', () async {
      await addUser(
        lastName: 'Νικολαράκη',
        firstName: 'Αναστασία',
        username: r'gnk\a.nikolaraki',
      );

      final options = await resolveLansweeperRequesterForCalls(
        userRepository: users,
        lookup: lookupWith(null),
        calls: [_call(callerText: 'Άγνωστος')],
      );

      expect(
        options.selectedUsername,
        isNull,
        reason: 'κανείς δεν χρεώνεται αίτημα χωρίς ρητή επιλογή του χρήστη',
      );
      expect(options.candidates, hasLength(1));
      expect(
        options.isChoosable,
        isTrue,
        reason: 'ο ένας συνάδελφος είναι από μόνος του εναλλακτική',
      );
    });

    test('μπαίνουν αλφαβητικά', () async {
      await addUser(
        lastName: 'Τσόγκας',
        firstName: 'Σωτήρης',
        username: r'gnk\s.tsogkas',
      );
      await addUser(
        lastName: 'Μπέλου',
        firstName: 'Βασιλική',
        username: r'gnk\v.mpelou',
      );

      final options = await resolveLansweeperRequesterForCalls(
        userRepository: users,
        lookup: lookupWith(null),
        calls: [_call(callerText: 'Άγνωστος')],
      );

      expect(options.candidates.map((c) => c.account.username), [
        r'gnk\v.mpelou',
        r'gnk\s.tsogkas',
      ]);
    });

    test('χωρίς αναγνωριστικό ή διαγραμμένοι δεν προσφέρονται', () async {
      await addUser(lastName: 'Χωρίς', firstName: 'Ταυτότητα');
      await addUser(
        lastName: 'Έφυγε',
        firstName: 'Παλιός',
        username: r'gnk\gone',
        isDeleted: 1,
      );

      final options = await resolveLansweeperRequesterForCalls(
        userRepository: users,
        lookup: lookupWith(null),
        calls: [_call(callerText: 'Άγνωστος')],
      );

      expect(options.candidates, isEmpty);
      expect(options.selectedUsername, isNull);
    });

    // Με γνωστό καλούντα ο χρήστης ξέρει ήδη ποιος τηλεφώνησε: μια λίστα
    // συναδέλφων εκεί θα ήταν ευκαιρία για λάθος, όχι βοήθεια.
    test('γνωστός καλών χωρίς αναγνωριστικό δεν φέρνει συναδέλφους', () async {
      final callerId = await db.insert('users', {
        'last_name': 'Μαλατέστα',
        'first_name': 'Καλή',
        'department_id': _kPathologyId,
        'is_deleted': 0,
      });
      await addUser(
        lastName: 'Νικολαράκη',
        firstName: 'Αναστασία',
        username: r'gnk\a.nikolaraki',
      );

      final options = await resolveLansweeperRequesterForCalls(
        userRepository: users,
        lookup: lookupWith(_kOneAccount),
        calls: [_call(callerId: callerId, callerText: 'Καλή Μαλατέστα')],
      );

      expect(
        options.candidates.where((c) => c.isSuggestionOnly),
        isEmpty,
        reason: 'ο καλών είναι γνωστός — δεν μαντεύουμε συνάδελφο',
      );
      expect(options.selectedUsername, _kDoc1);
    });
  });
}
