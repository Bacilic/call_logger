import 'dart:async';

import '../updates/update_check_result.dart';
import 'startup_journal.dart';

/// Πόσο περιμένει η εκκίνηση τον έλεγχο νέας έκδοσης πριν προχωρήσει.
///
/// Ο έλεγχος διαβάζει το `version.json` από κοινόχρηστο φάκελο του τοπικού
/// δικτύου. Όταν ο φάκελος είναι άφταστος — πεσμένο δίκτυο, ή η εφαρμογή
/// ανοιγμένη από το σπίτι — το λειτουργικό δεν απαντά «δεν υπάρχει» αμέσως:
/// περιμένει το δικό του, πολύ μεγαλύτερο, όριο δικτύου. Χωρίς αυτό το φρένο,
/// μια απλή ευγενική ερώτηση θα κρατούσε την πόρτα κλειστή για δεκάδες
/// δευτερόλεπτα.
const Duration kStartupUpdateCheckTimeout = Duration(milliseconds: 1500);

/// Τρέχει τον έλεγχο νέας έκδοσης ως βήμα εκκίνησης, με σκληρό όριο αναμονής.
///
/// Δεν πετάει ποτέ: ο έλεγχος έκδοσης είναι ευκολία, όχι προϋπόθεση. Κάθε
/// έκβαση γίνεται μία γραμμή στο ημερολόγιο και τίποτα περισσότερο.
Future<UpdateCheckResult?> runStartupUpdateCheck(
  Future<UpdateCheckResult> Function() check, {
  Duration timeout = kStartupUpdateCheckTimeout,
  StartupJournal? journal,
}) async {
  final step = (journal ?? StartupJournal.instance)
      .begin('Έλεγχος για νέα έκδοση');
  try {
    final result = await check().timeout(timeout);
    if (result.checkedAt == null) {
      // Ο έλεγχος δεν έγινε πραγματικά (build ανάπτυξης, χωρίς ρυθμισμένο
      // φάκελο). Δεν το ανακοινώνουμε ως κάτι που συνέβη.
      step.skip();
      return result;
    }
    step.ok(
      result.updateAvailable
          ? 'Νέα έκδοση διαθέσιμη: ${result.latestVersion ?? ''}'.trimRight()
          : 'Έλεγχος για νέα έκδοση — είστε ενημερωμένοι',
    );
    return result;
  } on TimeoutException {
    step.warn(
      'Δεν απάντησε μέσα σε ${timeout.inMilliseconds} ms.',
      'Ο φάκελος ενημερώσεων δεν ήταν διαθέσιμος',
    );
    return null;
  } catch (e) {
    step.warn(e.toString(), 'Ο φάκελος ενημερώσεων δεν ήταν διαθέσιμος');
    return null;
  }
}
