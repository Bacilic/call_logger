@TestOn('windows')
library;

import 'dart:io';

import 'package:call_logger/core/utils/file_picker_initial_directory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Ο επιλογέας φακέλων των Windows σκάει («Η παράμετρος είναι εσφαλμένη»)
/// όταν του δοθεί αρχικός φάκελος που δεν ξεκινά από γράμμα δίσκου ή από
/// `\\διακομιστή\κοινόχρηστο`. Το πεδίο που τροφοδοτεί τον επιλογέα είναι
/// ελεύθερο κείμενο, άρα ό,τι κι αν πληκτρολογήσει ο χρήστης πρέπει να
/// καταλήγει σε φάκελο που ανοίγει.
void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('picker_initial_dir_');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('κείμενο χωρίς ρίζα δίσκου ή δικτύου → C:\\', () {
    for (final typed in <String>[
      r'POPINIO\CallLogger\Backups',
      'abc',
      r'.\Backups',
      r'\Windows',
    ]) {
      test('«$typed»', () {
        expect(initialDirectoryForFilePicker(typed), r'C:\');
      });
    }
  });

  test('διαδρομή με κάθετους ανοίγει τον ίδιο φάκελο με ανάποδες', () {
    final forward = temp.path.replaceAll(r'\', '/');

    expect(initialDirectoryForFilePicker(forward), p.normalize(temp.path));
  });

  test('ανύπαρκτος υποφάκελος → ο πλησιέστερος υπάρχων γονέας', () {
    final missing = p.join(temp.path, 'δεν_υπάρχει', 'ούτε_αυτός');

    expect(initialDirectoryForFilePicker(missing), p.normalize(temp.path));
  });

  test('κενό πεδίο → C:\\', () {
    expect(initialDirectoryForFilePicker('   '), r'C:\');
  });
}
