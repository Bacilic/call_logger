import 'package:call_logger/core/database/database_init_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DatabaseInitResult.fromException — missingApplicationFile', () {
    test(
      'Περίπτωση Α: αποτυχία φόρτωσης sqlite3.dll → missingApplicationFile',
      () {
        final error = ArgumentError(
          "Failed to load dynamic library 'sqlite3.dll': "
          'The specified module could not be found. (error code: 126)',
        );

        final result = DatabaseInitResult.fromException(error);

        expect(result.status, DatabaseStatus.applicationError);
        expect(result.recoveryKind, DatabaseInitRecoveryKind.missingApplicationFile);
        expect(result.message, contains('sqlite3.dll'));
        expect(result.message!.toLowerCase(), contains('επανεγκατάσταση'));
      },
    );

    test(
      'Περίπτωση Β: Unable to load asset NativeAssetsManifest.json → '
      'missingApplicationFile',
      () {
        final error = StateError(
          'Unable to load asset: NativeAssetsManifest.json',
        );

        final result = DatabaseInitResult.fromException(error);

        expect(result.status, DatabaseStatus.applicationError);
        expect(result.recoveryKind, DatabaseInitRecoveryKind.missingApplicationFile);
        expect(
          result.message,
          anyOf(
            contains('NativeAssetsManifest.json'),
            contains('NativeAssetsManifest'),
          ),
        );
        expect(result.message!.toLowerCase(), contains('επανεγκατάσταση'));
      },
    );

    test(
      'Περίπτωση Α2 (ΠΡΑΓΜΑΤΙΚΟ σενάριο): λείπει sqlite3.dll ή '
      'NativeAssetsManifest.json → το ορατό σφάλμα είναι το δευτερογενές '
      '«databaseFactory not initialized» → missingApplicationFile',
      () {
        // Ακριβές κείμενο που εμφανίστηκε στην οθόνη σφάλματος (δοκιμή χρήστη
        // 24/07): το πρωτογενές σφάλμα με το όνομα αρχείου καταπίνεται στο
        // σιωπηλό catch του main.dart, οπότε φτάνει μόνο αυτό εδώ.
        final error = StateError(
          'databaseFactory not initialized\n'
          'databaseFactory is only initialized when using sqflite. '
          'When using `sqflite_common_ffi`',
        );

        final result = DatabaseInitResult.fromException(error);

        expect(result.status, DatabaseStatus.applicationError);
        expect(
          result.recoveryKind,
          DatabaseInitRecoveryKind.missingApplicationFile,
        );
        expect(result.message!.toLowerCase(), contains('επανεγκατάσταση'));
      },
    );

    test(
      'Περίπτωση Γ: σκέτο StateError χωρίς asset markers → generic fallback',
      () {
        final error = StateError('No element');

        final result = DatabaseInitResult.fromException(error);

        expect(result.status, DatabaseStatus.applicationError);
        expect(
          result.recoveryKind,
          isNot(DatabaseInitRecoveryKind.missingApplicationFile),
        );
        expect(result.recoveryKind, DatabaseInitRecoveryKind.generic);
        expect(result.message, contains('StateError'));
      },
    );
  });
}
