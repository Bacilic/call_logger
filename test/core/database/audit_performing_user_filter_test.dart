// Το «ποιος το έκανε» ζει σε δικό του φίλτρο, όχι μέσα στη λέξη-κλειδί.
// Εδώ φυλάγεται ότι στενεύει σωστά τη λίστα, ότι συνδυάζεται με ΚΑΙ με τα
// υπόλοιπα φίλτρα, και — κυρίως — ότι η «επιλογή όλων» βλέπει ακριβώς ό,τι
// βλέπει και η οθόνη.
//
//   flutter test test/core/database/audit_performing_user_filter_test.dart

import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late Database db;
  late AuditService service;

  setUpAll(() async {
    initSqfliteFfiForTests();
    db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    await db.execute('''
      CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT,
        timestamp TEXT,
        user_performing TEXT,
        details TEXT,
        entity_type TEXT,
        entity_id INTEGER,
        entity_name TEXT,
        search_text TEXT,
        old_values_json TEXT,
        new_values_json TEXT
      )
    ''');
    service = AuditService(db);
  });

  tearDown(() async {
    await db.delete('audit_log');
  });

  tearDownAll(() async {
    await db.close();
  });

  Future<int> insertRow({
    required String action,
    required String performer,
    required String entityType,
    required String entityName,
    required String timestamp,
  }) {
    return db.insert('audit_log', {
      'action': action,
      'timestamp': timestamp,
      'user_performing': performer,
      'entity_type': entityType,
      'entity_name': entityName,
      'search_text': SearchTextNormalizer.normalizeForSearch(entityName),
    });
  }

  /// Τρεις χειριστές, ώστε κάθε φίλτρο να έχει κάτι να αποκλείσει.
  Future<void> seedThreePerformers() async {
    await insertRow(
      action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΥΠΑΛΛΗΛΟΥ',
      performer: 'Βασίλης',
      entityType: 'user',
      entityName: 'Δήμητρα Παπαδοπούλου',
      timestamp: '2026-08-20T10:00:00.000',
    );
    await insertRow(
      action: 'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ',
      performer: 'Βασίλης',
      entityType: 'call',
      entityName: 'Ακτινολογικό',
      timestamp: '2026-08-20T11:00:00.000',
    );
    await insertRow(
      action: 'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ',
      performer: 'v.drosos',
      entityType: 'call',
      entityName: 'Φαρμακείο',
      timestamp: '2026-08-20T12:00:00.000',
    );
    await insertRow(
      action: 'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ',
      performer: CurrentOperator.unknownAuditName,
      entityType: 'call',
      entityName: 'Παλιά εγγραφή',
      timestamp: '2026-08-19T09:00:00.000',
    );
  }

  Future<int> countWith({
    String? performer,
    String? action,
    String? keyword,
  }) async {
    final page = await service.queryPage(
      offset: 0,
      limit: 50,
      userPerforming: performer,
      action: action,
      keywordNormalized: keyword == null
          ? null
          : SearchTextNormalizer.normalizeForSearch(keyword),
    );
    return page.total;
  }

  group('Φίλτρο «Χειριστής»', () {
    test('δείχνει μόνο όσα σφράγισε ο συγκεκριμένος χειριστής', () async {
      await seedThreePerformers();

      expect(await countWith(), 4, reason: 'χωρίς φίλτρο φαίνονται όλες');
      expect(await countWith(performer: 'Βασίλης'), 2);
      expect(await countWith(performer: 'v.drosos'), 1);
    });

    test('οι εγγραφές πριν την ταυτότητα απομονώνονται με την παύλα', () async {
      await seedThreePerformers();

      expect(await countWith(performer: CurrentOperator.unknownAuditName), 1);
    });

    test('συνδυάζεται με τα άλλα φίλτρα ως ΚΑΙ, όχι ως Ή', () async {
      await seedThreePerformers();

      expect(
        await countWith(performer: 'Βασίλης', action: 'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ'),
        1,
        reason:
            'Ο Βασίλης έχει 2 εγγραφές και η ενέργεια 3· η τομή τους είναι μία.',
      );
      expect(
        await countWith(performer: 'v.drosos', action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΥΠΑΛΛΗΛΟΥ'),
        0,
      );
    });

    test('συνδυάζεται με τη λέξη-κλειδί ως ΚΑΙ', () async {
      await seedThreePerformers();

      expect(await countWith(keyword: 'Φαρμακείο'), 1);
      expect(await countWith(performer: 'Βασίλης', keyword: 'Φαρμακείο'), 0);
      expect(await countWith(performer: 'v.drosos', keyword: 'Φαρμακείο'), 1);
    });

    test('άδειο φίλτρο δεν στενεύει τίποτα', () async {
      await seedThreePerformers();

      expect(await countWith(performer: ''), 4);
      expect(await countWith(performer: '   '), 4);
    });
  });

  group('Η λίστα ονομάτων του φίλτρου', () {
    test('περιλαμβάνει κάθε χειριστή, μαζί με την παύλα', () async {
      await seedThreePerformers();

      final names = await service.queryDistinctPerformingUsers();

      expect(names, contains('Βασίλης'));
      expect(names, contains('v.drosos'));
      expect(
        names,
        contains(CurrentOperator.unknownAuditName),
        reason:
            'Οι εγγραφές πριν την ταυτότητα είναι η πλειοψηφία — αν λείπουν '
            'από τη λίστα, δεν υπάρχει τρόπος να απομονωθούν.',
      );
      expect(names.length, 3, reason: 'κάθε όνομα μία φορά');
    });

    test('περιορίζεται από τα υπόλοιπα φίλτρα', () async {
      await seedThreePerformers();

      final names = await service.queryDistinctPerformingUsers(
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΥΠΑΛΛΗΛΟΥ',
      );

      expect(names, ['Βασίλης']);
    });
  });

  group('Η επιλογή όλων βλέπει ό,τι και η οθόνη', () {
    test('τα ids της επιλογής σέβονται το φίλτρο χειριστή', () async {
      await seedThreePerformers();

      final shown = await service.queryPage(
        offset: 0,
        limit: 50,
        userPerforming: 'Βασίλης',
      );
      final selectable = await service.queryMatchingIds(
        userPerforming: 'Βασίλης',
      );

      expect(
        selectable.length,
        shown.total,
        reason:
            'Αν η επιλογή όλων αγνοούσε το φίλτρο, θα σημείωνε προς διαγραφή '
            'εγγραφές που ο χρήστης δεν βλέπει καν στη λίστα.',
      );
      expect(selectable.toSet(), shown.rows.map((r) => r['id']).toSet());
    });
  });
}
