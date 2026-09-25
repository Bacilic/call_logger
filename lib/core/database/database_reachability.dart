/// Φύλακας προσβασιμότητας της ανοιχτής βάσης.
///
/// **Το πρόβλημα που λύνει:** η βάση ζει σε δικτυακό φάκελο και η σύνδεση
/// κόβεται ενώ η εφαρμογή τρέχει. Τα ερωτήματα δεν επιστρέφουν ποτέ, οι
/// οθόνες γυρίζουν τον κύκλο φόρτωσης, και ο χειριστής δεν μαθαίνει ποτέ ότι
/// φταίει το δίκτυο και όχι η εφαρμογή.
///
/// **Τι κάνει και τι ΔΕΝ κάνει:** ο φύλακας **ειδοποιεί**. Δεν σταματά την
/// αναμονή των ερωτημάτων που ήδη τρέχουν — αυτό είναι δουλειά του ορίου
/// χρόνου, που μπαίνει χωριστά.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqflite.dart';

import 'database_helper.dart';
import 'database_stall.dart';

/// Η κατάσταση όπως τη βλέπει ο χειριστής.
enum DatabaseReachability {
  /// Το αρχείο απαντά.
  ok,

  /// Το αρχείο απαντά, αλλά η βάση μένει **κλειδωμένη** — π.χ. μεγάλη
  /// εγγραφή ή αντίγραφο ασφαλείας από άλλον σταθμό. Οι φορτώσεις και οι
  /// αποθηκεύσεις περιμένουν· μετά από αρκετή αναμονή μπορεί να αποτύχουν.
  busy,

  /// Το αρχείο έπαψε να απαντά.
  lost,

  /// Το αρχείο απαντά, αλλά η **σύνδεση που κρατά η εφαρμογή** έχει πεθάνει.
  ///
  /// Ξεχωριστή κατάσταση επειδή αλλάζει τι μπορεί να κάνει ο άνθρωπος: το
  /// χαμένο δίκτυο επανέρχεται μόνο του και η αναμονή έχει νόημα· η νεκρή
  /// σύνδεση **δεν ζωντανεύει ποτέ** — μετρημένο στο πεδίο, πάνω από είκοσι
  /// λεπτά. Η μόνη διέξοδος είναι νέο άνοιγμα της εφαρμογής, και η λωρίδα
  /// οφείλει να το λέει αντί να υπόσχεται επιστροφή που δεν θα έρθει.
  staleConnection,
}

/// Τι βρήκε **ένας** έλεγχος του φύλακα.
enum DatabaseProbeSample {
  /// Το αρχείο απαντά και η βάση δεν είναι κλειδωμένη.
  ok,

  /// Το αρχείο απαντά, αλλά η βάση είναι κλειδωμένη αυτή τη στιγμή.
  locked,

  /// Το αρχείο δεν απαντά.
  unreachable,

  /// Η σύνδεση που κρατά η εφαρμογή δεν αποκρίνεται πια.
  staleConnection,
}

/// Η κατάσταση του φύλακα, διαθέσιμη **έξω** από το Riverpod.
///
/// Υπάρχει για έναν και μόνο καταναλωτή: τον κανόνα επανάληψης του
/// `ProviderScope`. Η υπογραφή που ορίζει το Riverpod του δίνει μόνο τον
/// αριθμό προσπάθειας και το σφάλμα — δεν έχει `ref`, άρα δεν μπορεί να
/// ρωτήσει τον φύλακα με τον κανονικό τρόπο.
///
/// **Ένας γράφει, ένας διαβάζει.** Το γράψιμο ανήκει αποκλειστικά στον
/// [DatabaseReachabilityNotifier], που είναι ο κάτοχος της κατάστασης· εδώ
/// απλώς δημοσιεύεται. Καμία άλλη ροή δεν έχει λόγο να το πειράξει.
class DatabaseReachabilitySignal {
  DatabaseReachabilitySignal._();

  static DatabaseReachability _state = DatabaseReachability.ok;

  static DatabaseReachability get state => _state;

