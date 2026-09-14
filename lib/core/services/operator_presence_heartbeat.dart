import 'dart:async';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';
import '../database/database_helper.dart';
import '../database/operator_presence_repository.dart';
import '../models/operator_presence.dart';
import 'crash_log_service.dart';
import 'current_operator.dart';

/// Αφήνει το ίχνος «είμαι εδώ» για τον συνδεδεμένο χρήστη, από αυτόν τον σταθμό.
///
/// **Γιατί χρειάζεται χτύπος και δεν αρκεί μία εγγραφή στη σύνδεση:** το SQLite
/// δεν κρατά λίστα συνδέσεων. Η μόνη ειλικρινής απάντηση στο «ποιος το έχει
/// ανοιχτό τώρα;» είναι «ποιος άφησε πρόσφατο ίχνος», και αυτό απαιτεί να το
/// ξαναγράφει όσο είναι ανοιχτή η εφαρμογή.
///
/// **Δένεται στην ταυτότητα, όχι στις οθόνες.** Κάθε ροή που αλλάζει χρήστη —
/// εκκίνηση, οθόνη επιλογής, «Αλλαγή χρήστη», αλλαγή βάσης — περνά από το
/// [CurrentOperator]. Ακούγοντας εκεί, ο χτύπος ακολουθεί μόνος του, και καμία
/// μελλοντική ροή δεν μπορεί να ξεχάσει να τον ενημερώσει.
///
/// **Σιωπηλός στα τεστ:** ξεκινά μόνο με ρητό [start] και γράφει μόνο σε βάση
/// που είναι **ήδη ανοιχτή** — ποτέ δεν ανοίγει σύνδεση. Μέσα σε `testWidgets` το
/// άνοιγμα δεν ολοκληρώνεται ποτέ και η οθόνη θα κρεμούσε.
class OperatorPresenceHeartbeat {
  OperatorPresenceHeartbeat._();

  static final OperatorPresenceHeartbeat instance =
      OperatorPresenceHeartbeat._();

  Timer? _timer;
  bool _listening = false;

  /// Ο χτύπος που τρέχει αυτή τη στιγμή, αν τρέχει.
  ///
  /// Υπάρχει ώστε ο έλεγχος να περιμένει το **πραγματικό** γράψιμο αντί για
  /// αυθαίρετη καθυστέρηση — μια αναμονή «μισού δευτερολέπτου» είναι τεστ που
  /// θα τρεμοπαίξει κάποια στιγμή σε φορτωμένο μηχάνημα.
  Future<void>? pendingBeat;

  /// Το όνομα του υπολογιστή. Αντικαθίσταται στα τεστ.
  static String Function() stationNameReader = () {
    final fromEnvironment = Platform.environment['COMPUTERNAME']?.trim();
    if (fromEnvironment != null && fromEnvironment.isNotEmpty) {
      return fromEnvironment;
    }
    return Platform.localHostname;
  };

  /// Ο σταθμός αυτού του αντιγράφου· κενό όταν το σύστημα δεν τον δίνει.
  static String get stationName {
    try {
      return stationNameReader().trim();
    } catch (_) {
      // Ο σταθμός είναι πληροφορία άνεσης — η απουσία του δεν σταματά τίποτα.
      return '';
    }
  }

  /// Ποιο **ανοιχτό αντίγραφο** είναι αυτό. Αντικαθίσταται στα τεστ.
  ///
  /// Διαδρομή εκτελέσιμου συν όνομα προφίλ: δύο εφαρμογές στον ίδιο υπολογιστή
  /// (η κανονική και η δοκιμαστική) ξεχωρίζουν, ενώ η ίδια εφαρμογή κρατά την
  /// ίδια ταυτότητα από εκκίνηση σε εκκίνηση — αλλιώς κάθε άνοιγμα θα άφηνε νέα
  /// γραμμή και ο πίνακας θα γινόταν ημερολόγιο.
  static String Function() instanceIdReader = () {
    final exe = Platform.resolvedExecutable.trim();
    final profile = AppConfig.activeProfile?.trim() ?? '';
    return profile.isEmpty ? exe : '$exe|$profile';
  };

  /// Η ταυτότητα αυτού του αντιγράφου· κενή όταν δεν μπορεί να βρεθεί.
  static String get instanceId {
    try {
      return instanceIdReader().trim();
    } catch (_) {
      return '';
    }
  }

