// Η μέτρηση ελεύθερου χώρου δουλεύει για απλό χρήστη.
//
// Ως τις 02/10/2026 γινόταν με το `fsutil`, που θέλει δικαιώματα διαχειριστή:
// για απλό χρήστη απαντούσε «Error 5» και οι έλεγχοι χώρου έλεγαν σιωπηλά
// «όλα καλά». Το τεστ τρέχει ως ο χρήστης που το εκτελεί — όχι διαχειριστής.
//
//   flutter test test/core/utils/disk_free_space_test.dart

import 'dart:io';

import 'package:call_logger/core/utils/disk_free_space.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

void main() {
  test('τοπικός δίσκος: επιστρέφει τον ελεύθερο χώρο', () {
    final free = freeBytesOnLocalDrive(Directory.systemTemp.path);

    expect(
      free,
      isNotNull,
      reason: greekExpectMsg(
        'Η μέτρηση δεν θέλει διαχειριστή — αλλιώς ο έλεγχος χώρου σωπαίνει',
      ),
    );
    expect(free, greaterThan(0));
  }, skip: !Platform.isWindows);

  test('διαδρομή δικτύου: δεν μετριέται', () {
    expect(
      freeBytesOnLocalDrive(r'\\server\share\Hospital.db'),
      isNull,
      reason: greekExpectMsg(
        'Διακομιστής που δεν απαντά δεν πρέπει να παγώσει την εφαρμογή',
      ),
    );
  });
}
