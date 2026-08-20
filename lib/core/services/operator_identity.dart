import 'dart:io';

import 'package:sqflite_common/sqlite_api.dart';

import '../database/operator_repository.dart';
import '../models/operator.dart';
import 'current_operator.dart';

/// Ποιος κάθεται μπροστά στην οθόνη — αναγνώριση χωρίς κωδικούς.
///
/// Η εφαρμογή διαβάζει τον λογαριασμό Windows και βρίσκει μόνη της το προφίλ.
/// Όταν δεν τον αναγνωρίζει **δεν μαντεύει**: επιστρέφει άδεια και ρωτά, γιατί
/// σε κοινόχρηστο λογαριασμό η αυτόματη δημιουργία θα χρέωνε τις ενέργειες
/// όλων σε ένα πρόσωπο.
class OperatorIdentity {
  const OperatorIdentity._();

  /// Ο λογαριασμός Windows της τρέχουσας συνεδρίας, όπως τον δίνει το σύστημα.
  static String? get currentWindowsAccount =>
      Platform.environment['USERNAME'] ?? Platform.environment['USER'];

  /// Βρίσκει το προφίλ του τρέχοντος λογαριασμού και το ορίζει ως ενεργό.
  ///
  /// Επιστρέφει `null` όταν δεν υπάρχει ταύτιση — τότε αποφασίζει ο άνθρωπος,
  /// από την οθόνη επιλογής.
  ///
  /// Η ταυτότητα **μηδενίζεται πρώτα**: μετά από αλλαγή βάσης τα προφίλ είναι
  /// άλλα, και μια αποτυχία δεν επιτρέπεται να αφήσει ενεργό τον χρήστη της
  /// προηγούμενης βάσης.
  ///
  /// Το [windowsAccount] δίνεται μόνο από ελέγχους.
  static Future<Operator?> resolveAndActivate(
    DatabaseExecutor db, {
    String? windowsAccount,
  }) async {
    CurrentOperator.reset();

    final account = normalizeWindowsAccount(
      windowsAccount ?? currentWindowsAccount,
    );
    if (account == null) return null;

    final existing = await OperatorRepository(db).findByWindowsAccount(account);
    if (existing == null) return null;

    CurrentOperator.activate(existing);
    return existing;
  }

  /// Τα προφίλ που προσφέρονται προς επιλογή — μόνο τα ενεργά.
  static Future<List<Operator>> selectableProfiles(DatabaseExecutor db) async {
    final all = await OperatorRepository(db).getAll();
    return [
      for (final operator in all)
        if (operator.isActive) operator,
    ];
  }

  /// Ενεργοποιεί υπάρχον προφίλ **για αυτή τη συνεδρία μόνο**.
  ///
  /// Δεν δένει τον λογαριασμό Windows: σε κοινόχρηστο υπολογιστή η επόμενη
  /// εκκίνηση πρέπει να ξαναρωτήσει. Το μόνιμο δέσιμο γίνεται ρητά, από την
  /// οθόνη «Χρήστες».
  static void activateForSession(Operator operator) {
    CurrentOperator.activate(operator);
  }

  /// Δημιουργεί προφίλ από την οθόνη επιλογής και το ενεργοποιεί.
  ///
  /// Με [bindCurrentAccount] το προφίλ δένεται στον λογαριασμό Windows, οπότε
  /// η επόμενη εκκίνηση δεν ξαναρωτά. Σε κοινόχρηστο υπολογιστή μένει `false`,
  /// αλλιώς όλοι θα έμπαιναν ως το ίδιο πρόσωπο.
  static Future<Operator> createAndActivate(
    DatabaseExecutor db, {
    required String displayName,
    required bool bindCurrentAccount,
    String? windowsAccount,
    DateTime? now,
  }) async {
    final repository = OperatorRepository(db);
    final account = bindCurrentAccount
        ? normalizeWindowsAccount(windowsAccount ?? currentWindowsAccount)
        : null;

    final created = await repository.insert(
      Operator(
        displayName: displayName.trim(),
        windowsAccount: account,
        // Ο πρώτος που στήνει τη βάση είναι ο διαχειριστής της. Όσο κανένα
        // δικαίωμα δεν επιβάλλεται η σήμανση δεν αλλάζει τίποτα στη χρήση —
        // διορθώνεται από την οθόνη «Χρήστες».
        isAdmin: await repository.count() == 0,
        createdAt: now ?? DateTime.now(),
      ),
    );
    CurrentOperator.activate(created);
    return created;
  }

  /// Πρόταση ονόματος για νέο προφίλ: ο λογαριασμός Windows, όπως τον γράφει
  /// το σύστημα. Είναι αφετηρία που ο άνθρωπος διορθώνει, όχι τελική τιμή.
  static String suggestedDisplayName({String? windowsAccount}) {
    final raw = (windowsAccount ?? currentWindowsAccount)?.trim() ?? '';
    if (raw.isEmpty) return '';
    final separator = raw.lastIndexOf('\\');
    return (separator >= 0 ? raw.substring(separator + 1) : raw).trim();
  }
}
