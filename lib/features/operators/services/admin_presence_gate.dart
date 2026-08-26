import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/database/operator_repository.dart';
import '../../../core/models/operator.dart';
import 'operator_management.dart';

/// Η κατάσταση των διαχειριστών μιας βάσης, διαβασμένη **μονομιάς**.
///
/// Το «χρειάζεται ορισμός;» και το «ποιοι μπορούν να οριστούν;» βγαίνουν από
/// την ίδια ανάγνωση επίτηδες: δύο χωριστά ερωτήματα θα μπορούσαν να πέσουν σε
/// διαφορετικά στιγμιότυπα και να δώσουν οθόνη που ζητά ορισμό με άδεια λίστα.
class AdminPresenceState {
  const AdminPresenceState({
    required this.needsSetup,
    required this.candidates,
  });

  /// Καμία βάση δεν χρειάζεται ορισμό ώσπου να διαβαστεί — η ασφαλής αφετηρία.
  static const AdminPresenceState fine = AdminPresenceState(
    needsSetup: false,
    candidates: <Operator>[],
  );

  /// Υπάρχουν ενεργά προφίλ, αλλά κανένα δεν είναι διαχειριστής.
  final bool needsSetup;

  /// Τα ενεργά προφίλ που μπορούν να οριστούν διαχειριστές.
  final List<Operator> candidates;
}

/// Ο έλεγχος «έχει αυτή η βάση διαχειριστή;» στο άνοιγμα.
///
/// **Γιατί υπάρχει:** η διαχείριση προφίλ επιτρέπεται μόνο σε διαχειριστή, και
/// δεν υπάρχουν κωδικοί — άρα βάση χωρίς κανέναν ενεργό διαχειριστή κλειδώνει
/// μόνιμα: κανείς δεν μπορεί να ορίσει κανέναν, και η «Αλλαγή χρήστη»
/// προσφέρει μόνο εξίσου ανίσχυρα προφίλ. Η σήμανση μπορεί να χαθεί από
/// επεξεργασία με εξωτερικό εργαλείο, από επαναφορά παλιού αντιγράφου ή από
/// βάση φτιαγμένη έξω από την εφαρμογή.
///
/// **Άδεια βάση δεν είναι πρόβλημα:** εκεί ο πρώτος που θα συστηθεί γίνεται
/// διαχειριστής της, όπως πάντα.
abstract final class AdminPresenceGate {
  /// Η κρίση πάνω σε λίστα που έχει ήδη διαβαστεί — χωρίς βάση, ώστε να
  /// ελέγχεται μόνη της.
  static AdminPresenceState evaluate(List<Operator> all) {
    final active = [
      for (final operator in all)
        if (operator.isActive) operator,
    ];
    if (active.isEmpty) return AdminPresenceState.fine;
    if (active.any((operator) => operator.isAdmin)) {
      return AdminPresenceState.fine;
    }
    return AdminPresenceState(needsSetup: true, candidates: active);
  }

  /// Η ίδια κρίση, ρωτώντας τη βάση.
  ///
  /// Αποτυχία ανάγνωσης **δεν** μπλοκάρει την εκκίνηση: η δικλείδα είναι
  /// φύλακας, όχι προϋπόθεση. Μια βάση που δεν διαβάζεται έχει ήδη δικά της
  /// μηνύματα σφάλματος, πολύ πιο κατατοπιστικά από μια οθόνη διαχειριστή.
  static Future<AdminPresenceState> read(DatabaseExecutor db) async {
    try {
      return evaluate(await OperatorRepository(db).getAll());
    } catch (_) {
      return AdminPresenceState.fine;
    }
  }

  /// Ορίζει το επιλεγμένο προφίλ ως διαχειριστή της βάσης.
  ///
  /// Περνά από την [OperatorManagement] και όχι κατευθείαν στη βάση, ώστε η
  /// αλλαγή να γραφτεί στο Ιστορικό όπως κάθε άλλη σήμανση διαχειριστή — και
  /// να ανανεωθεί η τρέχουσα ταυτότητα αν ο χρήστης όρισε τον εαυτό του.
  static Future<OperatorActionResult> promote(
    DatabaseExecutor db,
    Operator chosen,
  ) async {
    final repository = OperatorRepository(db);
    // Η κρίση γίνεται με τη ΒΑΣΗ: η λίστα της οθόνης διαβάστηκε πριν από λίγο
    // και ο συνάδελφος μπορεί να έχει προλάβει να ορίσει κάποιον στο μεταξύ.
    final fresh = chosen.id == null
        ? null
        : await repository.findById(chosen.id!);
    if (fresh == null) {
      return const OperatorActionResult.blocked(
        'Το προφίλ δεν υπάρχει πια σε αυτή τη βάση.',
      );
    }
    return OperatorManagement(repository).save(
      fresh,
      displayName: fresh.displayName,
      windowsAccount: fresh.windowsAccount,
      isAdmin: true,
      isActive: fresh.isActive,
    );
  }
}