  /// Ποια έκδοση της εφαρμογής τρέχει. Αντικαθίσταται στα τεστ.
  static Future<String> Function() appVersionReader = () async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  };

  /// Η έκδοση, διαβασμένη **μία φορά** και κρατημένη.
  ///
  /// Δεν αλλάζει όσο τρέχει η εφαρμογή, και ο χτύπος δεν επιτρέπεται να
  /// πληρώνει μια κλήση στο σύστημα κάθε λεπτό για να ξαναμάθει το ίδιο.
  /// Κενή όταν το σύστημα δεν τη δίνει — η έκδοση είναι πληροφορία άνεσης.
  static String? _cachedAppVersion;

  static Future<String> _appVersion() async {
    final cached = _cachedAppVersion;
    if (cached != null) return cached;
    try {
      final value = (await appVersionReader()).trim();
      _cachedAppVersion = value;
      return value;
    } catch (_) {
      _cachedAppVersion = '';
      return '';
    }
  }

  /// Ξεχνά την έκδοση που κρατήθηκε. Υπάρχει για τα τεστ.
  static void resetAppVersionCache() => _cachedAppVersion = null;

  /// Αρχίζει να παρακολουθεί την ταυτότητα και να χτυπά.
  ///
  /// Ασφαλές να κληθεί πολλές φορές — η δεύτερη κλήση δεν κάνει τίποτα.
  void start() {
    if (_listening) return;
    _listening = true;
    CurrentOperator.listenable.addListener(_onOperatorChanged);
    _onOperatorChanged();
  }

  /// Σταματά τα πάντα. Καλείται από τα τεστ και από το [releaseAndStop].
  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_listening) {
      CurrentOperator.listenable.removeListener(_onOperatorChanged);
      _listening = false;
    }
  }

  void _onOperatorChanged() {
    _timer?.cancel();
    _timer = null;
    if (CurrentOperator.active?.id == null) return;

    // Αμέσως, ώστε η αλλαγή χρήστη να φαίνεται στους άλλους χωρίς αναμονή.
    pendingBeat = beatOnce();
    unawaited(pendingBeat);
    _timer = Timer.periodic(OperatorPresence.heartbeatInterval, (_) {
      pendingBeat = beatOnce();
      unawaited(pendingBeat);
    });
  }

  /// Ένας χτύπος. Δημόσιο για τα τεστ και για τη στιγμή της σύνδεσης.
  ///
  /// **Ποτέ μοιραίο.** Η βάση ζει σε δικτυακό φάκελο που μπορεί να πέσει· ένα
  /// ίχνος που δεν γράφτηκε δεν επιτρέπεται να χαλάσει τη δουλειά κανενός. Το
  /// σφάλμα αφήνει ίχνος στο ημερολόγιο και η επόμενη προσπάθεια ξαναδοκιμάζει.
  Future<void> beatOnce() async {
    final operatorId = CurrentOperator.active?.id;
    if (operatorId == null) return;
    final station = stationName;
    if (station.isEmpty) return;

    final db = DatabaseHelper.instance.openDatabaseOrNull;
    if (db == null) return;

    try {
      await OperatorPresenceRepository(db).touch(
        operatorId: operatorId,
        station: station,
        instance: instanceId,
        appVersion: await _appVersion(),
        at: DateTime.now(),
      );
    } catch (e, stack) {
      CrashLogService.instanceOrNull?.logError(e, stack, fatal: false);
    }
  }

  /// Παραδίδει το ίχνος αυτού του αντιγράφου και σταματά τον χτύπο.
  ///
  /// **Μόνο στο κανονικό κλείσιμο.** Χωρίς αυτό, όποιος κλείνει σωστά την
  /// εφαρμογή εξακολουθεί να μετράει ως ανοιχτή συνεδρία για όσο κρατά το
  /// παράθυρο φρεσκάδας — και ο συνάδελφος που ετοιμάζεται για συντήρηση
  /// βλέπει φάντασμα ακριβώς τη στιγμή που περιμένει να αδειάσει το πεδίο.
  ///
  /// **Ποτέ μοιραίο**, για τον ίδιο λόγο με τον χτύπο: το κλείσιμο δεν
  /// σταματά επειδή το δίκτυο δεν απάντησε.
  Future<void> releaseAndStop() async {
    stop();
    final holder = instanceId;
    if (holder.isEmpty) return;
    final db = DatabaseHelper.instance.openDatabaseOrNull;
    if (db == null) return;
    try {
      await OperatorPresenceRepository(db).release(instance: holder);
    } catch (e, stack) {
      CrashLogService.instanceOrNull?.logError(e, stack, fatal: false);
    }
  }
}
