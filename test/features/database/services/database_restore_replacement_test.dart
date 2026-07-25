// Ασφαλής αντικατάσταση αρχείου βάσης κατά την επαναφορά — χωρίς πραγματική βάση.
//
//   flutter test test/features/database/services/database_restore_replacement_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:call_logger/core/database/database_file_classifier.dart';
import 'package:call_logger/features/database/services/database_file_replacement.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('db_restore_repl_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'ξένη βάση στον στόχο: τίποτα δεν αγγίζεται και επιστρέφεται αποτυχία',
    () async {
      final target = p.join(tempDir.path, 'lampa.db');
      await File(target).writeAsString('FOREIGN_LAMP_BYTES');
      await File('$target-wal').writeAsString('wal');
      final beforeMain = await File(target).readAsBytes();
      final beforeWal = await File('$target-wal').readAsBytes();
      final listingBefore = await tempDir
          .list()
          .map((e) => p.basename(e.path))
          .toList();

      final result = await DatabaseFileReplacement.replaceWithBytes(
        targetDatabasePath: target,
        bytes: Uint8List.fromList('NEW_CALL_LOGGER'.codeUnits),
        classify: (_) async => DatabaseFileKind.lamp,
        now: DateTime(2026, 7, 25, 10, 0),
      );

      expect(result.success, isFalse);
      expect(result.message, contains('Λάμπας'));
      expect(await File(target).readAsBytes(), orderedEquals(beforeMain));
      expect(await File('$target-wal').readAsBytes(), orderedEquals(beforeWal));
      final listingAfter = await tempDir
          .list()
          .map((e) => p.basename(e.path))
          .toList();
      expect(listingAfter.toSet(), listingBefore.toSet());
    },
  );

  test(
    'επιτυχία: νέο περιεχόμενο στον στόχο και παλιό αρχείο μετονομασμένο',
    () async {
      final target = p.join(tempDir.path, 'call_logger.db');
      await File(target).writeAsString('OLD_DATABASE');
      final newBytes = Uint8List.fromList('NEW_DATABASE'.codeUnits);

      final result = await DatabaseFileReplacement.replaceWithBytes(
        targetDatabasePath: target,
        bytes: newBytes,
        classify: (_) async => DatabaseFileKind.callLogger,
        now: DateTime(2026, 7, 25, 14, 32),
      );

      expect(result.success, isTrue);
      expect(await File(target).readAsBytes(), orderedEquals(newBytes));
      expect(result.preRestoreBackupPath, isNotNull);
      final preserved = File(result.preRestoreBackupPath!);
      expect(await preserved.exists(), isTrue);
      expect(await preserved.readAsString(), 'OLD_DATABASE');
      expect(
        p.basename(result.preRestoreBackupPath!),
        'call_logger_pre_restore_25-07-2026.db',
      );
    },
  );

  test(
    'αποτυχία τελικής μετονομασίας: επανέρχεται το παλιό περιεχόμενο',
    () async {
      final target = p.join(tempDir.path, 'call_logger.db');
      await File(target).writeAsString('OLD_SAFE');
      final newBytes = Uint8List.fromList('SHOULD_NOT_STICK'.codeUnits);

      final result = await DatabaseFileReplacement.replaceWithBytes(
        targetDatabasePath: target,
        bytes: newBytes,
        classify: (_) async => DatabaseFileKind.callLogger,
        now: DateTime(2026, 7, 25, 14, 32),
        commitTempFile: (from, to) async {
          throw const FileSystemException(
            'simulated rename failure',
            null,
            OSError('Access denied', 5),
          );
        },
      );

      expect(result.success, isFalse);
      expect(result.message, contains('δεν χάθηκε'));
      expect(await File(target).readAsString(), 'OLD_SAFE');
      // Δεν πρέπει να μείνει προσωρινό ούτε «ορφανό» pre_restore.
      final leftovers = await tempDir
          .list()
          .map((e) => p.basename(e.path))
          .where((n) => n.contains('pre_restore') || n.contains('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    },
  );
}
