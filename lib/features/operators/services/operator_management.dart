import '../../../core/database/operator_audit.dart';
import '../../../core/database/operator_repository.dart';
import '../../../core/models/operator.dart';
import '../../../core/services/current_operator.dart';
import '../avatars/operator_avatar_assignment.dart';
import 'operator_save_conflict.dart';

/// Το αποτέλεσμα μιας ενέργειας διαχείρισης χρηστών.
///
/// Ποτέ σιωπηλή αποτυχία: όταν κάτι δεν επιτρέπεται, ο λόγος γράφεται εδώ και
/// φτάνει στον χρήστη με τα λόγια του.
class OperatorActionResult {
  const OperatorActionResult.ok([this.operator])
    : allowed = true,
      message = null,
      conflict = null;

  const OperatorActionResult.blocked(this.message)
    : allowed = false,
      operator = null,
      conflict = null;

  /// Η καρτέλα άλλαξε από άλλον — η αποθήκευση σταμάτησε πριν γράψει.
  ///
  /// Το [message] συμπληρώνεται κι εδώ επίτηδες: όποιος καλών δεν κοιτάξει το
  /// [conflict] θα δείξει κάτι **αληθές** («κάποιος άλλος την άλλαξε») αντί να
  /// αποθηκεύσει σιωπηλά ή να μείνει βουβός.
  OperatorActionResult.conflictFound(OperatorSaveConflict found)
    : allowed = false,
      operator = null,
      conflict = found,
      message =
          'Η καρτέλα άλλαξε από άλλον χρήστη στο μεταξύ '
          '(${found.changedFields.join(', ')}). '
          'Κλείστε την και ξανανοίξτε τη για να δείτε τα τρέχοντα στοιχεία.';

  final bool allowed;
  final String? message;
  final Operator? operator;
  final OperatorSaveConflict? conflict;
}

/// Τα μηνύματα του φρουρού «πρέπει να μείνει ένας διαχειριστής» — **μία πηγή**.
///
/// Τα ίδια λόγια εμφανίζονται και από τον άμεσο φραγμό της φόρμας (πάτημα στον
/// διακόπτη) και από τον έλεγχο της αποθήκευσης· δύο αντίγραφα θα απέκλιναν
/// σιωπηλά στην πρώτη αναδιατύπωση.
const String kLastAdminDemoteBlockedMessage =
    'Πρέπει να μείνει τουλάχιστον ένας διαχειριστής. Ορίστε '
    'πρώτα άλλον και μετά αφαιρέστε τη σήμανση από εδώ.';
const String kLastAdminDeactivateBlockedMessage =
    'Ο μοναδικός διαχειριστής δεν απενεργοποιείται. Ορίστε πρώτα '
    'άλλον διαχειριστή.';

/// Είναι αυτό το προφίλ ο τελευταίος διαχειριστής που μπορεί να συνδεθεί;
///
/// Κρίνει πάνω σε λίστα που έχει ήδη διαβαστεί — για τον **άμεσο** φραγμό της
/// φόρμας, ώστε ο χρήστης να μάθει το «γιατί όχι» στο πάτημα του διακόπτη και
/// όχι στην Αποθήκευση. Δεν αντικαθιστά τον έλεγχο της αποθήκευσης: εκείνος
/// ξαναρωτά τη βάση, γιατί η λίστα της οθόνης μπορεί να έχει παλιώσει όσο
/// δούλευε δίπλα ένας συνάδελφος.
bool isLastActiveAdmin(Operator operator, List<Operator> all) {
  if (!operator.isAdmin || !operator.isActive) return false;
  final activeAdmins = [
    for (final candidate in all)
      if (candidate.isAdmin && candidate.isActive) candidate,
  ];
  return activeAdmins.length <= 1;
}

/// Οι κανόνες της διαχείρισης χρηστών — έξω από τα widgets.
///
/// Το widget δείχνει και ρωτά· εδώ αποφασίζεται τι επιτρέπεται και γιατί.
class OperatorManagement {
  const OperatorManagement(this._repository);

  final OperatorRepository _repository;