  /// True όταν ο φύλακας έχει ήδη κρίνει ότι η βάση δεν απαντά.
  ///
  /// Περιλαμβάνει και τη νεκρή σύνδεση: εκεί καμία επανάληψη δεν πρόκειται
  /// να πετύχει, και η μόνη τους συνεισφορά θα ήταν να κρύβουν το σφάλμα.
  static bool get isLost =>
      _state == DatabaseReachability.lost ||
      _state == DatabaseReachability.staleConnection;

  /// Το γράφει ΜΟΝΟ ο φύλακας.
  static void publish(DatabaseReachability value) => _state = value;

  /// Μηδενισμός για τα τεστ — η κατάσταση είναι καθολική και δεν επιτρέπεται
  /// να ταξιδεύει από τον έναν έλεγχο στον επόμενο.
  static void resetForTest() => _state = DatabaseReachability.ok;
}

/// Ο κανόνας επανάληψης ολόκληρης της εφαρμογής.
///
/// **Το πρόβλημα:** όταν η βάση χάνεται, κάθε ερώτημα αποτυγχάνει αμέσως — και
/// το Riverpod το ξαναδοκιμάζει δέκα φορές μέσα σε ~38 δευτερόλεπτα. Όσο
/// κρατούν οι προσπάθειες, η οθόνη δείχνει κύκλο φόρτωσης: ο χειριστής βλέπει
/// «φορτώνει» κάτω από μια κόκκινη λωρίδα που λέει «δεν αποκρίνεται».
///
/// **Η λύση δεν είναι να κοπεί η επανάληψη.** Σε κοινόχρηστη βάση το παροδικό
/// κλείδωμα λύνεται μόνο του και η επανάληψη το γεφυρώνει σιωπηλά — αυτό
/// μένει. Ό,τι κόβεται είναι η **άσκοπη** επανάληψη: όταν ο φύλακας έχει ήδη
/// διαπιστώσει ότι η διαδρομή δεν απαντά, καμία επόμενη προσπάθεια δεν
/// πρόκειται να πετύχει, και η μόνη τους συνεισφορά είναι να κρύβουν το
/// σφάλμα από τον χειριστή.
/// Είναι αυτή η αλλαγή **επιστροφή** της βάσης;
///
/// Μόνο η μετάβαση «χαμένη ή απασχολημένη → εντάξει» μετράει. Κάθε
/// επιτυχημένος έλεγχος του φύλακα περνά από τον ίδιο δρόμο — αν μετρούσαν
/// όλοι, η εφαρμογή θα ξαναφόρτωνε τις κοινές όψεις κάθε είκοσι
/// δευτερόλεπτα, σε βάση που μοιράζονται δεκάδες σταθμοί. Η απασχολημένη
/// βάση μετρά κι αυτή: όσο ήταν κλειδωμένη, ερωτήματα μπορεί να έληξαν, και
/// οι οθόνες τους θα έμεναν με το σφάλμα αν δεν ξαναρωτούσαν.
bool isDatabaseReturn(
  DatabaseReachability? previous,
  DatabaseReachability next,
) =>
    previous != null &&
    previous != DatabaseReachability.ok &&
    next == DatabaseReachability.ok;

Duration? databaseAwareRetry(int retryCount, Object error) {
  if (DatabaseReachabilitySignal.isLost) return null;
  return ProviderContainer.defaultRetry(retryCount, error);
}

/// Κρατά την ιστορία των ελέγχων και αποφασίζει **πότε** λέμε «χάθηκε» ή
/// «απασχολημένη».
///
/// **Δύο συνεχόμενες μετρήσεις, όχι μία.** Μια στιγμιαία αναλαμπή του δικτύου
/// δεν πρέπει να πετά κόκκινη λωρίδα στα μούτρα του χειριστή τη στιγμή που
/// γράφει μια κλήση — και κάθε κανονική εγγραφή κλειδώνει τη βάση για
/// κλάσματα δευτερολέπτου. Η επιστροφή όμως είναι **άμεση**: μία επιτυχία
/// αρκεί — όταν το εμπόδιο φύγει, δεν έχει νόημα να κρατάμε τη λωρίδα.
///
/// Οι δύο αιτίες μετρούν **χωριστά**: μία κλειδωμένη και μία άφταστη μέτρηση
/// δεν αθροίζονται σε συναγερμό.
class DatabaseReachabilityTracker {
  DatabaseReachabilityTracker({this.failuresBeforeAlarm = 2});

