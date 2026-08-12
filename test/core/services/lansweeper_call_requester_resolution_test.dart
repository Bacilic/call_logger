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

  test('χωρίς κλήσεις δεν προκύπτει αιτών', () async {
    final options = await resolveLansweeperRequesterForCalls(
      userRepository: users,
      lookup: lookupWith(_kOneAccount),
      calls: const [],
    );

    expect(options.selectedUsername, isNull);
  });
}
