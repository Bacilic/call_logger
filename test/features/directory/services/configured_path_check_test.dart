// Έλεγχος ρυθμισμένων διαδρομών: ποιες από τις διαδρομές των ρυθμίσεων δεν
// υπάρχουν σε αυτό το μηχάνημα — ώστε η βάση που ταξιδεύει δουλειά ↔ σπίτι
// να μη «σέρνει» άκυρες διαδρομές που ανακαλύπτονται μία-μία.
//
//   flutter test test/features/directory/services/configured_path_check_test.dart

import 'dart:io';

import 'package:call_logger/features/directory/services/configured_path_check.dart';
import 'package:flutter_test/flutter_test.dart';

ConfiguredPathEntry _entry(String path, {bool inDb = true}) {
  return ConfiguredPathEntry(
    settingName: 'Δοκιμαστική ρύθμιση',
    path: path,
    storedInDatabase: inDb,
    fixLocation: 'Ρυθμίσεις → Δοκιμή',
  );
}

void main() {
  group('evaluateConfiguredPaths', () {
    test('κρατά μόνο τις διαδρομές που δεν υπάρχουν', () async {
      final entries = [
        _entry(r'C:\ok\backups'),
        _entry(r'\\gnk.local\Departments\TPO\Backups'),
        _entry(r'C:\ok\tool.exe'),
      ];
      final invalid = await evaluateConfiguredPaths(
        entries,
        (path) async => path.startsWith(r'C:\ok'),
      );
      expect(invalid, hasLength(1));
      expect(invalid.single.path, r'\\gnk.local\Departments\TPO\Backups');
    });

    test('κενή διαδρομή = «χωρίς ρύθμιση», ποτέ εύρημα', () async {
      final invalid = await evaluateConfiguredPaths(
        [_entry(''), _entry('   ')],
        (_) async => false,
      );
      expect(invalid, isEmpty);
    });

    test('όλα έγκυρα → κενή λίστα', () async {
      final invalid = await evaluateConfiguredPaths(
        [_entry(r'C:\a'), _entry(r'C:\b', inDb: false)],
        (_) async => true,
      );
      expect(invalid, isEmpty);
    });
  });

  group('configuredPathExistsOnThisMachine', () {
    test('υπαρκτός φάκελος και υπαρκτό αρχείο → true', () async {
      final dir = await Directory.systemTemp.createTemp('path_check_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}x.txt');
      await file.writeAsString('x');

      expect(await configuredPathExistsOnThisMachine(dir.path), isTrue);
      expect(await configuredPathExistsOnThisMachine(file.path), isTrue);
    });

    test('ανύπαρκτη διαδρομή → false, χωρίς εξαίρεση', () async {
      expect(
        await configuredPathExistsOnThisMachine(
          r'C:\call_logger_test\δεν\υπάρχει\πουθενά',
        ),
        isFalse,
      );
    });
  });
}
