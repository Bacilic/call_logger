// Τι διαβάζει ο χειριστής στην κόκκινη λωρίδα της φόρμας κλήσης.
//
// Η λωρίδα εμφανίζεται ΕΝΩ ο χειριστής δουλεύει — δεν επέλεξε αρχείο βάσης,
// δεν άλλαξε ρύθμιση. Μια συμβουλή τύπου «επαληθεύστε ότι επιλέξατε σωστό
// αρχείο .db» περιγράφει ενέργεια που δεν έκανε ποτέ, και τον στέλνει να
// ψάξει κάτι άσχετο (εύρημα ζωντανής δοκιμής 13/09/2026).
//
//   flutter test test/features/calls/lookup_load_error_message_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = LookupService.instance;

  LookupLoadResult resultFor(Object error) =>
      LookupLoadResult.fromError(service, error, StackTrace.current);

  /// Τα σφάλματα που έβγαλε στην πράξη η φθαρμένη βάση του νοσοκομείου.
  final realErrors = <String, Object>{
    'φθαρμένο περιεχόμενο': Exception(
      'SqfliteFfiException(sqlite_error: 11, SqliteException(11): while '
      'selecting from statement, database disk image is malformed, database '
      'disk image is malformed (code 11) Causing statement: '
      'SELECT COUNT(*) AS c FROM "users"',
    ),
    'ξένο αρχείο': Exception('SqliteException: file is not a database'),
    'κλειδωμένη βάση': Exception('SqliteException(5): database is locked'),
  };

  group('η συμβουλή ταιριάζει με αυτό που κάνει ο χειριστής', () {
    for (final entry in realErrors.entries) {
      test('${entry.key}: δεν του ζητά να ελέγξει αρχείο που δεν διάλεξε', () {
        final shown =
            '${resultFor(entry.value).loadError} '
            '${resultFor(entry.value).loadErrorDetails ?? ''}';

        expect(
          shown,
          isNot(contains('επιλέξατε')),
          reason:
              'Ο χειριστής δεν επέλεξε αρχείο — άνοιξε την εφαρμογή και '
              'πήγε να καταγράψει κλήση',
        );
      });
    }

    test('η διάγνωση παραμένει — αλλάζει η συμβουλή, όχι η αλήθεια', () {
      final result = resultFor(realErrors['φθαρμένο περιεχόμενο']!);
      expect(result.loadError, isNotNull);
      expect(
        result.loadError,
        contains('κατεστραμμένο'),
        reason: 'Το τι συνέβη λέγεται κανονικά· μόνο το τι να κάνει αλλάζει',
      );
    });

    test('η συμβουλή δείχνει πού να πάει ο χειριστής', () {
      final result = resultFor(realErrors['φθαρμένο περιεχόμενο']!);
      expect(
        result.loadErrorDetails,
        contains('Ρυθμίσεις βάσης'),
        reason: 'Χωρίς προορισμό, το μήνυμα είναι αδιέξοδο',
      );
    });

    test('άγνωστο σφάλμα δεν μένει χωρίς κείμενο', () {
      final result = resultFor(StateError('κάτι εντελώς άλλο'));
      expect(result.loadError, isNotNull);
      expect(result.loadError, isNotEmpty);
    });
  });
}
