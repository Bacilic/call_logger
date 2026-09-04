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

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Η κατάσταση όπως τη βλέπει ο χειριστής.
enum DatabaseReachability {
  /// Το αρχείο απαντά.
  ok,

  /// Το αρχείο έπαψε να απαντά.
  lost,
}

/// Κρατά την ιστορία των ελέγχων και αποφασίζει **πότε** λέμε «χάθηκε».
///
/// **Δύο συνεχόμενες αποτυχίες, όχι μία.** Μια στιγμιαία αναλαμπή του δικτύου
/// δεν πρέπει να πετά κόκκινη λωρίδα στα μούτρα του χειριστή τη στιγμή που
/// γράφει μια κλήση. Η επιστροφή όμως είναι **άμεση**: μία επιτυχία αρκεί —
/// όταν το δίκτυο γυρίσει, δεν έχει νόημα να κρατάμε τον συναγερμό.
class DatabaseReachabilityTracker {
  DatabaseReachabilityTracker({this.failuresBeforeAlarm = 2});

  /// Πόσες συνεχόμενες αποτυχίες χρειάζονται πριν σημάνει ο συναγερμός.
  final int failuresBeforeAlarm;

  int _consecutiveFailures = 0;

  DatabaseReachability get state => _consecutiveFailures >= failuresBeforeAlarm
      ? DatabaseReachability.lost
      : DatabaseReachability.ok;

  /// Καταγράφει το αποτέλεσμα ενός ελέγχου και επιστρέφει τη νέα κατάσταση.
  DatabaseReachability record({required bool probeSucceeded}) {
    if (probeSucceeded) {
      _consecutiveFailures = 0;
    } else if (_consecutiveFailures < failuresBeforeAlarm) {
      _consecutiveFailures++;
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
      _lastProbeFailed || state == DatabaseReachability.lost
      ? alertInterval
      : calmInterval;

  @override
  DatabaseReachability build() {
    ref.onDispose(() => _timer?.cancel());
    return DatabaseReachability.ok;
  }

  /// Ξεκινά τον περιοδικό έλεγχο για τη συγκεκριμένη διαδρομή.
  ///
  /// Καλείται ξανά σε κάθε αλλαγή βάσης· ο προηγούμενος φύλακας σταματά, ώστε
  /// να μη μείνουν δύο να ρωτούν διαφορετικά αρχεία.
  void watch(String? databasePath) {
    _timer?.cancel();
    _tracker.record(probeSucceeded: true);
    state = DatabaseReachability.ok;

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

  Future<void> _runCheck() async {
    final path = _watchedPath;
    if (path == null) return;
    final ok = await probeDatabaseFile(path);
    _lastProbeFailed = !ok;
    final next = _tracker.record(probeSucceeded: ok);
    if (next != state) state = next;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