  /// Πόσες συνεχόμενες ίδιες μετρήσεις χρειάζονται πριν ανάψει λωρίδα.
  final int failuresBeforeAlarm;

  int _consecutiveFailures = 0;
  int _consecutiveLocked = 0;
  int _consecutiveStale = 0;

  /// Ως πότε **δεν** πιστεύουμε μια επιτυχημένη ανάγνωση.
  ///
  /// Μπαίνει μόνο όταν μια πραγματική πράξη μπλοκαρίστηκε — δες
  /// [recordRealStall].
  DateTime? _stallFloorUntil;

  /// Πόσο κρατά η λωρίδα μετά από πραγματική αποτυχία, ό,τι κι αν λέει η
  /// ανάγνωση του φύλακα.
  ///
  /// **Γιατί χρειάζεται πάτωμα:** η ανάγνωση περνά μέσα από το κλείδωμα, οπότε
  /// ο επόμενος έλεγχος (σε πέντε δευτερόλεπτα) θα έσβηνε τη λωρίδα ενώ το
  /// εμπόδιο κρατά ακόμη — και η υπόσχεσή της, «ξαναδοκίμασε μόλις φύγει αυτή
  /// η λωρίδα», θα γινόταν ψέμα. Είκοσι δευτερόλεπτα καλύπτουν με άνεση το
  /// μετρημένο αντίγραφο ασφαλείας συναδέλφου (12'').
  static const Duration realStallFloor = Duration(seconds: 20);

  /// Η σειρά είναι προτεραιότητα: το χαμένο αρχείο είναι η βαρύτερη είδηση,
  /// μετά η νεκρή σύνδεση, και τελευταία η απασχόληση που λύνεται μόνη της.
  DatabaseReachability get state {
    if (_consecutiveFailures >= failuresBeforeAlarm) {
      return DatabaseReachability.lost;
    }
    if (_consecutiveStale >= failuresBeforeAlarm) {
      return DatabaseReachability.staleConnection;
    }
    if (_consecutiveLocked >= failuresBeforeAlarm) {
      return DatabaseReachability.busy;
    }
    return DatabaseReachability.ok;
  }

  /// Καταγράφει το αποτέλεσμα ενός ελέγχου αρχείου (χωρίς έλεγχο κλειδώματος).
  DatabaseReachability record({required bool probeSucceeded}) => recordSample(
    probeSucceeded ? DatabaseProbeSample.ok : DatabaseProbeSample.unreachable,
  );

  /// Μια **πραγματική** πράξη της εφαρμογής μπλοκαρίστηκε.
  ///
  /// **Μία φτάνει.** Τα δείγματα του φύλακα θέλουν δύο επιβεβαιώσεις επειδή
  /// είναι εικασίες από απόσταση· αυτό δεν είναι εικασία, είναι ζημιά που ήδη
  /// έγινε — κάποιος περίμενε ως το όριο και έχασε την αποθήκευσή του.
  ///
  /// **Κίτρινη, ποτέ πορτοκαλί.** Το ίδιο όριο χτυπά και σε κλείδωμα
  /// συναδέλφου και σε νεκρή σύνδεση. Η δεύτερη έχει ήδη τον δικό της,
  /// αξιόπιστο κριτή (την επιμονή της σιωπής) και θα υπερισχύσει μόνη της·
  /// μια εικασία από εδώ θα ζητούσε επανεκκίνηση σε κάθε αργό αντίγραφο.
  DatabaseReachability recordRealStall(DateTime now) {
    // Η βαρύτερη είδηση δεν υποβαθμίζεται: όταν η σύνδεση έχει ήδη κριθεί
    // νεκρή (ή ο φάκελος χαμένος) κάθε πράξη αποτυγχάνει και κάθε μία θα
    // ανέφερε — η λωρίδα με τη σωστή διέξοδο πρέπει να μείνει.
    if (_consecutiveFailures >= failuresBeforeAlarm ||
        _consecutiveStale >= failuresBeforeAlarm) {
      return state;
    }
    _consecutiveFailures = 0;
    _consecutiveStale = 0;
    _consecutiveLocked = failuresBeforeAlarm;
    _stallFloorUntil = now.add(realStallFloor);
    return state;
  }

