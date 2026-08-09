// Η Βάση Γνώσης: αποθήκευση, αναζήτηση, μετρητής χρήσης και ίχνος στο Ιστορικό.
//
//   flutter test test/core/database/knowledge_base_repository_test.dart --timeout 30s

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/knowledge_base_repository.dart';
import 'package:call_logger/features/knowledge/models/knowledge_article.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

const _vncArticle = KnowledgeArticle(
  title: 'Μαύρη οθόνη λόγω VNC',
  symptom: 'Βλέπει μαυρη οθόνη από το πρωί',
  solution: 'Αποσύνδεση της ενεργής συνεδρίας VNC και η προβολή επανέρχεται.',
  tags: 'VNC, μαύρη οθόνη',
);

void main() {
  late Database db;
  late KnowledgeBaseRepository repo;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('knowledge_base_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/knowledge.db');
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
    await db.delete('audit_log');
    await db.delete('knowledge_base');
    repo = KnowledgeBaseRepository(db);
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  test('νέο άρθρο αποθηκεύεται με χρόνους και μηδενικό μετρητή', () async {
    final id = await repo.saveArticle(_vncArticle);

    final saved = await repo.getById(id);
    expect(saved, isNotNull);
    expect(saved!.title, 'Μαύρη οθόνη λόγω VNC');
    expect(saved.symptom, 'Βλέπει μαυρη οθόνη από το πρωί');
    expect(saved.timesUsed, 0);
    expect(saved.createdAt, isNotNull);
    expect(saved.updatedAt, isNotNull);
  });

  test('οι ετικέτες καθαρίζονται από κενά και διπλότυπα', () async {
    final id = await repo.saveArticle(
      _vncArticle.copyWith(tags: ' VNC ,, μαύρη οθόνη ,VNC '),
    );

    final saved = await repo.getById(id);
    expect(saved!.tagList, <String>['VNC', 'μαύρη οθόνη']);
  });

  test('η αναζήτηση βρίσκει από σύμπτωμα, λύση και λέξεις-κλειδιά', () async {
    await repo.saveArticle(_vncArticle);

    expect(await repo.listArticles(keyword: 'μαυρη'), hasLength(1));
    expect(await repo.listArticles(keyword: 'συνεδριασ'), hasLength(1));
    expect(await repo.listArticles(keyword: 'VNC'), hasLength(1));
    expect(await repo.listArticles(keyword: 'εκτυπωτησ'), isEmpty);
  });

  test('η αναζήτηση απαιτεί όλες τις λέξεις του ερωτήματος', () async {
    await repo.saveArticle(_vncArticle);

    expect(await repo.listArticles(keyword: 'μαυρη οθονη'), hasLength(1));
    expect(await repo.listArticles(keyword: 'μαυρη εκτυπωτησ'), isEmpty);
  });

  test('findRelevant φέρνει το άρθρο από ανορθόγραφη κλήση', () async {
    await repo.saveArticle(_vncArticle);

    final found = await repo.findRelevant(query: 'Βλεπει μαυρη οθονη απο το πρωι');
    expect(found, hasLength(1));
    expect(found.single.title, 'Μαύρη οθόνη λόγω VNC');
  });

  test('findRelevant δεν επιστρέφει άσχετο άρθρο', () async {
    await repo.saveArticle(_vncArticle);

    expect(
      await repo.findRelevant(query: 'Να μπει το σύστημα διαλογής αλληλογραφίας'),
      isEmpty,
    );
  });

  test('markUsed αυξάνει τον μετρητή και γράφει τη στιγμή', () async {
    final id = await repo.saveArticle(_vncArticle);

    await repo.markUsed([id]);
    await repo.markUsed([id]);

    final saved = await repo.getById(id);
    expect(saved!.timesUsed, 2);
    expect(saved.lastUsedAt, isNotNull);
  });

  test('η ενημέρωση κρατά τον μετρητή χρήσης', () async {
    final id = await repo.saveArticle(_vncArticle);
    await repo.markUsed([id]);

    await repo.saveArticle(
      _vncArticle.copyWith(id: id, solution: 'Νέα διατύπωση λύσης.'),
    );

    final saved = await repo.getById(id);
    expect(saved!.solution, 'Νέα διατύπωση λύσης.');
    expect(saved.timesUsed, 1);
  });

  test('δημιουργία και τροποποίηση καταγράφονται ξεχωριστά', () async {
    final id = await repo.saveArticle(_vncArticle);
    await repo.saveArticle(
      _vncArticle.copyWith(id: id, title: 'Άλλος τίτλος'),
    );

    final actions = (await db.query('audit_log', columns: ['action']))
        .map((r) => r['action'])
        .toList();
    expect(actions, contains('ΔΗΜΙΟΥΡΓΙΑ ΑΡΘΡΟΥ ΓΝΩΣΗΣ'));
    expect(actions, contains('ΤΡΟΠΟΠΟΙΗΣΗ ΑΡΘΡΟΥ ΓΝΩΣΗΣ'));
  });

  test('αποθήκευση χωρίς αλλαγή δεν γεμίζει το Ιστορικό', () async {
    final id = await repo.saveArticle(_vncArticle);
    await repo.saveArticle(_vncArticle.copyWith(id: id));

    final logs = await db.query(
      'audit_log',
      where: 'action = ?',
      whereArgs: ['ΤΡΟΠΟΠΟΙΗΣΗ ΑΡΘΡΟΥ ΓΝΩΣΗΣ'],
    );
    expect(logs, isEmpty);
  });

  test('η διαγραφή αφήνει το περιεχόμενο στο Ιστορικό', () async {
    final id = await repo.saveArticle(_vncArticle);

    await repo.deleteArticle(id);

    expect(await repo.getById(id), isNull);
    final logs = await db.query(
      'audit_log',
      where: 'action = ?',
      whereArgs: ['ΔΙΑΓΡΑΦΗ ΑΡΘΡΟΥ ΓΝΩΣΗΣ'],
    );
    expect(logs, hasLength(1));
    expect(logs.single['old_values_json'], contains('VNC'));
  });

  test('η μετάπτωση v42 δίνει το πλήρες σχήμα και ξανατρέχει αζήμια', () async {
    await migrateDatabaseToV42(db);
    await migrateDatabaseToV42(db);

    final info = await db.rawQuery('PRAGMA table_info(knowledge_base)');
    final names = info.map((r) => r['name'] as String).toSet();
    expect(
      names,
      containsAll(<String>[
        'topic',
        'symptom',
        'content',
        'tags',
        'category_id',
        'source_call_id',
        'times_used',
        'last_used_at',
        'created_at',
        'updated_at',
        'search_index',
      ]),
    );
  });

  test('η μετάπτωση v42 δεν πετά υπάρχουσες γραμμές παλιού σχήματος', () async {
    await db.execute('DROP TABLE knowledge_base');
    await db.execute(
      'CREATE TABLE knowledge_base ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, topic TEXT, content TEXT, tags TEXT)',
    );
    await db.insert('knowledge_base', {
      'topic': 'Παλιά σημείωση',
      'content': 'Κάτι γραμμένο πριν τη Βάση Γνώσης',
    });

    await migrateDatabaseToV42(db);

    final rows = await db.query('knowledge_base');
    expect(rows, hasLength(1));
    expect(rows.single['topic'], 'Παλιά σημείωση');
    final info = await db.rawQuery('PRAGMA table_info(knowledge_base)');
    final names = info.map((r) => r['name'] as String).toSet();
    expect(names, contains('symptom'));
    expect(names, contains('times_used'));
  });
}
