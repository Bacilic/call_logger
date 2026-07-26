import 'package:call_logger/core/utils/database_path_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const callsOnly =
      r'F:\flutter_projects\call_logger\Data Base\Δοκιμές\μόνο_κλήσεις.db';
  const callLogger =
      r'C:\Users\Bacilic\Documents\call_logger\DB\call_logger.db';

  test('ίδια διαδρομή με διαφορετικά πεζά-κεφαλαία', () {
    expect(
      databasePathsReferToSameFile(
        callsOnly,
        r'f:\flutter_projects\call_logger\data base\δοκιμές\μόνο_κλήσεις.db',
      ),
      isTrue,
    );
  });

  test(
    'ίδια διαδρομή με περιττά στοιχεία μονοπατιού που κανονικοποιούνται',
    () {
      expect(
        databasePathsReferToSameFile(
          callLogger,
          r'C:\Users\Bacilic\Documents\call_logger\DB\.\call_logger.db',
        ),
        isTrue,
      );
    },
  );

  test('δύο πραγματικά διαφορετικές διαδρομές', () {
    expect(databasePathsReferToSameFile(callsOnly, callLogger), isFalse);
  });
}
