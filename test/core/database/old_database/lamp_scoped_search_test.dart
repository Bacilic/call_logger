import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:call_logger/core/database/old_database/old_equipment_repository.dart';
import 'package:call_logger/features/lamp/controllers/lamp_search_query_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;
  late OldEquipmentRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-scoped-search-');
    dbPath = p.join(tempDir.path, 'lamp.db');
    repository = OldEquipmentRepository();
  });

  tearDown(() async {
    await LampDatabaseProvider.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> seedCategoryComputers() async {
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);
      await db.insert('model', <String, Object?>{
        'model': 1,
        'model_name': 'Desktop PC',
        'category_name': 'Υπολογιστής',
      });
      await db.insert('model', <String, Object?>{
        'model': 2,
        'model_name': 'Laser Printer',
        'category_name': 'Εκτυπωτής',
      });
      await db.insert('equipment', <String, Object?>{
        'code': 100,
        'description': 'PC Γραφείου',
        'model': 1,
      });
      await db.insert('equipment', <String, Object?>{
        'code': 200,
        'description': 'Εκτυπωτής Α4',
        'model': 2,
      });
    } finally {
      await db.close();
    }
  }

  test(
    'κατηγορια: υπολογιστης χωρίς στοχευμένους όρους επιστρέφει 0',
    () async {
      await seedCategoryComputers();

      final result = await repository.globalSearch(
        dbPath,
        'κατηγορια: υπολογιστης',
        maxDisplay: 10,
      );

      expect(result.totalCount, 0);
    },
  );

  test(
    'κατηγορια: υπολογιστης με στοχευμένους όρους επιστρέφει υπολογιστές',
    () async {
      await seedCategoryComputers();
      final parsed = LampSearchQueryParser.parse('κατηγορια: υπολογιστης');

      final result = await repository.globalSearch(
        dbPath,
        'κατηγορια: υπολογιστης',
        maxDisplay: 10,
        scopedTerms: parsed.scopedTerms,
        freeText: parsed.freeText,
      );

      expect(result.totalCount, 1);
      expect(result.rows.single['code'], 100);
      expect(result.rows.single['category_name'], 'Υπολογιστής');
    },
  );

  test('συνδυασμός στοχευμένου όρου και ελεύθερου κειμένου', () async {
    await seedCategoryComputers();
    final parsed = LampSearchQueryParser.parse(
      'κατηγορια:υπολογιστης γραφειου',
    );

    final result = await repository.globalSearch(
      dbPath,
      'κατηγορια:υπολογιστης γραφειου',
      maxDisplay: 10,
      scopedTerms: parsed.scopedTerms,
      freeText: parsed.freeText,
    );

    expect(result.totalCount, 1);
    expect(result.rows.single['code'], 100);
  });

  test('απλό κείμενο χωρίς κλειδιά — ίδια συμπεριφορά με παλιά globalSearch',
      () async {
    await seedCategoryComputers();

    final legacy = await repository.globalSearch(
      dbPath,
      'γραφειου',
      maxDisplay: 10,
    );
    final parsed = LampSearchQueryParser.parse('γραφειου');
    final scoped = await repository.globalSearch(
      dbPath,
      'γραφειου',
      maxDisplay: 10,
      scopedTerms: parsed.scopedTerms,
      freeText: parsed.freeText,
    );

    expect(scoped.totalCount, legacy.totalCount);
    expect(
      scoped.rows.map((r) => r['code']).toList(),
      legacy.rows.map((r) => r['code']).toList(),
    );
  });
}
