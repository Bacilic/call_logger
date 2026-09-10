// Οι δύο διάλογοι της ροής ανοίγουν ο ένας μετά τον άλλο για το ΙΔΙΟ στοιχείο:
// πρώτα η αποδέσμευση, μετά ο προορισμός. Οι τίτλοι τους οφείλουν να λένε το
// ίδιο πράγμα — αλλιώς ο χρήστης διαβάζει «προσωπικού» και αμέσως μετά
// «κοινόχρηστου» για το ίδιο μηχάνημα.
//
//   flutter test test/features/directory/asset_dialog_titles_follow_the_case_test.dart

import 'package:call_logger/features/directory/services/asset_disconnect_models.dart';
import 'package:call_logger/features/directory/services/asset_disconnect_texts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

void main() {
  group('Τίτλοι αποδέσμευσης και μεταφοράς', () {
    test('ο τίτλος της μεταφοράς ακολουθεί την περίπτωση', () {
      expect(
        transferDialogTitle(
          isPhone: false,
          mode: SharedAssetDisconnectMode.personalEquipment,
        ),
        'Μεταφορά προσωπικού εξοπλισμού',
      );
      expect(
        transferDialogTitle(
          isPhone: true,
          mode: SharedAssetDisconnectMode.personalPhone,
        ),
        'Μεταφορά προσωπικού τηλεφώνου',
      );
      expect(
        transferDialogTitle(
          isPhone: false,
          mode: SharedAssetDisconnectMode.sharedAsset,
        ),
        'Μεταφορά κοινόχρηστου εξοπλισμού',
      );
      expect(
        transferDialogTitle(
          isPhone: true,
          mode: SharedAssetDisconnectMode.sharedAsset,
        ),
        'Μεταφορά κοινόχρηστου τηλεφώνου',
      );
    });

    test('οι δύο τίτλοι δεν αποκλίνουν σε καμία περίπτωση', () {
      for (final mode in SharedAssetDisconnectMode.values) {
        for (final isPhone in [true, false]) {
          final phrase = assetKindPhrase(isPhone: isPhone, mode: mode);
          expect(
            disconnectDialogTitle(isPhone: isPhone, mode: mode),
            'Αποδέσμευση $phrase',
            reason: greekExpectMsg('Αποδέσμευση · $mode · τηλέφωνο=$isPhone'),
          );
          expect(
            transferDialogTitle(isPhone: isPhone, mode: mode),
            'Μεταφορά $phrase',
            reason: greekExpectMsg('Μεταφορά · $mode · τηλέφωνο=$isPhone'),
          );
        }
      }
    });
  });
}
