// Αναζήτηση κλήσης με τον αριθμό της («#276»), όπως ήδη στον Κατάλογο.
//
// Ο τίτλος κάθε ticket Lansweeper τελειώνει με αυτόν τον αριθμό («[Word] #276»),
// οπότε ο δρόμος ticket → κλήση κλείνει μέσα από την αναζήτηση του Ιστορικού.
//
//   flutter test test/features/history/history_id_search_test.dart

import 'dart:io';

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/utils/id_search_query.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late Database db;
  late CallsRepository calls;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('history_id_search_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/id_search.db');
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
    await db.delete('calls');
    calls = CallsRepository(db);
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  Future<int> insertCall({required String issue}) {
    return db.insert('calls', {
      'date': '2026-08-11',
      'time': '12:26',
      'issue': issue,
      'status': 'completed',
      'lansweeper_state': 'unsent',
      'search_index': SearchTextNormalizer.normalizeForSearch(issue),
      'is_deleted': 0,
    });
  }

  /// Η ίδια διαδρομή που κάνει ο provider: ανάλυση «#id» και ξεχωριστό κείμενο.
  Future<List<Map<String, dynamic>>> search(String rawQuery) async {
    final query = IdSearchQuery.parse(rawQuery);
    if (query.hasInvalidIdToken) return const <Map<String, dynamic>>[];
    final text = SearchTextNormalizer.normalizeForSearch(query.text);
    return calls.getHistoryCalls(
      keyword: text.isEmpty ? null : text,
      callIds: query.ids,
    );
  }

  test('«#id» φέρνει ΜΟΝΟ την κλήση με αυτόν τον αριθμό', () async {
    final target = await insertCall(issue: 'είχε κωλύσει');
    await insertCall(issue: 'δεν εκτυπώνει');

    final rows = await search('#$target');

    expect(rows, hasLength(1));
    expect(rows.single['id'], target);
  });

  test('ο αριθμός είναι ακριβής — το «#7» δεν φέρνει το 17', () async {
    final first = await insertCall(issue: 'πρώτη');
    // Οι επόμενες κλήσεις παίρνουν αύξοντα ids· φτιάχνουμε ένα που περιέχει
    // τον ίδιο αριθμό ως υποσύνολο ψηφίων.
    var last = first;
    while (last < first + 10) {
      last = await insertCall(issue: 'γέμισμα');
    }

    final rows = await search('#$first');

    expect(rows, hasLength(1));
    expect(rows.single['id'], first);
  });

  test('«#id» μαζί με κείμενο ισχύουν αθροιστικά', () async {
    final target = await insertCall(issue: 'είχε κωλύσει το Word');
    await insertCall(issue: 'είχε κωλύσει το Excel');

    expect(await search('#$target word'), hasLength(1));
    expect(
      await search('#$target excel'),
      isEmpty,
      reason: 'ο αριθμός δείχνει άλλη κλήση από αυτήν που έχει τη λέξη',
    );
  });

  test('δύο διαφορετικοί αριθμοί δεν ταιριάζουν καμία γραμμή', () async {
    final a = await insertCall(issue: 'πρώτη');
    final b = await insertCall(issue: 'δεύτερη');

    expect(await search('#$a #$b'), isEmpty);
  });

  test('«#» χωρίς αριθμό δεν φέρνει τίποτα, αντί για όλες', () async {
    await insertCall(issue: 'είχε κωλύσει');

    expect(await search('#'), isEmpty);
    expect(await search('#αβγ'), isEmpty);
  });

  test('ανύπαρκτος αριθμός δίνει άδειο αποτέλεσμα', () async {
    await insertCall(issue: 'είχε κωλύσει');

    expect(await search('#999999'), isEmpty);
  });

  test('χωρίς όρο «#» η αναζήτηση κειμένου μένει ως είχε', () async {
    await insertCall(issue: 'είχε κωλύσει');
    await insertCall(issue: 'δεν εκτυπώνει');

    final rows = await search('κωλύσει');

    expect(rows, hasLength(1));
    expect(rows.single['issue'], 'είχε κωλύσει');
  });
}
