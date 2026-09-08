// Το συμβόλαιο: **η τοπική βάση που προσφέρεται και η τοπική βάση που ανοίγει
// είναι η ίδια — μία απάντηση, όχι δύο ανεξάρτητοι υπολογισμοί.**
//
// Το κουμπί «Χρήση τοπικής βάσης» κοίταζε μία σταθερή διαδρομή (την
// προεπιλεγμένη), που σε εγκατάσταση με δικτυακή βάση είναι άδεια — οπότε δεν
// εμφανιζόταν ποτέ. Και η αποδοχή ξαναϋπολόγιζε τη διαδρομή μόνη της, οπότε
// ακόμη κι αν εμφανιζόταν, θα άνοιγε άλλο αρχείο.
//
//   flutter test test/core/database/local_database_offer_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_path_resolution.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LocalDatabaseSessionFallback.forget();
    temp = await Directory.systemTemp.createTemp('local_offer_');
  });

  tearDown(() async {
    LocalDatabaseSessionFallback.forget();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<String> makeDb(String name) async {
    final path = p.join(temp.path, name);
    await File(path).writeAsString('όχι πραγματική βάση, αρκεί να υπάρχει');
    return path;
  }

  group('η προσφορά βρίσκει ό,τι ΥΠΑΡΧΕΙ', () {
    test('προσφέρεται η πρόσφατη τοπική βάση, όχι η άδεια προεπιλογή',
        () async {
      final existing = await makeDb('call_logger.db');
      await SettingsService().recordVerifiedDatabasePath(existing);

      final offer = await localDatabaseOffer();

      expect(
        offer.exists,
        isTrue,
        reason:
            'Υπάρχει τοπική βάση στις πρόσφατες, αλλά η προσφορά κοίταξε μόνο '
            'την προεπιλεγμένη διαδρομή — το κουμπί δεν θα εμφανιστεί ποτέ.',
      );
      expect(offer.path, existing);
      expect(offer.lastModified, isNotNull);
    });

    test('χωρίς καμία τοπική βάση, δεν προσφέρεται τίποτα', () async {
      final offer = await localDatabaseOffer();

      expect(offer.exists, isFalse);
    });

    test('οι δικτυακές διαδρομές ΔΕΝ προσφέρονται ποτέ ως τοπικές', () async {
      await SettingsService().recordVerifiedDatabasePath(
        r'\\gnk.local\Departments\Data Base\call_logger.db',
      );

      final offer = await localDatabaseOffer();

      // Δεν είναι τοπικές, και ο έλεγχος ύπαρξης πάνω τους μπορεί να κρεμάσει
      // την ίδια την οθόνη που υπάρχει για να δώσει διέξοδο.
      expect(offer.exists, isFalse);
    });

    test('προτιμάται η πιο πρόσφατα χρησιμοποιημένη', () async {
      final older = await makeDb('palia.db');
      final newer = await makeDb('prosfati.db');
      final settings = SettingsService();
      await settings.recordVerifiedDatabasePath(older);
      await settings.recordVerifiedDatabasePath(newer);

      final offer = await localDatabaseOffer();

      expect(offer.path, newer);
    });

    test('πρόσφατη που έχει σβηστεί προσπερνιέται', () async {
      final deleted = p.join(temp.path, 'svismeni.db');
      final alive = await makeDb('zontani.db');
      final settings = SettingsService();
      await settings.recordVerifiedDatabasePath(alive);
      await settings.recordVerifiedDatabasePath(deleted);

      final offer = await localDatabaseOffer();

      expect(offer.path, alive);
    });
  });

  group('η προσφορά και η ενέργεια δείχνουν στο ΙΔΙΟ αρχείο', () {
    const unreachableUnc =
        r'\\gnk.local\Departments\Data Base\call_logger.db';

    test('ανοίγει ακριβώς η βάση που δέχτηκε ο χρήστης', () async {
      final offered = await makeDb('call_logger.db');
      await SettingsService().recordVerifiedDatabasePath(offered);

      final offer = await localDatabaseOffer();
      LocalDatabaseSessionFallback.accept(unreachableUnc, offer.path);

      final resolved = await resolveEffectiveDatabasePath(unreachableUnc);

      expect(resolved.outcome, DatabasePathResolution.resolved);
      expect(
        resolved.pathToOpen,
        offer.path,
        reason:
            'Ο χρήστης είδε μια ημερομηνία στο κουμπί και άνοιξε άλλο αρχείο.',
      );
    });

    test('χωρίς αποδοχή δεν ανοίγει τίποτα τοπικό', () async {
      final resolved = await resolveEffectiveDatabasePath(unreachableUnc);

      expect(resolved.outcome, DatabasePathResolution.networkUnreachable);
    });
  });
}