  Future<List<Operator>> load() => _repository.getAll();

  /// Δημιουργεί προφίλ. Κενός λογαριασμός Windows σημαίνει αυτόνομο προφίλ.
  ///
  /// Το εικονίδιο δίνεται εδώ, αυτόματα: ο διαχειριστής που φτιάχνει προφίλ για
  /// συνάδελφο δεν έχει λόγο να διαλέξει πρόσωπο εκ μέρους του — και ο ίδιος ο
  /// συνάδελφος μπορεί να το αλλάξει αργότερα από την καρτέλα του.
  Future<OperatorActionResult> create({
    required String displayName,
    String? windowsAccount,
    bool isAdmin = false,
    Map<String, bool> permissionOverrides = const <String, bool>{},
    String? avatarKey,
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

    final taken = takenAvatarKeys(await _repository.getAll());
    final avatarProblem = _avatarProblem(avatarKey, taken);
    if (avatarProblem != null) {
      return OperatorActionResult.blocked(avatarProblem);
    }

    final created = await _repository.insert(
      Operator(
        displayName: name,
        windowsAccount: account,
        isAdmin: isAdmin,
        permissionOverrides: permissionOverrides,
        // Ό,τι διάλεξε ρητά ο διαχειριστής νικά· αλλιώς πέφτει ο κλήρος.
        avatarKey: avatarKey ?? pickAvatarKey(taken),
        createdAt: now ?? DateTime.now(),
      ),
    );
    await OperatorAudit.logCreated(_repository.db, created);
    return OperatorActionResult.ok(created);
  }

  /// Αποθηκεύει τις αλλαγές ενός προφίλ, αφού περάσουν όλες οι δικλείδες.
  ///
  /// Με [force] `true` η αποθήκευση περνά παρά τη διένεξη — ο διαχειριστής είδε
  /// τι άλλαξε ο συνάδελφός του και επέλεξε να κρατήσει τη δική του εικόνα.
  Future<OperatorActionResult> save(
    Operator original, {
    required String displayName,
    required String? windowsAccount,
    required bool isAdmin,
    required bool isActive,
    Map<String, bool>? permissionOverrides,
    String? avatarKey,
    bool clearAvatarKey = false,
    bool force = false,
  }) async {
    final id = original.id;
    if (id == null) {
      return const OperatorActionResult.blocked(
        'Το προφίλ δεν έχει αποθηκευτεί ακόμη.',
      );
    }

    final name = displayName.trim();
    final account = normalizeWindowsAccount(windowsAccount);

    // `null` στα δικαιώματα σημαίνει «ο καλών δεν ασχολήθηκε» — τα υπάρχοντα
    // μένουν ως έχουν. Κενός χάρτης σημαίνει «καμία παράκαμψη», που είναι
    // διαφορετικό πράγμα και πρέπει να μπορεί να γραφτεί.
    final updated = original.copyWith(
      displayName: name,
      windowsAccount: account,
      clearWindowsAccount: account == null,
      isAdmin: isAdmin,
      isActive: isActive,
      permissionOverrides: permissionOverrides,
      avatarKey: avatarKey,
      clearAvatarKey: clearAvatarKey,
    );

    // ΠΡΩΤΑ η διένεξη, πριν από κάθε άλλο κανόνα. Ένας κανόνας που κρίνει πάνω
    // σε παλιά δεδομένα δίνει σωστή προστασία με λάθος αιτιολογία: ο χρήστης
    // διάβαζε «πρέπει να μείνει ένας διαχειριστής» ενώ το πραγματικό θέμα ήταν
    // ότι ο συνάδελφός του είχε προλάβει.
    if (!force) {
      final conflict = await _repository.conflictFor(
        expected: original,
        attempted: updated,
      );
      if (conflict != null) return _conflictResult(conflict, id);
    }

    final nameProblem = await _displayNameProblem(name, excludeId: id);
    if (nameProblem != null) return OperatorActionResult.blocked(nameProblem);

    final accountProblem = await _windowsAccountProblem(account, excludeId: id);
    if (accountProblem != null) {
      return OperatorActionResult.blocked(accountProblem);
    }

    // Το εικονίδιο κρίνεται τώρα, με τη ΒΑΣΗ: όσο η καρτέλα ήταν ανοιχτή, ο
    // συνάδελφος δίπλα μπορεί να διάλεξε το ίδιο. Ο έλεγχος αφορά μόνο τα
    // ενεργά προφίλ — ο απενεργοποιημένος κρατά το δικό του αλλά δεν το
    // δεσμεύει.
    if (updated.isActive) {
      final avatarProblem = _avatarProblem(
        updated.avatarKey,
        takenAvatarKeys(await _repository.getAll(), excludeId: id),
      );
      if (avatarProblem != null) {
        return OperatorActionResult.blocked(avatarProblem);
      }
    }

    // Η κρίση γίνεται με τη ΒΑΣΗ, όχι με την εικόνα της φόρμας: αν ο συνάδελφος
    // προήγαγε αυτό το προφίλ από άλλη οθόνη, η μπαγιάτικη καρτέλα δεν το ξέρει
    // και ο έλεγχος «πρέπει να μείνει ένας διαχειριστής» θα έκρινε με το παλιό
    // «δεν ήταν διαχειριστής» — δηλαδή δεν θα πυροδοτούσε καθόλου.
    final storedIsAdmin =
        (await _repository.findById(id))?.isAdmin ?? original.isAdmin;
    final losesAdmin = storedIsAdmin && !isAdmin;
    final getsArchived = storedIsAdmin && isAdmin && !isActive;
    if (losesAdmin || getsArchived) {
      final remaining = await _repository.countActiveAdmins();
      if (remaining <= 1) {
        return OperatorActionResult.blocked(
          losesAdmin
              ? kLastAdminDemoteBlockedMessage
              : kLastAdminDeactivateBlockedMessage,
        );
      }
    }

    try {
      // Ο φρουρός του repository ξανατρέχει εδώ ως δίχτυ — φθηνός, και πιάνει
      // την κούρσα που άνοιξε όσο έτρεχαν οι υπόλοιποι έλεγχοι.
      await _repository.update(updated, expected: original, force: force);
    } on OperatorStaleException catch (e) {
      return _conflictResult(e.conflict, id);
    }
    await OperatorAudit.logUpdated(
      _repository.db,
      before: original,
      after: updated,
    );
    _refreshActiveIdentity(updated);
    return OperatorActionResult.ok(updated);
  }

  /// Ντύνει τη διένεξη με το «ποιος και πότε» και τη δίνει στον καλούντα.
  ///
  /// Η ταυτότητα δεν ζει στη γραμμή του προφίλ — μόνο στο Ιστορικό. Ζητείται
  /// **αφού** η διένεξη διαπιστωθεί, ώστε η κανονική αποθήκευση να μην πληρώνει
  /// ποτέ το ερώτημα.
  Future<OperatorActionResult> _conflictResult(
    OperatorSaveConflict conflict,
    int operatorId,
  ) async {
    final actor = await OperatorAudit.lastActorFor(_repository.db, operatorId);
    return OperatorActionResult.conflictFound(
      OperatorSaveConflict(
        expected: conflict.expected,
        fresh: conflict.fresh,
        attempted: conflict.attempted,
        changedBy: actor.who,
        changedAt: actor.at,
      ),
    );
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

  /// Το εικονίδιο είναι πιασμένο από άλλον ενεργό χρήστη;
  ///
  /// Το κενό εικονίδιο (κλασικό ανθρωπάκι) δεν ελέγχεται ποτέ: το μοιράζονται
  /// όσοι θέλουν, γιατί δεν ξεχωρίζει κανέναν.
  String? _avatarProblem(String? avatarKey, Set<String> taken) {
    if (avatarKey == null || avatarKey.isEmpty) return null;
    if (!taken.contains(avatarKey)) return null;
    return 'Αυτό το εικονίδιο το κρατά ήδη άλλος χρήστης. Διαλέξτε άλλο — '
        'δύο χρήστες με το ίδιο πρόσωπο δεν ξεχωρίζουν πουθενά.';
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
