import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../config/app_config.dart';
import '../updates/build_environment.dart';

/// Αποτέλεσμα σάρωσης για αδήλωτα αρχεία στον φάκελο πόρων.
class AssetResidueScan {
  const AssetResidueScan({this.removable = const <String>[]});

  /// Πλήρεις διαδρομές αρχείων που βρέθηκαν και επιτρέπεται να διαγραφούν.
  final List<String> removable;

  /// True μόνο όταν υπάρχει πραγματική δουλειά — τότε εμφανίζεται και το βήμα.
  bool get hasWork => removable.isNotEmpty;
}

/// Καθαρίζει αρχεία που έμειναν στον φάκελο πόρων χωρίς να ανήκουν πουθενά.
///
/// Το `flutter_assets` **δεν καθαρίζεται ποτέ**: το εργαλείο χτισίματος
/// προσθέτει και αντικαθιστά, αλλά δεν αφαιρεί. Μια εικόνα που μπήκε κάποτε με
/// προσωρινό όνομα και μετά μετονομάστηκε αφήνει πίσω της το παλιό αντίγραφο,
/// το οποίο ταξιδεύει αυτούσιο σε κάθε εγκατάσταση που φτιάχνεται από εκείνο
/// το σημείο και μετά — για πάντα, χωρίς να το φορτώνει ποτέ κανείς.
///
/// Ο κριτής δεν είναι το όνομα ούτε η κατάληξη, αλλά ο **κατάλογος πόρων** που
/// παράγει το ίδιο το χτίσιμο: ό,τι δεν είναι δηλωμένο εκεί, δεν μπορεί να
/// ζητηθεί ποτέ από την εφαρμογή. Η απόδειξη είναι απόλυτη, όχι ευρετική.
///
/// Η διαγραφή είναι **ευκαιριακή**: ό,τι δεν καθαριστεί σήμερα (κλειδωμένο
/// αρχείο, φάκελος χωρίς δικαίωμα εγγραφής) ξαναδοκιμάζεται στο επόμενο
/// άνοιγμα. Καμία αποτυχία δεν διακόπτει την εκκίνηση.
class AssetResidueCleaner {
  AssetResidueCleaner({
    required this.flutterAssetsDirectory,
    Future<Set<String>> Function()? loadDeclaredAssets,
    bool Function()? isWindows,
    bool Function()? isDevelopmentBuild,
  }) : loadDeclaredAssets = loadDeclaredAssets ?? _loadDeclaredAssetsFromBundle,
       isWindows = isWindows ?? (() => Platform.isWindows),
       isDevelopmentBuild = isDevelopmentBuild ?? (() => false);

  /// Ρίζα του `flutter_assets` της εγκατάστασης.
  final String flutterAssetsDirectory;

  /// Τα δηλωμένα κλειδιά πόρων, όπως `assets/call_logger.ico`.
  final Future<Set<String>> Function() loadDeclaredAssets;

  final bool Function() isWindows;
  final bool Function() isDevelopmentBuild;

  /// Ο **μόνος** υποφάκελος που σαρώνεται ποτέ.
  ///
  /// Στη ρίζα του `flutter_assets` ζουν τα κρίσιμα του κινητήρα — κατάλογοι
  /// πόρων και γραμματοσειρών, ο μεταγλωττισμένος κώδικας, οι άδειες. Κανένα
  /// από αυτά δεν είναι δηλωμένο ως πόρος, άρα ένας κριτής που κοιτούσε τη ρίζα
  /// θα τα έκρινε όλα σκουπίδια και θα κατέστρεφε την εγκατάσταση.
  static const String scannedSubdirectory = 'assets';

  /// Ο εργάτης της παραγωγής.
  factory AssetResidueCleaner.production() {
    return AssetResidueCleaner(
      flutterAssetsDirectory: p.join(
        AppConfig.applicationExecutableDirectory,
        'data',
        'flutter_assets',
      ),
      isDevelopmentBuild: () => BuildEnvironment.isDevelopmentBuild(),
    );
  }

