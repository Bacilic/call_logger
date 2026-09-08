import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/calls/provider/call_mutation_refresh.dart';
import '../../features/directory/providers/category_directory_provider.dart';
import '../../features/directory/providers/department_directory_provider.dart';
import '../../features/directory/providers/directory_cache_refresh.dart';
import '../../features/tasks/providers/tasks_provider.dart';
import '../widgets/modal_route_tracker.dart';
import 'database_helper.dart';
import 'database_reachability.dart';
import 'shared_database_change_watcher.dart';

/// Πόσο συχνά ρωτάμε αν έγραψε άλλο μηχάνημα.
///
/// Το ερώτημα είναι ένα `PRAGMA` που δεν διαβάζει δεδομένα, αλλά ταξιδεύει στο
/// δίκτυο. Τα 12'' είναι ο συμβιβασμός: η εικόνα δεν γερνά αισθητά μέσα σε μια
/// συζήτηση, και ο δικτυακός φάκελος δεν βομβαρδίζεται.
const Duration kSharedDatabaseCheckInterval = Duration(seconds: 12);

/// Ό,τι ξαναδιαβάζεται όταν **άλλο μηχάνημα** γράψει στην κοινόχρηστη βάση.
///
/// Ένα σημείο επίτηδες: η απάντηση στο «τι γερνά όταν γράψει ο συνάδελφος» δεν
/// επιτρέπεται να ζει σκορπισμένη. Κάθε νέα οθόνη που θέλει φρεσκάδα
/// προστίθεται **εδώ**, και τότε ισχύει για όλες τις αφορμές ανανέωσης μαζί.
///
/// Δεν αδειάζει τίποτα: μετρήθηκε (24/08) ότι η ακύρωση σε provider που κρατά
/// ήδη δεδομένα δείχνει την **παλιά** τιμή ώσπου να έρθει η νέα, χωρίς
/// ενδιάμεσο δείκτη φόρτωσης. Η λίστα αντικαθίσταται, δεν αναβοσβήνει.
///
/// Οι οθόνες των κλήσεων είναι `autoDispose`: όποια δεν κοιτάζει κανείς εκείνη
/// τη στιγμή δεν υπάρχει, και η ακύρωσή της δεν κοστίζει ερώτημα.
/// Η σειρά είναι σκόπιμη: **πρώτα όσα φορτώνουν** (περιμένουν τη βάση), μετά
/// όσα απλώς ακυρώνονται. Έτσι η αναμονή του ενός δεν προλαβαίνει να ξεπλύνει
/// τις ακυρώσεις του άλλου πριν προλάβει να τις δει όποιος ακούει.
Future<void> refreshSharedDatabaseViews(Ref ref) async {
  await ref.read(tasksProvider.notifier).refresh();
  // Τα τμήματα τροφοδοτούν ΚΑΙ τον χάρτη κτιρίου, όπου η μπαγιάτικη εικόνα δεν
  // κρύβει απλώς τη δουλειά του άλλου: η αυτόματη επιλογή χρώματος ρωτά αυτή τη
  // λίστα για να δώσει «διακριτό» χρώμα στον όροφο, οπότε δύο τμήματα
  // κατέληγαν με το ίδιο. Φόρτωση και όχι ακύρωση — ο notifier κρατά δεδομένα,
  // και η ακύρωση θα άδειαζε την οθόνη ώσπου να έρθουν τα νέα.
  await ref.read(departmentDirectoryProvider.notifier).loadDepartments();
  if (!ref.mounted) return;
  // Ο Κατάλογος δεν είναι απλώς μια ακόμη οθόνη που γερνά: οι καρτέλες του
  // γράφονται ΟΛΟΚΛΗΡΕΣ, και η αφετηρία της σύγκρισης είναι η εγγραφή όπως
  // τη φόρτωσε αυτή η λίστα. Όσο έλειπε από εδώ, η αλλαγή του συναδέλφου
  // έμενε αόρατη επ' αόριστον και ο φρουρός μπλόκαρε τη ΔΙΚΗ μου αποθήκευση
  // — ξανά και ξανά, χωρίς τρόπο να ξεμπλοκάρω.
  await refreshDirectoryCaches(ref, users: true, equipment: true);
  if (!ref.mounted) return;
  await ref.read(categoryDirectoryProvider.notifier).loadCategories();
  if (!ref.mounted) return;
  // Ιστορικό, Στατιστικά, ουρά Αναφοράς Lansweeper και πρόσφατες κλήσεις μαζί.
  refreshAfterCallMutation(ref);
}

/// Ο φρουρός της κοινόχρηστης βάσης για αυτή τη συνεδρία.
///
/// Στήνεται από το κέλυφος (`main_shell`) ώστε να ζει όσο και η εφαρμογή: ο
/// μετρητής της πλευρικής μπάρας πρέπει να ενημερώνεται και όταν ο χρήστης
/// βρίσκεται σε άλλη οθόνη.
final sharedDatabaseChangeWatcherProvider =
    Provider<SharedDatabaseChangeWatcher>((ref) {
      // Η επιστροφή της βάσης είναι αλλαγή σαν κάθε άλλη — απλώς έρχεται
      // από το δίκτυο και όχι από συνάδελφο. Ο φύλακας τη διαπιστώνει σε
      // δευτερόλεπτα· χωρίς αυτή τη γραμμή η κόκκινη λωρίδα έσβηνε και οι
      // οθόνες έμεναν με το σφάλμα τους, λέγοντας «όλα καλά» και δείχνοντας
      // αποτυχία.
      //
      // ΜΟΝΟ στη μετάβαση «χαμένη → εντάξει»: το ξαναφόρτωμα κοστίζει
      // ερωτήματα και δεν έχει λόγο να τρέχει σε κάθε επιτυχημένο έλεγχο.
      ref.listen<DatabaseReachability>(databaseReachabilityProvider, (
        previous,
        next,
      ) {
        if (!isDatabaseReturn(previous, next)) return;
        unawaited(refreshSharedDatabaseViews(ref));
      });

      final tracker = appModalRouteTracker;
      final watcher = SharedDatabaseChangeWatcher(
        interval: kSharedDatabaseCheckInterval,
        readVersion: DatabaseHelper.instance.readDataVersion,
        isBusy: () => tracker.isUserBusy,
        onChanged: () => refreshSharedDatabaseViews(ref),
      );

      // Στα widget τεστ ο χρόνος είναι πλαστός και τρέχει κατά λεπτά μέσα σε
      // ένα `pump`: ένας παλμός των 12'' θα πυροδοτούσε και θα έμενε εκκρεμής,
      // ρίχνοντας κάθε τεστ που στήνει το κέλυφος. Ο φρουρός αφορά ζωντανή
      // κοινόχρηστη βάση — σε τεστ δεν έχει τι να φυλάξει. Η ίδια η κλάση μένει
      // καθαρή και ελέγχεται χωριστά, με ρητά `checkNow()`.
      if (Platform.environment['FLUTTER_TEST'] != 'true') watcher.start();

      // Μόλις κλείσει ο τελευταίος διάλογος, η κρατημένη ανανέωση εκτελείται
      // αμέσως — ο χρήστης βλέπει την αλήθεια χωρίς να περιμένει τον κύκλο.
      final previous = tracker.onAllClosed;
      tracker.onAllClosed = () => watcher.flushPending();

      ref.onDispose(() {
        tracker.onAllClosed = previous;
        watcher.dispose();
      });
      return watcher;
    });
