import '../../../core/database/operator_repository.dart';
import '../../../core/models/operator.dart';
import '../../../core/services/current_operator.dart';

/// Το αποτέλεσμα μιας ενέργειας διαχείρισης χρηστών.
///
/// Ποτέ σιωπηλή αποτυχία: όταν κάτι δεν επιτρέπεται, ο λόγος γράφεται εδώ και
/// φτάνει στον χρήστη με τα λόγια του.
class OperatorActionResult {
  const OperatorActionResult.ok([this.operator])
    : allowed = true,
      message = null;

  const OperatorActionResult.blocked(this.message)
    : allowed = false,
      operator = null;

  final bool allowed;
  final String? message;
  final Operator? operator;
}

/// Οι κανόνες της διαχείρισης χρηστών — έξω από τα widgets.
///
/// Το widget δείχνει και ρωτά· εδώ αποφασίζεται τι επιτρέπεται και γιατί.
class OperatorManagement {
  const OperatorManagement(this._repository);

  final OperatorRepository _repository;

  Future<List<Operator>> load() => _repository.getAll();

  /// Δημιουργεί προφίλ. Κενός λογαριασμός Windows σημαίνει αυτόνομο προφίλ.
  Future<OperatorActionResult> create({
    required String displayName,
    String? windowsAccount,
    bool isAdmin = false,
    Map<String, bool> permissionOverrides = const <String, bool>{},
    DateTime? now,
  }) async {
    final name = displayName.trim();
    final nameProblem = await _displayNameProblem(name);
    if (nameProblem != null) return OperatorActionResult.blocked(nameProblem);

    final account = normalizeWindowsAccount(windowsAccount);
    final accountProblem = await _windowsAccountProblem(account);
    if (accountProblem != null) {
      return OperatorActionResult.blocked(accountProblem);
    }

    final created = await _repository.insert(
      Operator(
        displayName: name,
        windowsAccount: account,
        isAdmin: isAdmin,
        permissionOverrides: permissionOverrides,
        createdAt: now ?? DateTime.now(),
      ),
    );
    return OperatorActionResult.ok(created);
  }

  /// Αποθηκεύει τις αλλαγές ενός προφίλ, αφού περάσουν όλες οι δικλείδες.
  Future<OperatorActionResult> save(
    Operator original, {
    required String displayName,
    required String? windowsAccount,
    required bool isAdmin,
    required bool isActive,
    Map<String, bool>? permissionOverrides,
  }) async {
    final id = original.id;
    if (id == null) {
      return const OperatorActionResult.blocked(
        'Το προφίλ δεν έχει αποθηκευτεί ακόμη.',
      );
    }

    final name = displayName.trim();
    final nameProblem = await _displayNameProblem(name, excludeId: id);
    if (nameProblem != null) return OperatorActionResult.blocked(nameProblem);

    final account = normalizeWindowsAccount(windowsAccount);
    final accountProblem = await _windowsAccountProblem(account, excludeId: id);
    if (accountProblem != null) {
      return OperatorActionResult.blocked(accountProblem);
    }

    final losesAdmin = original.isAdmin && !isAdmin;
    final getsArchived = original.isAdmin && isAdmin && !isActive;
    if (losesAdmin || getsArchived) {
      final remaining = await _repository.countAdmins();
      if (remaining <= 1) {
        return OperatorActionResult.blocked(
          losesAdmin
              ? 'Πρέπει να μείνει τουλάχιστον ένας διαχειριστής. Ορίστε '
                    'πρώτα άλλον και μετά αφαιρέστε τη σήμανση από εδώ.'
              : 'Ο μοναδικός διαχειριστής δεν αρχειοθετείται. Ορίστε πρώτα '
                    'άλλον διαχειριστή.',
        );
      }
    }

    // `null` σημαίνει «ο καλών δεν ασχολήθηκε με δικαιώματα» — τα υπάρχοντα
    // μένουν ως έχουν. Κενός χάρτης σημαίνει «καμία παράκαμψη», που είναι
    // διαφορετικό πράγμα και πρέπει να μπορεί να γραφτεί.
    final updated = original.copyWith(
      displayName: name,
      windowsAccount: account,
      clearWindowsAccount: account == null,
      isAdmin: isAdmin,
      isActive: isActive,
      permissionOverrides: permissionOverrides,
    );
    await _repository.update(updated);
    _refreshActiveIdentity(updated);
    return OperatorActionResult.ok(updated);
  }

  /// Όταν αλλάζει το **δικό μας** προφίλ, η ταυτότητα ανανεώνεται αμέσως.
  ///
  /// Αλλιώς το Ιστορικό θα συνέχιζε να σφραγίζει με το παλιό όνομα μέχρι την
  /// επόμενη εκκίνηση — και κανείς δεν θα καταλάβαινε γιατί.
  void _refreshActiveIdentity(Operator updated) {
    final active = CurrentOperator.active;
    if (active == null || active.id == null) return;
    if (active.id != updated.id) return;
    CurrentOperator.activate(updated);
  }

  Future<String?> _displayNameProblem(String name, {int? excludeId}) async {
    if (name.isEmpty) {
      return 'Δώστε όνομα — με αυτό σφραγίζεται κάθε ενέργεια στο Ιστορικό.';
    }
    final duplicate = await _repository.findByDisplayName(
      name,
      excludeId: excludeId,
    );
    if (duplicate != null) {
      return 'Υπάρχει ήδη χρήστης «$name». Το Ιστορικό κρατά ονόματα, όχι '
          'κωδικούς: δύο ίδια δεν ξεχωρίζουν ποτέ ξανά.';
    }
    return null;
  }

  Future<String?> _windowsAccountProblem(
    String? account, {
    int? excludeId,
  }) async {
    if (account == null) return null;
    final owner = await _repository.findByWindowsAccount(account);
    if (owner == null || owner.id == excludeId) return null;
    return 'Ο λογαριασμός «$account» ανήκει ήδη στον χρήστη '
        '«${owner.displayName}».';
  }
}