  /// Καταγράφει το αποτέλεσμα ενός ελέγχου και επιστρέφει τη νέα κατάσταση.
  ///
  /// Το [now] υπάρχει για το πάτωμα του [recordRealStall] — και μόνο γι' αυτό.
  DatabaseReachability recordSample(
    DatabaseProbeSample sample, {
    DateTime? now,
  }) {
    switch (sample) {
      case DatabaseProbeSample.ok:
        final floor = _stallFloorUntil;
        if (floor != null && (now ?? DateTime.now()).isBefore(floor)) {
          // Η ανάγνωση περνά μέσα από το κλείδωμα· δεν αποδεικνύει τίποτα.
          return state;
        }
        _stallFloorUntil = null;
        _consecutiveFailures = 0;
        _consecutiveLocked = 0;
        _consecutiveStale = 0;
      case DatabaseProbeSample.locked:
        _consecutiveFailures = 0;
        _consecutiveStale = 0;
        if (_consecutiveLocked < failuresBeforeAlarm) _consecutiveLocked++;
      case DatabaseProbeSample.unreachable:
        _stallFloorUntil = null;
        _consecutiveLocked = 0;
        _consecutiveStale = 0;
        if (_consecutiveFailures < failuresBeforeAlarm) _consecutiveFailures++;
      case DatabaseProbeSample.staleConnection:
        _stallFloorUntil = null;
        _consecutiveFailures = 0;
        _consecutiveLocked = 0;
        if (_consecutiveStale < failuresBeforeAlarm) _consecutiveStale++;
    }
    return state;
  }
}

/// Ρωτά το αρχείο της βάσης αν είναι ακόμη εκεί — **χωρίς να κρεμάσει**.
///
/// Δύο προφυλάξεις, και οι δύο απαραίτητες:
///  * **Όριο χρόνου:** μια δικτυακή διαδρομή που δεν αποκρίνεται μπορεί να
///    αργήσει δεκάδες δευτερόλεπτα λόγω SMB. Ο φύλακας δεν επιτρέπεται να
///    κολλήσει εκεί που κόλλησε η εφαρμογή.
///  * **try/catch:** σε άφταστη διαδρομή δικτύου τα Windows **πετούν**
///    εξαίρεση αντί να απαντήσουν «δεν υπάρχει».
///
/// Ρωτά για το **μέγεθος** και όχι για την ύπαρξη: το μέγεθος απαιτεί
/// πραγματικό άνοιγμα, ενώ η ύπαρξη μπορεί να απαντηθεί από μνήμη του
/// συστήματος και να πει «όλα καλά» για αρχείο που δεν διαβάζεται πια.
Future<bool> probeDatabaseFile(
  String path, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (path.trim().isEmpty) return true;
  try {
    await File(path).length().timeout(timeout);
    return true;
  } catch (_) {
    return false;
  }
}

