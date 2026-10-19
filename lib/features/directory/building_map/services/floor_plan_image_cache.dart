import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/database/building_map_repository.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/models/building_map_floor.dart';

/// Το τοπικό αντίγραφο κάθε κάτοψης σε αυτόν τον σταθμό.
///
/// Η εικόνα ζει στην κοινή βάση· κάθε σταθμός την κατεβάζει **μία φορά** και
/// την κρατά σε αρχείο με όνομα το αποτύπωμά της. Όσο το αποτύπωμα στη λίστα
/// ορόφων μένει ίδιο, η εικόνα δεν ξαναζητιέται από το δίκτυο· μόλις ο
/// διαχειριστής ανεβάσει νέα, το αποτύπωμα αλλάζει και κατεβαίνει η νέα.
///
/// Το όνομα από το αποτύπωμα κάνει το αντίγραφο ασφαλές και σε αλλαγή βάσης:
/// ίδια bytes σε δύο βάσεις μοιράζονται το ίδιο αρχείο, διαφορετικά bytes
/// ποτέ δεν συγχέονται.
class FloorPlanImageCache {
  FloorPlanImageCache({required this.directory, required this.loadImage});

  static final FloorPlanImageCache instance = FloorPlanImageCache(
    directory: () async => p.join(
      (await getApplicationSupportDirectory()).path,
      'floor_plan_cache',
    ),
    loadImage: (floorId) async => BuildingMapRepository(
      await DatabaseHelper.instance.database,
    ).readFloorImage(floorId),
  );

  /// Ο τοπικός φάκελος των αντιγράφων.
  final Future<String> Function() directory;

  /// Η ανάγνωση της εικόνας από τη βάση.
  final Future<({Uint8List bytes, String hash})?> Function(int floorId)
  loadImage;

  /// Μία μόνο λήψη ανά εικόνα, όσες οθόνες κι αν τη ζητήσουν ταυτόχρονα.
  final Map<String, Future<File?>> _inFlight = {};

  /// Το τοπικό αρχείο της κάτοψης· `null` όταν δεν έχει ανέβει ή δεν
  /// κατέβηκε (π.χ. η βάση δεν απαντά).
  Future<File?> fileFor(BuildingMapFloor floor) {
    final hash = floor.imageHash;
    if (hash == null) return Future.value(null);
    return _inFlight.putIfAbsent(hash, () async {
      try {
        return await _materialize(floor.id, hash);
      } on Exception {
        // Η λήψη τρέχει στο παρασκήνιο κάθε οθόνης που δείχνει κάτοψη, ακόμη
        // και της φόρμας κλήσης: βάση που δεν απαντά ή δίσκος που αρνείται
        // δεν ρίχνουν την εφαρμογή — η οθόνη γράφει «δεν φορτώθηκε», και το
        // επόμενο άνοιγμα ξαναδοκιμάζει.
        return null;
      } finally {
        _inFlight.remove(hash);
      }
    });
  }

  Future<File?> _materialize(int floorId, String hash) async {
    final dir = await directory();
    final file = File(p.join(dir, '$hash.jpg'));
    if (await file.exists()) return file;

    final loaded = await loadImage(floorId);
    if (loaded == null) return null;
    // Αν στο μεταξύ ανέβηκε άλλη εικόνα, κρατιέται αυτή που ήρθε, με το δικό
    // της όνομα — ποτέ bytes κάτω από ξένο αποτύπωμα.
    final target = loaded.hash == hash
        ? file
        : File(p.join(dir, '${loaded.hash}.jpg'));
    if (await target.exists()) return target;

    await Directory(dir).create(recursive: true);
    // Πρώτα σε προσωρινό και μετά μετονομασία: ένα μισογραμμένο αρχείο (π.χ.
    // κλείσιμο στη μέση) δεν πρέπει ποτέ να περάσει για έτοιμη εικόνα.
    final temp = File('${target.path}.part');
    await temp.writeAsBytes(loaded.bytes, flush: true);
    return temp.rename(target.path);
  }
}
