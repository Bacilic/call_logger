// Ο καθαριστής υπολειμμάτων του φακέλου πόρων ΔΙΑΓΡΑΦΕΙ αρχεία. Εδώ δεν
// ελέγχεται μόνο ότι κάνει τη δουλειά του, αλλά κυρίως ότι **δεν** την κάνει
// όταν δεν πρέπει: μια λάθος διαγραφή εδώ καταστρέφει την εγκατάσταση.
//
//   flutter test test/core/services/asset_residue_cleaner_test.dart

import 'dart:io';

import 'package:call_logger/core/services/asset_residue_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;
  late String flutterAssets;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('asset_residue_');
    flutterAssets = p.join(tempRoot.path, 'data', 'flutter_assets');
    await Directory(p.join(flutterAssets, 'assets')).create(recursive: true);
  });

  tearDown(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  /// Δημιουργεί αρχείο κάτω από το `flutter_assets` και επιστρέφει τη διαδρομή.
  Future<String> makeFile(String relative) async {
    final path = p.join(flutterAssets, p.joinAll(relative.split('/')));
    await Directory(p.dirname(path)).create(recursive: true);
    await File(path).writeAsString('περιεχόμενο');
    return path;
  }

  AssetResidueCleaner cleanerWith(
    Set<String> declared, {
    bool developmentBuild = false,
    bool windows = true,
    Future<Set<String>> Function()? loader,
  }) {
    return AssetResidueCleaner(
      flutterAssetsDirectory: flutterAssets,
      loadDeclaredAssets: loader ?? (() async => declared),
      isWindows: () => windows,
      isDevelopmentBuild: () => developmentBuild,
    );
  }

  group('εντοπισμός', () {
    test('αδήλωτο αρχείο σημειώνεται προς διαγραφή', () async {
      final junk = await makeFile('assets/18628505');
      await makeFile('assets/call_logger.ico');

      final scan = await cleanerWith({'assets/call_logger.ico'}).scan();

      expect(scan.hasWork, isTrue);
      expect(scan.removable, [p.normalize(junk)]);
    });

    test('δηλωμένο αρχείο δεν αγγίζεται ποτέ', () async {
      await makeFile('assets/call_logger.ico');

      final scan = await cleanerWith({'assets/call_logger.ico'}).scan();

      expect(scan.hasWork, isFalse);
    });

    // Πραγματικό περιστατικό: το `lansweeper tickets.png` γράφεται στον δίσκο
    // ως `lansweeper%20tickets.png`, ενώ ο κατάλογος κρατά το όνομα με το κενό.
    // Σύγκριση κατά γράμμα θα έσβηνε εικόνα που η εφαρμογή όντως ζητά.
    test('όνομα με κενό: το κωδικοποιημένο αρχείο αναγνωρίζεται', () async {
      await makeFile('assets/lansweeper%20tickets.png');

      final scan = await cleanerWith({'assets/lansweeper tickets.png'}).scan();

      expect(
        scan.hasWork,
        isFalse,
        reason: 'το αρχείο είναι δηλωμένο, απλώς με κωδικοποιημένο όνομα',
      );
    });

    test('όνομα με άκυρο «%» δεν ρίχνει τον έλεγχο', () async {
      final junk = await makeFile('assets/100%κάτι');

      final scan = await cleanerWith({'assets/call_logger.ico'}).scan();

      expect(scan.removable, [p.normalize(junk)]);
    });

    test('ο κανόνας ισχύει και σε υποφακέλους', () async {
      await makeFile('assets/splash/splash-1.webp');
      final junk = await makeFile('assets/splash/παλιό-αντίγραφο');

      final scan = await cleanerWith({'assets/splash/splash-1.webp'}).scan();

      expect(scan.removable, [p.normalize(junk)]);
    });
  });

  group('φρουροί — πότε ΔΕΝ αγγίζεται τίποτα', () {
    // Ο πιο επικίνδυνος φρουρός: κενός κατάλογος σημαίνει αποτυχία ανάγνωσης,
    // ποτέ «η εφαρμογή δεν έχει πόρους». Χωρίς αυτόν, σβήνει ο κόσμος.
    test('κενός κατάλογος πόρων δεν κάνει τα πάντα σκουπίδια', () async {
      await makeFile('assets/call_logger.ico');
      await makeFile('assets/splash/splash-1.webp');

      final scan = await cleanerWith(<String>{}).scan();

      expect(scan.hasWork, isFalse);
    });

    test('αποτυχία ανάγνωσης του καταλόγου δεν διαγράφει τίποτα', () async {
      await makeFile('assets/18628505');

      final scan = await cleanerWith(
        const <String>{},
        loader: () async => throw const FileSystemException('χωρίς κατάλογο'),
      ).scan();

      expect(scan.hasWork, isFalse);
    });

    test('σε build ανάπτυξης δεν καθαρίζεται τίποτα', () async {
      await makeFile('assets/18628505');

      final scan = await cleanerWith(
        {'assets/άλλο.png'},
        developmentBuild: true,
      ).scan();

      expect(scan.hasWork, isFalse);
    });

    test('εκτός Windows δεν καθαρίζεται τίποτα', () async {
      await makeFile('assets/18628505');

      final scan = await cleanerWith(
        {'assets/άλλο.png'},
        windows: false,
      ).scan();

      expect(scan.hasWork, isFalse);
    });

    // Στη ρίζα του flutter_assets ζουν τα κρίσιμα του κινητήρα. Κανένα δεν
    // είναι δηλωμένο ως πόρος: ένας κριτής που κοιτούσε εκεί θα τα έσβηνε όλα.
    test('τα κρίσιμα αρχεία της ρίζας μένουν άθικτα', () async {
      final manifest = await makeFile('AssetManifest.bin');
      final kernel = await makeFile('kernel_blob.bin');
      final fonts = await makeFile('FontManifest.json');
      await makeFile('assets/18628505');

      final cleaner = cleanerWith({'assets/call_logger.ico'});
      await cleaner.clean(await cleaner.scan());

      expect(await File(manifest).exists(), isTrue);
      expect(await File(kernel).exists(), isTrue);
      expect(await File(fonts).exists(), isTrue);
    });
  });

  group('διαγραφή', () {
    test('φεύγει το αδήλωτο, μένει το δηλωμένο', () async {
      final junk = await makeFile('assets/18628505');
      final keep = await makeFile('assets/call_logger.ico');

      final cleaner = cleanerWith({'assets/call_logger.ico'});
      final removed = await cleaner.clean(await cleaner.scan());

      expect(removed, [p.normalize(junk)]);
      expect(await File(junk).exists(), isFalse);
      expect(await File(keep).exists(), isTrue);
    });

    // Η λίστα δεν είναι εντολή: κάθε διαδρομή περνά ξανά από την πύλη, ώστε μια
    // λίστα φτιαγμένη αλλού να μη μπορεί ποτέ να στοχεύσει έξω από τον φάκελο.
    test('διαδρομή εκτός του σαρωμένου φακέλου αγνοείται', () async {
      final outsider = p.join(tempRoot.path, 'πολύτιμο.db');
      await File(outsider).writeAsString('δεδομένα');

      final removed = await cleanerWith({
        'assets/call_logger.ico',
      }).clean(AssetResidueScan(removable: [outsider]));

      expect(removed, isEmpty);
      expect(await File(outsider).exists(), isTrue);
    });

    test('αρχείο που χάθηκε στο μεταξύ δεν ρίχνει τον καθαρισμό', () async {
      final junk = await makeFile('assets/18628505');
      final cleaner = cleanerWith({'assets/call_logger.ico'});
      final scan = await cleaner.scan();
      await File(junk).delete();

      expect(await cleaner.clean(scan), isEmpty);
    });
  });
}