/// Είναι η βάση κλειδωμένη **αυτή τη στιγμή**; Ρωτά χωρίς να περιμένει.
///
/// Ο έλεγχος του αρχείου ([probeDatabaseFile]) απαντά «υπάρχει και
/// διαβάζεται» — και σε κλειδωμένη βάση λέει «όλα καλά». Έτσι, όσο κάποιος
/// άλλος σταθμός κρατούσε τη βάση (μετρημένο 23/09/2026: 12 δευτερόλεπτα για
/// ένα αντίγραφο ασφαλείας), οι οθόνες έδειχναν «Χρήστης #2» και καμία λωρίδα
/// δεν εξηγούσε γιατί.
///
/// Ανοίγει δική του σύνδεση **χωρίς αναμονή κλειδώματος**: μια ανάγνωση που
/// βρίσκει τη βάση πιασμένη απαντά αμέσως «κλειδωμένη» αντί να περιμένει. Ό,τι
/// άλλο στραβό βρει (αρχείο που δεν είναι βάση, δικαιώματα) **δεν** το λέει
/// απασχόληση — έχει δικό του φρουρό, και εδώ θα ήταν ψέμα.
Future<DatabaseProbeSample> probeDatabaseLock(
  String path, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  if (path.trim().isEmpty) return DatabaseProbeSample.ok;
  Database? db;
  try {
    return await () async {
      final opened = await openDatabase(
        path,
        readOnly: true,
        singleInstance: false,
      );
      db = opened;
      await opened.rawQuery('SELECT count(*) FROM sqlite_master');
      return DatabaseProbeSample.ok;
    }().timeout(timeout);
  } on TimeoutException {
    // Ούτε μια ανάγνωση του καταλόγου δεν πρόλαβε: για τον χειριστή, η βάση
    // δεν απαντά αυτή τη στιγμή. (Το άφταστο αρχείο το έχει ήδη πιάσει ο
    // έλεγχος αρχείου, που τρέχει πρώτος.)
    return DatabaseProbeSample.locked;
  } catch (e) {
    return isDatabaseLockedError(e)
        ? DatabaseProbeSample.locked
        : DatabaseProbeSample.ok;
  } finally {
    try {
      await db?.close();
    } catch (_) {}
  }
}

/// Πώς κρίνεται ένα σφάλμα που ήρθε από τη **ζωντανή** σύνδεση.
///
/// **Γιατί χρειάζεται δική του κρίση:** το ερώτημα είναι ένα `PRAGMA` που δεν
/// διαβάζει δεδομένα και δεν έχει σύνταξη να αποτύχει. Ό,τι επιστρέψει σφάλμα
/// αφορά την ίδια τη σύνδεση, όχι το ερώτημα — γι' αυτό η άγνωστη αιτία
/// κρίνεται **άφταστη** και όχι «εντάξει». Ο φύλακας θέλει ούτως ή άλλως δύο
/// συνεχόμενες μετρήσεις για να ανάψει λωρίδα, οπότε ένα μεμονωμένο περίεργο
/// σφάλμα δεν πετά κόκκινο στα μούτρα του χειριστή.
///
/// Η μόνη εξαίρεση είναι το **κλείδωμα**: λύνεται μόνο του, και έχει δική του
/// λωρίδα. Αν μπερδευόταν με τη νεκρή σύνδεση, κάθε αντίγραφο ασφαλείας
/// συναδέλφου θα έδειχνε «χάθηκε η βάση».
DatabaseProbeSample classifyLiveConnectionError(Object error) =>
    isDatabaseLockedError(error)
    ? DatabaseProbeSample.locked
    : DatabaseProbeSample.staleConnection;

/// Ρωτά τη **σύνδεση που χρησιμοποιεί η εφαρμογή** αν ζει ακόμη.
///
/// **Το κενό που κλείνει:** οι άλλοι δύο έλεγχοι του φύλακα ρωτούν το αρχείο
/// και ανοίγουν καινούργια σύνδεση. Και τα δύο πετυχαίνουν όταν η πραγματική
/// σύνδεση έχει πεθάνει — μετρημένο στο πεδίο 23/09/2026: επί είκοσι λεπτά
/// κάθε εγγραφή απέτυχε με «disk I/O error (code 1802)», ενώ το αρχείο
/// απαντούσε και μια νέα σύνδεση δούλευε αμέσως.
///
/// Επιστρέφει `null` όταν **δεν υπάρχει** ανοιχτή σύνδεση: τότε δεν υπάρχει
/// τίποτα να κριθεί, και οι υπόλοιποι έλεγχοι αναλαμβάνουν.
///
/// Το ερώτημα είναι το φθηνότερο που υπάρχει — ένα `PRAGMA` που δεν διαβάζει
/// δεδομένα — και τρέχει πάνω σε ήδη ανοιχτή σύνδεση.
Future<DatabaseProbeSample?> probeLiveConnection(
  DatabaseExecutor? db, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  if (db == null) return null;
  try {
    return await () async {
      await db.rawQuery('PRAGMA data_version');
      return DatabaseProbeSample.ok;
    }().timeout(timeout);
  } on TimeoutException {
    // «Η βάση δεν απάντησε σε 18 δευτερόλεπτα»: για τον χειριστή, η σύνδεση
    // δεν αποκρίνεται. Το κλείδωμα απαντά με σφάλμα, δεν σιωπά.
    return DatabaseProbeSample.staleConnection;
  } catch (e) {
    return classifyLiveConnectionError(e);
  }
}

