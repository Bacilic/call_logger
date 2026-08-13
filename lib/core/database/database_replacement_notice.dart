import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database_helper.dart';
import 'database_replacement_watchdog.dart';

/// Κάθε πότε ρωτά ο φρουρός αν το αρχείο βάσης είναι ακόμα το ίδιο.
///
/// Ένα λεπτό: η ερώτηση κοστίζει την ανάγνωση 100 bytes, αλλά σε δικτυακό
/// φάκελο ταξιδεύει. Το περιστατικό είναι σπάνιο και δεν επείγει να το μάθουμε
/// στο δευτερόλεπτο — αρκεί να το μάθουμε **πριν** ο χρήστης δουλέψει πολλή ώρα
/// πάνω σε λάθος δεδομένα. Σταθερά, όχι ρύθμιση.
const Duration kDatabaseReplacementCheckInterval = Duration(seconds: 60);

/// Το μήνυμα προς τον χρήστη, σε ένα σημείο.
String databaseReplacementMessage(String? databasePath) {
  final where = (databasePath ?? '').trim();
  return 'Το αρχείο της βάσης άλλαξε από κάποιο άλλο πρόγραμμα ενώ η εφαρμογή '
      'ήταν ανοιχτή${where.isEmpty ? '' : ':\n\n$where'}\n\n'
      'Αυτό συμβαίνει όταν αντιγραφεί άλλο αρχείο βάσης πάνω στο ενεργό. Για '
      'να μην αναμειχθούν τα παλιά με τα νέα δεδομένα, η εφαρμογή αποσυνδέθηκε '
      'χωρίς να γράψει τίποτα και θα διαβάσει από την αρχή το αρχείο που '
      'υπάρχει τώρα.\n\n'
      'Ό,τι δείχνει η οθόνη αυτή τη στιγμή μπορεί να προέρχεται από την '
      'προηγούμενη βάση.';
}

/// Καθολική κατάσταση: έχει ανιχνευθεί αντικατάσταση που δεν ανακοινώθηκε ακόμα;
///
/// Κρατά τη διαδρομή του αρχείου· `null` σημαίνει «τίποτα να πούμε». Όχι
/// autoDispose, ώστε να επιζεί του ξαναχτίσματος μετά την επαναρχικοποίηση.
final databaseReplacementNoticeProvider =
    NotifierProvider<DatabaseReplacementNoticeNotifier, String?>(
      DatabaseReplacementNoticeNotifier.new,
    );

class DatabaseReplacementNoticeNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String? databasePath) => state = databasePath ?? '';

  void clear() => state = null;
}

/// Ο φρουρός της τρέχουσας συνεδρίας, προσβάσιμος έξω από το δέντρο των widget.
///
/// Υπάρχει για έναν μόνο καλούντα: τον καθολικό χειριστή σφαλμάτων, που τρέχει
/// πριν από κάθε `ref` και πρέπει να μπορεί να ρωτήσει «μήπως αυτό το σφάλμα
/// είναι η αντικατάσταση;» τη στιγμή που συμβαίνει. Κάτοχος παραμένει ο
/// [databaseReplacementWatchdogProvider], που τον στήνει και τον ξηλώνει.
DatabaseReplacementWatchdog? _activeWatchdog;

/// Ζητά άμεσο έλεγχο, εκτός σειράς. Επιστρέφει `true` όταν η αντικατάσταση
/// επιβεβαιώθηκε και ο φρουρός ανέλαβε — οπότε ο καλών δεν έχει τίποτα να πει.
///
/// Χωρίς ενεργό φρουρό (τεστ, οθόνες πριν από το κέλυφος) απαντά `false`: η
/// άγνοια δεν καταπίνει ποτέ σφάλμα.
Future<bool> pokeDatabaseReplacementWatchdog() async {
  final watchdog = _activeWatchdog;
  if (watchdog == null) return false;
  if (watchdog.hasFired) return true;
  await watchdog.checkNow();
  return watchdog.hasFired;
}

/// Καταχωρεί τον [watchdog] ως τον ενεργό της συνεδρίας.
///
/// Καταχώρηση και ξήλωμα γράφονται μαζί, σε ένα σημείο: ένας φρουρός που μένει
/// καταχωρημένος αφού πεθάνει ο κάτοχός του θα απαντούσε «το χειρίζομαι εγώ»
/// σε σφάλματα που δεν χειρίζεται κανείς.
void registerActiveDatabaseReplacementWatchdog(
  Ref ref,
  DatabaseReplacementWatchdog watchdog,
) {
  _activeWatchdog = watchdog;
  ref.onDispose(() {
    if (identical(_activeWatchdog, watchdog)) _activeWatchdog = null;
    watchdog.dispose();
  });
}

/// Κρατά ζωντανό τον φρουρό όσο ζει το κέλυφος.
///
/// Η αντίδραση χωρίζεται σκόπιμα στα δύο: **εδώ** γίνεται ό,τι δεν αντέχει
/// αναμονή —η αποσύνδεση χωρίς checkpoint, που σταματά τη ζημιά— και **στο UI**
/// μένει μόνο η ανακοίνωση. Έτσι η προστασία δεν εξαρτάται από το αν υπάρχει
/// κάποιος να πατήσει «Εντάξει».
final databaseReplacementWatchdogProvider = Provider<DatabaseReplacementWatchdog>(
  (ref) {
    final helper = DatabaseHelper.instance;
    final watchdog = DatabaseReplacementWatchdog(
      interval: kDatabaseReplacementCheckInterval,
      detect: helper.databaseFileWasReplaced,
      onDetected: () async {
        final path = helper.openedDatabasePath;
        // ΠΡΩΤΑ η αποσύνδεση: όσο η σύνδεση ζει, κάθε εγγραφή πηγαίνει σε βάση
        // που δεν βρίσκεται πια εκεί. Το ίδιο το κλείσιμο ξέρει να μη γράψει
        // τίποτα πάνω σε αντικατεστημένο αρχείο.
        await helper.closeConnection();
        ref.read(databaseReplacementNoticeProvider.notifier).show(path);
      },
    )..start();
    registerActiveDatabaseReplacementWatchdog(ref, watchdog);
    return watchdog;
  },
);
