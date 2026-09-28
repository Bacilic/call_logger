// Unit tests: ο φρουρός που δεν αφήνει να ανοίξουν δύο διάλογοι αρχείου.
//
//   flutter test test/core/utils/file_picker_session_test.dart

import 'dart:async';

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
}
