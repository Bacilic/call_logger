import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_excel_validator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const validator = LampExcelValidator();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-excel-val-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('pathEmpty όταν η διαδρομή είναι κενή', () async {
    final result = await validator.validateExcelSource('');
    expect(result.status, LampExcelStatus.pathEmpty);
  });

  test('missing όταν το αρχείο δεν υπάρχει', () async {
    final missing = p.join(tempDir.path, 'gone.xlsx');
    final result = await validator.validateExcelSource(missing);
    expect(result.status, LampExcelStatus.missing);
    expect(result.userMessageGreek, contains('δεν βρέθηκε'));
  });

  test('notAFile όταν η διαδρομή είναι φάκελος', () async {
    final result = await validator.validateExcelSource(tempDir.path);
    expect(result.status, LampExcelStatus.notAFile);
  });

  test('wrongExtension για κατάληξη εκτός .xlsx/.xls', () async {
    final path = p.join(tempDir.path, 'data.csv');
    await File(path).writeAsString('a,b');
    final result = await validator.validateExcelSource(path);
    expect(result.status, LampExcelStatus.wrongExtension);
  });

  test('empty όταν το αρχείο έχει 0 byte', () async {
    final path = p.join(tempDir.path, 'empty.xlsx');
    await File(path).create();
    final result = await validator.validateExcelSource(path);
    expect(result.status, LampExcelStatus.empty);
  });

  test('ok για έγκυρο μη-κενό .xlsx', () async {
    final path = p.join(tempDir.path, 'valid.xlsx');
    await File(path).writeAsBytes(<int>[1, 2, 3]);
    final result = await validator.validateExcelSource(path);
    expect(result.status, LampExcelStatus.ok);
  });

  test('locked σε Windows με exclusive handle', () async {
    if (!Platform.isWindows) return;

    final path = p.join(tempDir.path, 'locked.xlsx');
    await File(path).writeAsBytes(<int>[1, 2, 3]);

    final raf = await File(path).open(mode: FileMode.read);
    await raf.lock(FileLock.exclusive);
    try {
      final result = await validator.validateExcelSource(path);
      expect(result.status, LampExcelStatus.locked);
      expect(result.userMessageGreek, contains('κλειδωμένο'));
    } finally {
      await raf.unlock();
      await raf.close();
    }
  });
}
