import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:call_logger/core/database/old_database/old_equipment_repository.dart';
import 'package:call_logger/features/lamp/controllers/lamp_issue_resolution_controller.dart';
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
    tempDir = await Directory.systemTemp.createTemp('lamp-serial-checker-test-');
    dbPath = p.join(tempDir.path, 'lamp.sqlite');
    repository = OldEquipmentRepository();
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);
      await db.insert('equipment', <String, Object?>{
        'code': 3200,
        'description': 'Εξοπλισμός Α',
        'model': 1,
        'serial_no': 'BARCODE-XYZ',
      });
      await db.insert('equipment', <String, Object?>{
        'code': 3201,
        'description': 'Εξοπλισμός Β',
        'model': 1,
        'serial_no': 'BARCODE-XYZ',
      });
    } finally {
      await db.close();
    }
  });

  tearDown(() async {
    await LampDatabaseProvider.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('lampSerialExistsCheckerFor', () {
    test('επιστρέφει true για υπαρκτό σειριακό', () async {
      final checker = lampSerialExistsCheckerFor(repository, dbPath);

      expect(await checker('BARCODE-XYZ', null), isTrue);
    });

    test('επιστρέφει false για ανύπαρκτο σειριακό', () async {
      final checker = lampSerialExistsCheckerFor(repository, dbPath);

      expect(await checker('ΜΟΝΑΔΙΚΟΣ-123', null), isFalse);
    });

    test('exceptCode εξαιρεί τον ίδιο κωδικό εξοπλισμού', () async {
      final checker = lampSerialExistsCheckerFor(repository, dbPath);

      await LampDatabaseProvider.instance.close();
      final db = await openDatabase(dbPath, singleInstance: false);
      try {
        await db.insert('equipment', <String, Object?>{
          'code': 3300,
          'description': 'Μοναδικός',
          'model': 1,
          'serial_no': 'UNIQUE-ONLY',
        });
      } finally {
        await db.close();
      }

      expect(await checker('UNIQUE-ONLY', 3300), isFalse);
      expect(await checker('UNIQUE-ONLY', null), isTrue);
      expect(await checker('BARCODE-XYZ', 3200), isTrue);
    });
  });
}
