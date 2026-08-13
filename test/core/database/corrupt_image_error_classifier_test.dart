// Αναγνώριση του σφάλματος «disk image is malformed» ως πιθανής ένδειξης
// αντικατάστασης αρχείου.
//
// Το σφάλμα δεν αποδεικνύει τίποτα μόνο του — οδηγεί σε έλεγχο ταυτότητας.
// Αυτό που ελέγχεται εδώ είναι ότι το αναγνωρίζουμε όταν έρθει, και ότι δεν
// μπερδεύουμε άσχετα σφάλματα με αυτό.
//
//   flutter test test/core/database/corrupt_image_error_classifier_test.dart

import 'package:call_logger/core/database/database_file_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('το πραγματικό σφάλμα του περιστατικού αναγνωρίζεται', () {
    // Αυτούσιο από το σφάλμα που εμφανίστηκε στη δοκιμή 13/08/2026, όταν ο
    // Κατάλογος διάβασε τη βάση αμέσως μετά την αντικατάσταση του αρχείου.
    const raw =
        'SqfliteFfiException(sqlite_error: 11, , SqliteException(11): while '
        'selecting from statement, database disk image is malformed, database '
        'disk image is malformed (code 11) Causing statement: SELECT * FROM '
        'users WHERE COALESCE(is_deleted, 0) = ?, parameters: 0})';

    expect(looksLikeCorruptImageError(raw), isTrue);
  });

  test('αναγνωρίζει τις γνωστές διατυπώσεις του SQLite', () {
    expect(
      looksLikeCorruptImageError('database disk image is malformed'),
      isTrue,
    );
    expect(looksLikeCorruptImageError('SQLITE_CORRUPT: something'), isTrue);
    expect(
      looksLikeCorruptImageError('malformed database schema'),
      isTrue,
    );
  });

  test('δεν μπερδεύει άσχετα σφάλματα', () {
    expect(
      looksLikeCorruptImageError('no such table: users'),
      isFalse,
      reason: 'Λείπει πίνακας — άλλο πρόβλημα, άλλη απάντηση.',
    );
    expect(
      looksLikeCorruptImageError('database is locked'),
      isFalse,
      reason: 'Το κλείδωμα δεν έχει σχέση με αντικατάσταση αρχείου.',
    );
    expect(
      looksLikeCorruptImageError('RenderFlex overflowed by 42 pixels'),
      isFalse,
    );
    expect(
      looksLikeCorruptImageError(
        'FormatException: Unexpected character (at character 1)',
      ),
      isFalse,
    );
    expect(
      looksLikeCorruptImageError(
        'utf8.decode(bytes, allowMalformed: true) failed',
      ),
      isFalse,
      reason:
          'Το «malformed» χωρίς αναφορά σε βάση είναι άλλης φύσης σφάλμα — '
          'δεν επιτρέπεται να στέλνει τον χρήστη σε μήνυμα για τη βάση.',
    );
  });
}