/// Η κατάσταση που βλέπει το κέλυφος. Δεν είναι autoDispose: ο φύλακας πρέπει
/// να επιζεί κάθε αλλαγής οθόνης.
final databaseReachabilityProvider =
    NotifierProvider<DatabaseReachabilityNotifier, DatabaseReachability>(
      DatabaseReachabilityNotifier.new,
    );

class DatabaseReachabilityNotifier extends Notifier<DatabaseReachability> {
  Timer? _timer;
  final DatabaseReachabilityTracker _tracker = DatabaseReachabilityTracker();
  String? _watchedPath;
  bool _lastProbeFailed = false;

  /// Ο ρυθμός στην ήρεμη ώρα: αραιά, ώστε να μην κοστίζει σε κοινόχρηστο
  /// δικτυακό φάκελο που τον μοιράζονται δεκάδες σταθμοί.
  static const Duration calmInterval = Duration(seconds: 20);

  /// Ο ρυθμός μόλις κάτι πάει στραβά — και όσο διαρκεί η απώλεια.
  ///
  /// **Δύο λόγοι, και οι δύο για τον χειριστή:** η ειδοποίηση φτάνει σε
  /// δευτερόλεπτα αντί για λεπτό, και η **επιστροφή** πιάνεται αμέσως μόλις
  /// γυρίσει το δίκτυο. Το πυκνό ρώτημα κοστίζει μόνο όταν κάτι ήδη φταίει.
  static const Duration alertInterval = Duration(seconds: 5);

  Duration get _nextDelay =>
      _lastProbeFailed || state != DatabaseReachability.ok
      ? alertInterval
      : calmInterval;

  @override
  DatabaseReachability build() {
    ref.onDispose(() {
      _timer?.cancel();
      _watchedPath = null;
      DatabaseStallReports.listen(null);
    });
    return DatabaseReachability.ok;
  }

  /// Η ώρα, από ένα σημείο — ώστε τα τεστ να ορίζουν το πάτωμα της λωρίδας.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  /// Μια πραγματική πράξη της εφαρμογής μόλις μπλοκαρίστηκε.
  ///
  /// **Γιατί ακούμε αντί να ρωτάμε:** το ερώτημα του φύλακα είναι ανάγνωση, και
  /// ένα αποκλειστικό κλείδωμα τις αφήνει να περνούν — μετρημένο στο πεδίο
  /// 24/09, όπου ο διπλανός σταθμός έχασε εγγραφή ενώ ο φύλακας έλεγε «όλα
  /// καλά». Η πράξη που κόλλησε είναι ο μόνος μάρτυρας που ρώτησε με τον
  /// σωστό τρόπο.
  void _onRealStall() {
    if (_watchedPath == null) return;
    final next = _tracker.recordRealStall(now());
    _lastProbeFailed = true;
    if (next != state) _publish(next);
    // Ο ρυθμός πυκνώνει αμέσως: η επιστροφή πρέπει να πιαστεί γρήγορα, και ο
    // επόμενος έλεγχος αποφασίζει αν πρόκειται για κάτι βαρύτερο.
    _scheduleNext();
  }

