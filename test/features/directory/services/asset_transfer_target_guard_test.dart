// Φρουρός προορισμού: κανένα στοιχείο δεν μεταφέρεται σε τμήμα που διαγράφεται
// στην ίδια πράξη — ούτε αν ο χρήστης γράψει το όνομά του με το χέρι.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/services/asset_transfer_target_guard_test.dart

import 'package:call_logger/features/directory/services/asset_transfer_target_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Απαγορευμένος προορισμός', () {
    test('όνομα εκτός λίστας: κανένα εμπόδιο', () {
      expect(
        blockedTransferTargetMessage(
          typedName: 'Πληροφορική',
          blockedNames: const ['Δοκιμαστικό', 'Αιμοδοσία'],
        ),
        isNull,
      );
    });

    test('ακριβές όνομα τμήματος που διαγράφεται: μήνυμα με το όνομα', () {
      expect(
        blockedTransferTargetMessage(
          typedName: 'Δοκιμαστικό',
          blockedNames: const ['Δοκιμαστικό'],
        ),
        'Το τμήμα «Δοκιμαστικό» διαγράφεται σε αυτή την πράξη — τα στοιχεία θα '
        'χάνονταν. Διαλέξτε άλλο προορισμό ή αφαιρέστε το από τη λίστα '
        'διαγραφής.',
      );
    });

    test('η σύγκριση αγνοεί πεζά/κεφαλαία, τόνους και κενά στις άκρες', () {
      expect(
        blockedTransferTargetMessage(
          typedName: '  δοκιμαστικο  ',
          blockedNames: const ['Δοκιμαστικό'],
        ),
        isNotNull,
      );
    });

    test('κενό κείμενο: κανένα εμπόδιο — δεν έχει γραφτεί τίποτα ακόμα', () {
      expect(
        blockedTransferTargetMessage(
          typedName: '   ',
          blockedNames: const ['Δοκιμαστικό'],
        ),
        isNull,
      );
    });

    test('κενή λίστα απαγορευμένων: κανένα εμπόδιο', () {
      expect(
        blockedTransferTargetMessage(
          typedName: 'Δοκιμαστικό',
          blockedNames: const [],
        ),
        isNull,
      );
    });

    test('ανώνυμα τμήματα στη λίστα δεν μπλοκάρουν τα πάντα', () {
      expect(
        blockedTransferTargetMessage(
          typedName: 'Πληροφορική',
          blockedNames: const ['', '   '],
        ),
        isNull,
      );
    });
  });
}
