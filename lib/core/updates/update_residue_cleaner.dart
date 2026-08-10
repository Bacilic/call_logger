import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/app_config.dart';
import 'build_environment.dart';
import 'update_installer_service.dart';
import 'update_providers.dart';

/// Αποτέλεσμα σάρωσης για υπολείμματα προηγούμενης ενημέρωσης.
class UpdateResidueScan {
  const UpdateResidueScan({
    this.removable = const <String>[],
    this.protected = const <String>[],
  });

  /// Πλήρεις διαδρομές φακέλων που βρέθηκαν και επιτρέπεται να διαγραφούν.
  final List<String> removable;

  /// Φάκελοι που βρέθηκαν αλλά **δεν** αγγίζονται (εκκρεμότητα ή φρέσκο ίχνος).
  final List<String> protected;

  /// True μόνο όταν υπάρχει πραγματική δουλειά — τότε εμφανίζεται και το βήμα.
  bool get hasWork => removable.isNotEmpty;
}

/// Καθαρίζει τα υπολείμματα που αφήνει πίσω της μια ολοκληρωμένη ενημέρωση.
///
/// Ο μηχανισμός ενημέρωσης δημιουργεί δύο φακέλους στον κατάλογο εγκατάστασης:
/// το `.update_staging` (πακέτο, αποσυμπιεσμένη νέα έκδοση, `updater.cmd`) και
/// το `.update_backup` (αντίγραφο της προηγούμενης έκδοσης, για επιστροφή αν η
/// ενημέρωση αποτύχει). Κανένας από τους δύο δεν καθαρίζεται ποτέ μόνος του:
/// το `updater.cmd` τρέχει **μέσα** από το staging και δεν μπορεί να διαγράψει
/// τον εαυτό του, ενώ το backup δεν το αφορά κανένα σημείο του κώδικα. Έτσι
/// συσσωρεύονται ~120 MB σε κάθε εγκατάσταση, για πάντα.
///
/// Η διαγραφή είναι **ευκαιριακή**: ό,τι δεν καθαριστεί σήμερα (κλειδωμένο
/// αρχείο, έλλειψη δικαιωμάτων) ξαναδοκιμάζεται στο επόμενο άνοιγμα. Καμία
/// αποτυχία δεν διακόπτει την εκκίνηση.
class UpdateResidueCleaner {
  UpdateResidueCleaner({
    required this.installDirectory,
    bool Function()? isDevelopmentBuild,
    bool Function()? isWindows,
    Future<bool> Function()? hasPendingUpdate,
    DateTime Function()? clock,
    this.settleWindow = const Duration(minutes: 2),
  }) : isDevelopmentBuild = isDevelopmentBuild ?? (() => false),
       isWindows = isWindows ?? (() => Platform.isWindows),
       hasPendingUpdate = hasPendingUpdate ?? (() async => false),
       clock = clock ?? DateTime.now;

  /// Ο κατάλογος εγκατάστασης — ο μόνος μέσα στον οποίο επιτρέπεται διαγραφή.
  final String installDirectory;

  final bool Function() isDevelopmentBuild;
  final bool Function() isWindows;
  final Future<bool> Function() hasPendingUpdate;
  final DateTime Function() clock;

  /// Πόσο πρόσφατο ίχνος θεωρείται «ζωντανό» και δεν αγγίζεται.
  ///
  /// Ο updater ξεκινά τη νέα έκδοση **πριν** τερματίσει ο ίδιος, και το
  /// `cmd.exe` διαβάζει το `updater.cmd` γραμμή-γραμμή από τον δίσκο. Διαγραφή
  /// του staging τη στιγμή που η εφαρμογή μόλις άνοιξε θα έσπαγε το script
  /// κάτω από τα πόδια του. Ένα άνοιγμα καθυστέρησης δεν κοστίζει τίποτα.
  final Duration settleWindow;

  /// Τα **μόνα** ονόματα που αγγίζονται ποτέ. Σταθερές, όχι παράμετροι: κανένα
  /// μονοπάτι δεν μπορεί να οδηγήσει σε διαγραφή του `Data Base` ή του `data`.
  static const List<String> residueDirectoryNames = <String>[
    UpdateInstallerService.stagingDirName,
    UpdateInstallerService.backupDirName,
  ];

  /// Ο εργάτης της παραγωγής: πραγματικός κατάλογος εγκατάστασης και πραγματικός
  /// έλεγχος εκκρεμότητας.
  factory UpdateResidueCleaner.production() {
    return UpdateResidueCleaner(
      installDirectory: AppConfig.applicationExecutableDirectory,
      isDevelopmentBuild: () => BuildEnvironment.isDevelopmentBuild(),
      hasPendingUpdate: () =>
          buildDefaultUpdateInstallerService().hasPendingUpdate(),
    );
  }