  static Future<Set<String>> _loadDeclaredAssetsFromBundle() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest.listAssets().toSet();
  }

  /// Εντοπίζει τι περισσεύει. Δεν διαγράφει τίποτα.
  Future<AssetResidueScan> scan() async {
    if (!isWindows()) return const AssetResidueScan();

    // Σε build ανάπτυξης το εκτελέσιμο ζει μέσα στο `build\windows\...`. Εκεί το
    // σωστό εργαλείο είναι το `flutter clean`, και μια διαγραφή θα ξαναγύριζε
    // με το επόμενο χτίσιμο — καθαρίζουμε εγκαταστάσεις, όχι χώρους εργασίας.
    if (isDevelopmentBuild()) return const AssetResidueScan();

    final root = Directory(p.join(flutterAssetsDirectory, scannedSubdirectory));
    if (!await root.exists()) return const AssetResidueScan();

    final Set<String> declared;
    try {
      declared = await loadDeclaredAssets();
    } catch (_) {
      // Χωρίς κατάλογο δεν υπάρχει κριτής.
      return const AssetResidueScan();
    }

    // Κενός κατάλογος σημαίνει ότι κάτι πήγε στραβά στην ανάγνωση, ποτέ ότι η
    // εφαρμογή δεν έχει πόρους. Χωρίς αυτόν τον φρουρό, μια αποτυχία θα
    // χαρακτήριζε **ολόκληρο** τον φάκελο σκουπίδι.
    if (declared.isEmpty) return const AssetResidueScan();

    final removable = <String>[];
    try {
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        if (_isDeclared(declared, entity.path)) continue;
        removable.add(p.normalize(entity.path));
      }
    } catch (_) {
      // Ο φάκελος δεν διαβάζεται: δεν αγγίζουμε τίποτα.
      return const AssetResidueScan();
    }

    return AssetResidueScan(removable: removable);
  }

  /// Διαγράφει όσα σήμανε η [scan]. Επιστρέφει όσα όντως έφυγαν.
  Future<List<String>> clean(AssetResidueScan scan) async {
    final removed = <String>[];
    for (final path in scan.removable) {
      // Δεύτερος έλεγχος πριν από κάθε διαγραφή: η διαδρομή περνά ξανά από την
      // ίδια πύλη, ώστε καμία λίστα φτιαγμένη αλλού να μη γίνεται εντολή.
      if (!_isInsideScannedDirectory(path)) continue;
      try {
        final file = File(path);
        if (!await file.exists()) continue;
        await file.delete();
        removed.add(path);
      } catch (_) {
        // Ευκαιριακό: ξαναδοκιμάζεται στο επόμενο άνοιγμα.
      }
    }
    return removed;
  }

  /// True αν το αρχείο αντιστοιχεί σε δηλωμένο πόρο.
  ///
  /// Το όνομα στον δίσκο **δεν είναι πάντα** το κλειδί του καταλόγου: το
  /// εργαλείο χτισίματος κωδικοποιεί τους ειδικούς χαρακτήρες, οπότε το
  /// `lansweeper tickets.png` γράφεται ως `lansweeper%20tickets.png` ενώ ο
  /// κατάλογος κρατά το αρχικό όνομα, με το κενό. Σύγκριση μόνο κατά γράμμα θα
  /// έκρινε σκουπίδι μια εικόνα που η εφαρμογή όντως ζητά.
  ///
  /// Δεκτές και οι δύο μορφές: στην αμφιβολία **κρατάμε** το αρχείο. Ένα
  /// υπόλειμμα που επιβιώνει κοστίζει λίγα kilobyte· ένας πόρος που σβήστηκε
  /// κατά λάθος κοστίζει σπασμένη εγκατάσταση.
  bool _isDeclared(Set<String> declared, String filePath) {
    final key = _manifestKeyFor(filePath);
    if (declared.contains(key)) return true;
    try {
      return declared.contains(Uri.decodeFull(key));
    } on ArgumentError {
      // Όνομα με μεμονωμένο «%» που δεν είναι έγκυρη κωδικοποίηση.
      return false;
    }
  }

  /// Μετατρέπει διαδρομή δίσκου σε κλειδί καταλόγου (`assets/…`, με κάθετες).
  String _manifestKeyFor(String filePath) {
    final relative = p.relative(
      p.normalize(filePath),
      from: p.normalize(flutterAssetsDirectory),
    );
    return relative.replaceAll('\\', '/');
  }

  bool _isInsideScannedDirectory(String candidate) {
    final root = p.normalize(
      p.absolute(p.join(flutterAssetsDirectory, scannedSubdirectory)),
    );
    if (root.isEmpty || p.equals(root, p.rootPrefix(root))) return false;
    final file = p.normalize(p.absolute(candidate));
    final prefix = root.endsWith(p.separator) ? root : '$root${p.separator}';
    return file.startsWith(prefix);
  }
}
