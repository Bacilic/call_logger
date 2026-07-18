import 'dart:io';

import 'package:call_logger/core/directory/phone_department_policy.dart';
import 'package:call_logger/core/utils/user_facing_error_messages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// Ελάχιστη υλοποίηση για δοκιμές — το `SqfliteDatabaseException` δεν εξάγεται δημόσια.
class _TestDatabaseException extends DatabaseException {
  _TestDatabaseException(super.message);

  @override
  int? getResultCode() => null;

  @override
  Object? get result => null;
}

void main() {
  group('humanizeUserFacingError', () {
    test('PhoneDepartmentPolicyException → μήνυμα με αριθμό, χωρίς Exception', () {
      final error = PhoneDepartmentPolicyException([
        const PhoneDepartmentConflict(
          phone: '2917',
          hasDepartmentLocationConflict: true,
          hasOtherUserOwners: false,
        ),
      ]);

      final message = humanizeUserFacingError(error);

      expect(message, contains('2917'));
      expect(message, contains('άλλο τμήμα'));
      expect(message.toLowerCase(), isNot(contains('exception')));
    });

    test('DatabaseException locked/busy → απασχολημένη βάση', () {
      final locked = _TestDatabaseException('database is locked');
      final busy = _TestDatabaseException('SQLITE_BUSY');

      expect(
        humanizeUserFacingError(locked),
        contains('απασχολημένη'),
      );
      expect(
        humanizeUserFacingError(busy),
        contains('απασχολημένη'),
      );
    });

    test('DatabaseException database_closed → ανανέωση σύνδεσης', () {
      final error = _TestDatabaseException('database_closed');

      expect(
        humanizeUserFacingError(error),
        contains('ανανεώθηκε'),
      );
    });

    test('FileSystemException → πρόσβαση αρχείου', () {
      final error = const FileSystemException('Permission denied', r'C:\tmp\db');

      expect(
        humanizeUserFacingError(error),
        contains('πρόσβαση'),
      );
    });

    test('άγνωστο σφάλμα → γενικό μήνυμα με τεχνικές λεπτομέρειες', () {
      final error = Exception('xyz_unique_detail_token_for_support');

      final message = humanizeUserFacingError(error);

      expect(message, startsWith('Απρόβλεπτο σφάλμα. Τεχνικές λεπτομέρειες:'));
      expect(message, contains('xyz_unique_detail_token_for_support'));
    });
  });
}