  /// Ξεκινά τον περιοδικό έλεγχο για τη συγκεκριμένη διαδρομή.
  ///
  /// Καλείται ξανά σε κάθε αλλαγή βάσης· ο προηγούμενος φύλακας σταματά, ώστε
  /// να μη μείνουν δύο να ρωτούν διαφορετικά αρχεία.
  void watch(String? databasePath) {
    _timer?.cancel();
    DatabaseStallReports.listen(_onRealStall);
    _liveSilentStreak = 0;
    _tracker.record(probeSucceeded: true);
    _publish(DatabaseReachability.ok);

    final path = databasePath?.trim() ?? '';
    _watchedPath = path.isEmpty ? null : path;
    _lastProbeFailed = false;
    if (_watchedPath == null) return;

    _scheduleNext();
  }

  /// Ο επόμενος έλεγχος προγραμματίζεται **μετά** τον προηγούμενο, ποτέ
  /// παράλληλα: σε διαδρομή που δεν αποκρίνεται ο έλεγχος κρατά ως το όριό
  /// του, και ένα περιοδικό χρονόμετρο θα στοίβαζε ελέγχους τον έναν πάνω
  /// στον άλλο.
  void _scheduleNext() {
    _timer?.cancel();
    _timer = Timer(_nextDelay, () async {
      await _runCheck();
      if (_watchedPath != null) _scheduleNext();
    });
  }

  /// Από πού έρχεται η σύνδεση που χρησιμοποιεί η εφαρμογή.
  ///
  /// Αντικαθίσταται στα τεστ: η πραγματική ζητά ανοιχτή βάση, και μέσα σε
  /// `testWidgets` ένα άνοιγμα δεν ολοκληρώνεται ποτέ.
  @visibleForTesting
  DatabaseExecutor? Function() liveConnection = () =>
      DatabaseHelper.instance.openDatabaseOrNull;

  /// Πόσες συνεχόμενες φορές σώπασε η **δική μας** σύνδεση.
  ///
  /// Μετριέται χωριστά από την τελική κατάσταση, και είναι ο μόνος τρόπος να
  /// ξεχωρίσει το προσωρινό από το μόνιμο (δες [_runCheck]).
  int _liveSilentStreak = 0;

  /// Πόση επίμονη σιωπή της δικής μας σύνδεσης σημαίνει «πέθανε».
  ///
  /// Τρία δείγματα, και μετά την πρώτη αποτυχία ο ρυθμός είναι πέντε
  /// δευτερόλεπτα: ο άνθρωπος μαθαίνει την αλήθεια μέσα σε ~15 δευτερόλεπτα,
  /// ενώ ένα κλείδωμα συναδέλφου (μετρημένο: 12 δευτερόλεπτα για αντίγραφο)
  /// προλαβαίνει να λυθεί και να μη χαρακτηριστεί ποτέ νεκρό.
  static const int silentBeatsBeforeStale = 3;

