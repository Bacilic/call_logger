// Το συμβόλαιο του πλήρους οδηγού επαναφοράς: ό,τι μπορεί να μπει στο
// αντίγραφο μπορεί και να μην επαναφερθεί — και το φίλτρο που το επιβάλλει
// κρίνει ΜΟΝΟ επιλογές, ποτέ εγκυρότητα περιεχομένου.
//
//   flutter test test/features/database/services/restore_selection_test.dart

import 'package:call_logger/core/config/app_config.dart';
import 'package:call_logger/core/services/building_map_storage.dart';
import 'package:call_logger/core/services/portable_lamp_storage.dart';
import 'package:call_logger/features/database/services/restore_plan.dart';
import 'package:call_logger/features/database/services/restore_selection.dart';
import 'package:flutter_test/flutter_test.dart';

String _maps(String file) =>
    '${BuildingMapStorage.backupZipMapsFolderName}/$file';
String _images(String file) => '${AppConfig.portableImagesDirName}/$file';
String _lexicon(String file) =>
    '${AppConfig.portableDictionariesDirName}/$file';
String _lamp(String file) =>
    '${PortableLampStorage.backupZipLampDbFolderName}/$file';

void main() {
  group('σε ποιο στοιχείο ανήκει η κάθε εγγραφή του αντιγράφου', () {
    test('κάθε γνωστός φάκελος βρίσκει το στοιχείο του', () {
      expect(
        restorePortablePartForEntry(_maps('a.webp')),
        RestorePortablePart.maps,
      );
      expect(
        restorePortablePartForEntry(_images('tool.png')),
        RestorePortablePart.toolImages,
      );
      expect(
        restorePortablePartForEntry(_lexicon('el.json')),
        RestorePortablePart.lexicon,
      );
      expect(
        restorePortablePartForEntry(_lamp('lampa.db')),
        RestorePortablePart.lampDatabase,
      );
    });

    test('η ανάποδη κάθετος των Windows δεν μπερδεύει την αναγνώριση', () {
      final windowsStyle = _maps('a.webp').replaceAll('/', r'\');
      expect(
        restorePortablePartForEntry(windowsStyle),
        RestorePortablePart.maps,
      );
    });

    test('ό,τι δεν ανήκει σε φάκελο στοιχείου δεν αποδίδεται σε κανένα', () {
      expect(restorePortablePartForEntry('Hospital.db'), isNull);
      expect(restorePortablePartForEntry('backup_manifest.json'), isNull);
    });
  });

  group('το φίλτρο επιβάλλει τις επιλογές του χρήστη', () {
    test('ξετσεκαρισμένο στοιχείο δεν περνά — ό,τι ζητήθηκε περνά', () {
      const wanted = {RestorePortablePart.maps, RestorePortablePart.lexicon};
      expect(restoreEntryIsWanted(_maps('a.webp'), wanted), isTrue);
      expect(restoreEntryIsWanted(_lexicon('el.json'), wanted), isTrue);
      expect(restoreEntryIsWanted(_images('tool.png'), wanted), isFalse);
      expect(restoreEntryIsWanted(_lamp('lampa.db'), wanted), isFalse);
    });

    test('καμία επιλογή σημαίνει κανένα φορητό αρχείο', () {
      const none = <RestorePortablePart>{};
      expect(restoreEntryIsWanted(_maps('a.webp'), none), isFalse);
      expect(restoreEntryIsWanted(_images('tool.png'), none), isFalse);
      expect(restoreEntryIsWanted(_lexicon('el.json'), none), isFalse);
      expect(restoreEntryIsWanted(_lamp('lampa.db'), none), isFalse);
    });

    test(
      'άγνωστη εγγραφή περνά ακόμη και με άδειες επιλογές — το φίλτρο δεν κρίνει εγκυρότητα',
      () {
        expect(
          restoreEntryIsWanted('Hospital.db', const <RestorePortablePart>{}),
          isTrue,
        );
      },
    );
  });

  group('τι δηλώνει η επιλογή του χρήστη', () {
    test('χωρίς προορισμό, η βάση δεν επαναφέρεται', () {
      const selection = RestoreSelection(
        destination: null,
        parts: {RestorePortablePart.maps},
      );
      expect(selection.restoresDatabase, isFalse);
      expect(selection.selectedCount, 1);
      expect(selection.isEmpty, isFalse);
    });

    test('η βάση μετρά ως ένα στοιχείο μαζί με τα υπόλοιπα', () {
      const selection = RestoreSelection(
        destination: RestoreDestinationChoice.currentDatabase,
        parts: {RestorePortablePart.maps, RestorePortablePart.lexicon},
      );
      expect(selection.restoresDatabase, isTrue);
      expect(selection.selectedCount, 3);
    });

    test('τίποτα επιλεγμένο = δεν υπάρχει δουλειά να γίνει', () {
      const selection = RestoreSelection(destination: null, parts: {});
      expect(selection.isEmpty, isTrue);
    });
  });
}
