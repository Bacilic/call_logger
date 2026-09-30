// Unit tests: ο φρουρός που δεν αφήνει να ανοίξουν δύο διάλογοι αρχείου.
//
//   flutter test test/core/utils/file_picker_session_test.dart

import 'dart:async';
import 'dart:io';

import 'package:call_logger/core/utils/file_picker_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'όσο ο διάλογος είναι ανοιχτός, δεύτερη κλήση δεν ανοίγει δεύτερο',
    () async {
      final firstReachedPicker = Completer<void>();
      final releaseFirst = Completer<String?>();
      var pickerCalls = 0;

      final first = FilePickerSession.run<String>(() {
        pickerCalls++;
        firstReachedPicker.complete();
        return releaseFirst.future;
      });
      await firstReachedPicker.future;
      expect(FilePickerSession.isActive, isTrue);

      final second = await FilePickerSession.run<String>(() async {
        pickerCalls++;
        return 'δεύτερη διαδρομή';
      });

      expect(pickerCalls, 1, reason: 'ο επιλογέας κλήθηκε μόνο μία φορά');
      expect(second.refocusedExisting, isTrue);
      expect(second.value, isNull);

      releaseFirst.complete('C:/κατόψεις/ισόγειο.png');
      final firstResult = await first;
      expect(firstResult.value, 'C:/κατόψεις/ισόγειο.png');
      expect(firstResult.refocusedExisting, isFalse);
    },
  );

  test('μετά το κλείσιμο, η επόμενη κλήση ανοίγει κανονικά', () async {
    await FilePickerSession.run<String>(() async => 'πρώτη');
    expect(FilePickerSession.isActive, isFalse);

    final again = await FilePickerSession.run<String>(() async => 'δεύτερη');
    expect(again.value, 'δεύτερη');
    expect(again.refocusedExisting, isFalse);
  });

  test('αποτυχία του επιλογέα ελευθερώνει τη συνεδρία', () async {
    await expectLater(
      FilePickerSession.run<String>(() async => throw StateError('σκασμός')),
      throwsStateError,
    );
    expect(FilePickerSession.isActive, isFalse);

    final after = await FilePickerSession.run<String>(() async => 'μετά');
    expect(after.value, 'μετά');
  });

  // Έλεγχος αρχιτεκτονικής: ο φρουρός δεν προστατεύει τίποτα αν τον
  // παρακάμπτουν. Κάθε άνοιγμα διαλόγου αρχείου στο lib/ περνά από αυτόν —
  // είτε μέσα στο ίδιο το `FilePickerSession.run(...)`, είτε σε συνάρτηση που
  // τρέχει ο φρουρός (π.χ. `FilePickerSession.run(_pickImpl)`).
  test(
    'κανένα σημείο της εφαρμογής δεν ανοίγει διάλογο αρχείου χωρίς φρουρό',
    () {
      final pickerCall = RegExp(
        r'FilePicker\.(pickFile|pickFiles|saveFile|getDirectoryPath)\(',
      );
      final functionStart = RegExp(
        r'^\s*(?:static\s+)?Future<.*>\s+(\w+)\s*\(',
      );
      final bypasses = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        if (path.endsWith('core/utils/file_picker_session.dart')) continue;
        final source = entity.readAsStringSync();
        if (!pickerCall.hasMatch(source)) continue;
        final lines = source.split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (!pickerCall.hasMatch(line) || line.trimLeft().startsWith('///')) {
            continue;
          }
          // (α) Άμεσα μέσα στον φρουρό.
          final before = lines.sublist(i < 3 ? 0 : i - 3, i + 1).join('\n');
          if (before.contains('FilePickerSession.run(')) continue;
          // (β) Μέσα σε συνάρτηση που την τρέχει ο φρουρός.
          String? enclosing;
          for (var j = i; j >= 0; j--) {
            final m = functionStart.firstMatch(lines[j]);
            if (m != null) {
              enclosing = m.group(1);
              break;
            }
          }
          if (enclosing != null &&
              RegExp(
                r'FilePickerSession\.run\(\s*(?:\(\)\s*=>\s*)?' +
                    RegExp.escape(enclosing) +
                    r'\b',
              ).hasMatch(source)) {
            continue;
          }
          bypasses.add('$path:${i + 1}');
        }
      }
      expect(
        bypasses,
        isEmpty,
        reason:
            'Αυτά τα σημεία ανοίγουν διάλογο αρχείου χωρίς τον φρουρό — '
            'δεύτερο κλικ όσο αργεί ο διάλογος ανοίγει δεύτερο παράθυρο.',
      );
    },
  );
}
