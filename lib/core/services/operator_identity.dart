import 'dart:io';

import 'package:sqflite_common/sqlite_api.dart';

import '../database/operator_audit.dart';
import '../database/operator_repository.dart';
import '../models/operator.dart';
import 'current_operator.dart';
import 'workstation_operators.dart';

/// Ποιος κάθεται μπροστά στην οθόνη — αναγνώριση χωρίς κωδικούς.
///
/// Η εφαρμογή ρωτά πρώτα τη μνήμη του σταθμού (ποιοι έχουν διαλέξει ταυτότητα
/// εδώ) και μετά τον λογαριασμό Windows. Όταν δεν καταλήγει σε ένα πρόσωπο
/// **δεν μαντεύει**: επιστρέφει άδεια και ρωτά, γιατί σε κοινόχρηστο σταθμό
/// μια λάθος εικασία χρεώνει τις ενέργειες σε άλλον άνθρωπο.
class OperatorIdentity {
  const OperatorIdentity._();

  /// Ο λογαριασμός Windows της τρέχουσας συνεδρίας, όπως τον δίνει το σύστημα.
  static String? get currentWindowsAccount =>
      Platform.environment['USERNAME'] ?? Platform.environment['USER'];

  /// Βρίσκει ποιος κάθεται εδώ και τον ορίζει ως ενεργό.
  ///
  /// Δύο ερωτήματα, με αυτή τη σειρά:
  ///
  /// 1. **Ποιοι έχουν δουλέψει σε αυτόν τον σταθμό;** Ένας ⇒ αυτός είναι, χωρίς
  ///    ερώτηση. Δύο ή περισσότεροι ⇒ `null`, δηλαδή ρωτά ο άνθρωπος: όπου
  ///    εναλλάσσονται πρόσωπα, καμία εικασία δεν είναι αρκετά καλή.
  /// 2. **Ποιον λέει ο λογαριασμός Windows;** Μόνο όταν ο σταθμός δεν θυμάται
  ///    κανέναν — πρώτη εκκίνηση, ή μετά από αλλαγή βάσης που δεν ξέρει αυτά
  ///    τα ονόματα.
  ///
  /// Επιστρέφει `null` όταν δεν καταλήγει σε ένα πρόσωπο — τότε αποφασίζει ο
  /// άνθρωπος, από την οθόνη επιλογής.
  ///
  /// Η ταυτότητα **μηδενίζεται πρώτα**: μετά από αλλαγή βάσης τα προφίλ είναι
  /// άλλα, και μια αποτυχία δεν επιτρέπεται να αφήσει ενεργό τον χρήστη της
  /// προηγούμενης βάσης.
  ///
  /// Τα [windowsAccount] και [workstationNames] δίνονται μόνο από ελέγχους.
  static Future<Operator?> resolveAndActivate(
    DatabaseExecutor db, {
    String? windowsAccount,
    List<String>? workstationNames,
  }) async {
    CurrentOperator.reset();

    final repository = OperatorRepository(db);
    final remembered = workstationNames ?? await WorkstationOperators.names();
    if (remembered.isNotEmpty) {
      final known = rememberedWorkstationProfiles(
        remembered,
        await repository.getAll(),
      );
      if (known.length > 1) return null;
      if (known.length == 1) {
        CurrentOperator.activate(known.single);
        return known.single;
      }
    }

    final account = normalizeWindowsAccount(
      windowsAccount ?? currentWindowsAccount,
    );
    if (account == null) return null;

    final existing = await repository.findByWindowsAccount(account);
    if (existing == null) return null;

    CurrentOperator.activate(existing);
    return existing;
  }

  /// Τα προφίλ που προσφέρονται προς επιλογή — μόνο τα ενεργά, **και ποτέ
  /// αυτός που είναι ήδη συνδεδεμένος**.
  ///
  /// «Αλλαγή χρήστη» σε αυτόν που είναι ήδη ο χρήστης δεν σημαίνει τίποτα. Στην
  /// οθόνη εκκίνησης δεν υπάρχει ακόμη συνδεδεμένος, οπότε εκεί η αφαίρεση δεν
  /// αγγίζει τίποτα — ένα σημείο, δύο σωστές συμπεριφορές.
  static Future<List<Operator>> selectableProfiles(DatabaseExecutor db) async =>
      selectableFrom(await OperatorRepository(db).getAll());

  /// Ο ίδιος κανόνας πάνω σε λίστα που έχει ήδη διαβαστεί — ώστε ο επιλογέας,
  /// που χρειάζεται και τα υπόλοιπα προφίλ, να μη ρωτά τη βάση δεύτερη φορά.
  static List<Operator> selectableFrom(List<Operator> all) {
    final activeId = CurrentOperator.active?.id;
    return [
      for (final operator in all)
        if (operator.isActive && (activeId == null || operator.id != activeId))
          operator,
    ];
  }

  /// Ενεργοποιεί υπάρχον προφίλ **χωρίς να το σημειώσει στον σταθμό**.
  ///
  /// Για εσωτερική χρήση και ελέγχους. Η ρητή ανθρώπινη επιλογή περνά από το
  /// [chooseForSession], ώστε ο σταθμός να θυμάται ποιος διάλεξε εδώ.
  static void activateForSession(Operator operator) {
    CurrentOperator.activate(operator);
  }

  /// Ο άνθρωπος διάλεξε ρητά ποιος είναι — από την οθόνη «Ποιος είστε;» ή τον
  /// διάλογο «Αλλαγή χρήστη».
  ///
  /// Ενεργοποιεί την ταυτότητα **και** τη σημειώνει στη μνήμη του σταθμού,
  /// ώστε η επόμενη εκκίνηση να μην ξεχάσει την επιλογή. Δεν δένει τον
  /// λογαριασμό Windows: αυτό είναι μόνιμη αντιστοίχιση προσώπου με λογαριασμό
  /// και γίνεται ρητά, από την οθόνη «Χρήστες».
  static Future<void> chooseForSession(Operator operator) async {
    CurrentOperator.activate(operator);
    await WorkstationOperators.remember(operator.displayName);
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
    // Πρώτα η ταυτότητα, μετά η καταγραφή: αλλιώς η πρώτη εγγραφή της βάσης θα
    // έγραφε «—» στο «ποιος το έκανε» — τη μόνη εγγραφή για την οποία ξέρουμε
    // με βεβαιότητα ποιος ήταν.
    CurrentOperator.activate(created);
    // Η δημιουργία είναι κι αυτή ρητή επιλογή: ο σταθμός πρέπει να τη θυμάται
    // όπως θυμάται κάθε άλλη.
    await WorkstationOperators.remember(created.displayName);
    await OperatorAudit.logCreated(db, created);
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
