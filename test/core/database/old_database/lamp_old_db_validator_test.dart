import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_old_db_validator.dart';
import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  group('LampOldDbValidator.pathsReferToSameFile', () {
    test('matches normalized paths on Windows', () {
      expect(
        LampOldDbValidator.pathsReferToSameFile(
          r'C:\Data\lampa_test.db',
          r'c:\data\lampa_test.db',
        ),
        isTrue,
      );
    });

    test('returns false when paths differ', () {
      expect(
        LampOldDbValidator.pathsReferToSameFile(
          r'C:\Data\a.db',
          r'C:\Data\b.db',
        ),
        isFalse,
      );
    });
  });

  group('LampOldDbValidator.validateReadPath', () {
    late LampOldDbValidator validator;

    setUp(() {
      validator = LampOldDbValidator();
    });

    test('fileMissing when the file is missing', () async {
      final result = await validator.validateReadPath(r'C:\missing\read.db');
      expect(result.status, LampOldDbStatus.fileMissing);
    });

    test('invalidPathFormat when path lacks .db extension', () async {
      final result = await validator.validateReadPath(r'F:\Data\old_base_test');
      expect(result.status, LampOldDbStatus.invalidPathFormat);
      expect(
        result.userMessageGreek,
        'Η διαδρομή πρέπει να δείχνει σε αρχείο με κατάληξη .db',
      );
    });

    test(
      'notOldEquipmentDb when equipment table exists but columns are wrong',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'lamp_val_wrong_cols',
        );
        addTearDown(() => dir.deleteSync(recursive: true));
        final dbPath = p.join(dir.path, 'wrong_structure.db');
        final db = await openDatabase(dbPath);
        await db.execute(
          'CREATE TABLE equipment (id INTEGER PRIMARY KEY, name TEXT)',
        );
        await db.close();

        final result = await validator.validateReadPath(dbPath);
        expect(result.status, LampOldDbStatus.notOldEquipmentDb);
        expect(result.userMessageGreek, contains('δομή'));
      },
    );

    test('ok when equipment table has expected Lamp columns', () async {
      final dir = await Directory.systemTemp.createTemp('lamp_val_valid');
      addTearDown(() => dir.deleteSync(recursive: true));
      final dbPath = p.join(dir.path, 'valid_lamp.db');
      final db = await openDatabase(dbPath);
      for (final statement in oldDatabaseCreateStatements) {
        await db.execute(statement);
      }
      await db.close();

      final result = await validator.validateReadPath(dbPath);
      expect(result.status, LampOldDbStatus.ok);
    });
  });

  group('LampOldDbValidator.validateDbPathFormat', () {
    test('returns null for empty path', () {
      expect(LampOldDbValidator.validateDbPathFormat(''), isNull);
      expect(LampOldDbValidator.validateDbPathFormat('   '), isNull);
    });

    test('returns null for valid .db path', () {
      expect(
        LampOldDbValidator.validateDbPathFormat(r'C:\Data\lampa_test.db'),
        isNull,
      );
    });

    test('returns error when extension is missing', () {
      expect(
        LampOldDbValidator.validateDbPathFormat(r'F:\Data\old_base_test'),
        'Η διαδρομή πρέπει να δείχνει σε αρχείο με κατάληξη .db',
      );
    });
  });
}