  /// **Ο κριτής είναι η ΕΠΙΜΟΝΗ, όχι το κλείδωμα** — μάθημα της δοκιμής
  /// πεδίου 24/09, δεύτερος γύρος.
  ///
  /// Η προφανής ιδέα ήταν να ρωτηθεί μια καινούργια σύνδεση: αν εκείνη ανοίγει
  /// ενώ η δική μας σωπαίνει, φταίει η δική μας. **Δεν δουλεύει:** η νεκρή
  /// λαβή εξακολουθεί να κρατά κλειδώματα στο αρχείο, οπότε η καινούργια
  /// σύνδεση βρίσκει τη βάση «κλειδωμένη» — από εμάς τους ίδιους — και η
  /// εφαρμογή έδειχνε «απασχολημένη» επ' άπειρον μετά την επαναφορά του
  /// δικτύου.
  ///
  /// Ο χρόνος τα ξεχωρίζει καθαρά: το κλείδωμα του συναδέλφου λύνεται σε
  /// δευτερόλεπτα, η νεκρή σύνδεση **ποτέ**. Γι' αυτό μετράει η σιωπή της
  /// δικής μας σύνδεσης, και μόνο όταν επιμείνει κερδίζει κάθε άλλη εξήγηση.
  ///
  /// Η σειρά:
  /// 1. **Απαντά το αρχείο;** Όχι ⇒ χάθηκε ο φάκελος.
  /// 2. **Έχει ήδη κριθεί νεκρή;** Τότε δεν την ξαναρωτάμε — κάθε ερώτημα
  ///    στοιβάζεται πίσω από τη λειτουργία που κρέμεται.
  /// 3. **Ζει η δική μας σύνδεση;** Ναι ⇒ όλα καλά. Όχι ⇒ μετρά η σιωπή.
  /// 4. **Επέμεινε η σιωπή;** Ναι ⇒ νεκρή σύνδεση, ό,τι κι αν λέει το
  ///    κλείδωμα. Όχι ⇒ ρωτάμε το κλείδωμα, που ίσως εξηγεί την καθυστέρηση.
  Future<void> _runCheck() async {
    final path = _watchedPath;
    if (path == null) return;
    if (!await probeDatabaseFile(path)) {
      _liveSilentStreak = 0;
      recordSample(DatabaseProbeSample.unreachable);
      return;
    }

    if (state == DatabaseReachability.staleConnection) {
      recordSample(DatabaseProbeSample.staleConnection);
      return;
    }

    final live = await probeLiveConnection(liveConnection());
    if (live == DatabaseProbeSample.ok) {
      _liveSilentStreak = 0;
      recordSample(DatabaseProbeSample.ok);
      return;
    }
    if (live == null) {
      // Δεν υπάρχει ανοιχτή σύνδεση να κριθεί — δεν είναι σιωπή, είναι απουσία.
      _liveSilentStreak = 0;
      recordSample(await probeDatabaseLock(path));
      return;
    }

    _liveSilentStreak++;
    if (_liveSilentStreak >= silentBeatsBeforeStale) {
      recordSample(DatabaseProbeSample.staleConnection);
      return;
    }

    // Όσο η σιωπή είναι νεαρή, το κλείδωμα είναι η πιο πιθανή εξήγηση και
    // έχει τη δική του, ηπιότερη λωρίδα.
    final lock = await probeDatabaseLock(path);
    recordSample(lock != DatabaseProbeSample.ok ? lock : live);
  }

  /// Καταγράφει το αποτέλεσμα ενός ελέγχου.
  ///
  /// Δημόσιο ώστε τα τεστ να περνούν από **την ίδια** διαδρομή με τον
  /// πραγματικό φύλακα: ένα τεστ που αναπαράγει τα βήματα μόνο του θα φύλαγε
  /// το αντίγραφό του και όχι τον κώδικα.
  @visibleForTesting
  void recordProbeResult({required bool succeeded}) => recordSample(
    succeeded ? DatabaseProbeSample.ok : DatabaseProbeSample.unreachable,
  );

  /// Όπως [recordProbeResult], με όλες τις εκβάσεις ενός ελέγχου.
  @visibleForTesting
  void recordSample(DatabaseProbeSample sample) {
    _lastProbeFailed = sample != DatabaseProbeSample.ok;
    final next = _tracker.recordSample(sample, now: now());
    if (next != state) _publish(next);
  }

  /// Μία πόρτα για κάθε αλλαγή κατάστασης.
  ///
  /// Η κατάσταση ζει σε δύο θέσεις — στον provider για τις οθόνες, και στο
  /// [DatabaseReachabilitySignal] για τον κανόνα επανάληψης. Αν γράφονταν
  /// χωριστά, θα αρκούσε ένα ξεχασμένο σημείο για να λέει η μία το αντίθετο
  /// από την άλλη.
  void _publish(DatabaseReachability value) {
    state = value;
    DatabaseReachabilitySignal.publish(value);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _watchedPath = null;
    DatabaseStallReports.listen(null);
    // Χωρίς φύλακα δεν υπάρχει γνώση· η άγνοια δεν επιτρέπεται να κρατά τις
    // οθόνες σε κατάσταση «χαμένη βάση» για την υπόλοιπη συνεδρία.
    DatabaseReachabilitySignal.publish(DatabaseReachability.ok);
  }
}