  /// Εντοπίζει τι υπάρχει και τι επιτρέπεται να φύγει. Δεν διαγράφει τίποτα.
  Future<UpdateResidueScan> scan() async {
    if (!isWindows()) return const UpdateResidueScan();

    // Σε build ανάπτυξης το εκτελέσιμο ζει μέσα στο `build\windows\...` — δεν
    // υπάρχει εγκατάσταση να καθαριστεί και μια λάθος διαγραφή εκεί κοστίζει
    // ξαναχτίσιμο.
    if (isDevelopmentBuild()) return const UpdateResidueScan();

    if (!_isPlausibleInstallDirectory(installDirectory)) {
      return const UpdateResidueScan();
    }

    // Εκκρεμής ενημέρωση σημαίνει ότι το staging είναι **έτοιμο πακέτο σε
    // αναμονή**, όχι σκουπίδι: διαγραφή του θα ακύρωνε σιωπηλά μια ενημέρωση
    // που ο χρήστης έχει ήδη εγκρίνει.
    final pending = await _hasPendingUpdateSafely();

    final removable = <String>[];
    final protected = <String>[];

    for (final name in residueDirectoryNames) {
      final directory = Directory(p.join(installDirectory, name));
      if (!await directory.exists()) continue;

      final isStaging = name == UpdateInstallerService.stagingDirName;
      if (pending && isStaging) {
        protected.add(directory.path);
        continue;
      }

      if (await _wasTouchedRecently(directory)) {
        protected.add(directory.path);
        continue;
      }

      removable.add(directory.path);
    }

    return UpdateResidueScan(removable: removable, protected: protected);
  }

  /// Διαγράφει όσα σήμανε η [scan]. Επιστρέφει όσα όντως έφυγαν.
  ///
  /// Μια αποτυχία (κλειδωμένο αρχείο, δικαιώματα, φάκελος που εξαφανίστηκε στο
  /// μεταξύ) αφορά μόνο τον δικό της φάκελο και δεν σταματά τους υπόλοιπους.
  Future<List<String>> clean(UpdateResidueScan scan) async {
    final removed = <String>[];
    for (final path in scan.removable) {
      // Δεύτερος έλεγχος πριν από κάθε διαγραφή: η [scan] μπορεί να έτρεξε πριν
      // από ώρα, και η διαδρομή περνά ξανά από την ίδια πύλη ασφαλείας.
      if (!_isInsideInstallDirectory(path)) continue;
      try {
        final directory = Directory(path);
        if (!await directory.exists()) continue;
        await directory.delete(recursive: true);
        removed.add(path);
      } catch (_) {
        // Ευκαιριακό: ξαναδοκιμάζεται στο επόμενο άνοιγμα.
      }
    }
    return removed;
  }

  Future<bool> _hasPendingUpdateSafely() async {
    try {
      return await hasPendingUpdate();
    } catch (_) {
      // Άγνωστη κατάσταση εκκρεμότητας: κρατάμε το staging. Ένα άνοιγμα με
      // 120 MB παραπάνω είναι ασύγκριτα φθηνότερο από ακυρωμένη ενημέρωση.
      return true;
    }
  }

  /// Το πιο πρόσφατο ίχνος εγγραφής στον φάκελο ή στα άμεσα παιδιά του.
  ///
  /// Ο χρόνος του ίδιου του φακέλου δεν αρκεί: στα Windows δεν ανανεώνεται όταν
  /// γράφεται περιεχόμενο σε υπάρχον αρχείο — και το `updater.log` γράφεται
  /// ακριβώς έτσι, όσο ο updater τρέχει.
  Future<bool> _wasTouchedRecently(Directory directory) async {
    try {
      var latest = (await directory.stat()).modified;
      await for (final entity in directory.list(followLinks: false)) {
        try {
          final modified = (await entity.stat()).modified;
          if (modified.isAfter(latest)) latest = modified;
        } catch (_) {}
      }
      final age = clock().difference(latest);
      // Αρνητική ηλικία σημαίνει ώρα αρχείου στο μέλλον (ρολόι εκτός συγχρονισμού
      // ή αντιγραφή από άλλο μηχάνημα): αντιμετωπίζεται ως φρέσκο.
      return age < settleWindow;
    } catch (_) {
      // Δεν διαβάζεται ο φάκελος: δεν τον αγγίζουμε.
      return true;
    }
  }

  /// Απορρίπτει κενές διαδρομές και ρίζες δίσκου (`C:\`), όπου μια διαγραφή θα
  /// στόχευε σε φάκελο που δεν έφτιαξε ποτέ η εφαρμογή.
  bool _isPlausibleInstallDirectory(String directory) {
    final normalized = p.normalize(directory.trim());
    if (normalized.isEmpty || normalized == '.') return false;
    if (p.equals(normalized, p.rootPrefix(normalized))) return false;
    return true;
  }

  bool _isInsideInstallDirectory(String candidate) {
    if (!_isPlausibleInstallDirectory(installDirectory)) return false;
    final parent = p.dirname(p.normalize(candidate));
    if (!p.equals(parent, p.normalize(installDirectory))) return false;
    return residueDirectoryNames.contains(p.basename(p.normalize(candidate)));
  }
}
