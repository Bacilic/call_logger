import 'lansweeper_department_accounts.dart';
import 'lansweeper_identity_diagnosis.dart';

/// Ένας υποψήφιος αιτών, με την προέλευσή του ώστε ο επιλογέας να ομαδοποιεί
/// ανά τμήμα όταν οι κλήσεις του ίδιου ticket έρχονται από περισσότερα.
class LansweeperRequesterCandidate {
  const LansweeperRequesterCandidate({
    required this.account,
    required this.departmentName,
  });

  final LansweeperAccount account;
  final String departmentName;
}

/// Ένας διακριτός καλών των επιλεγμένων κλήσεων — με ή χωρίς δικό του
/// αναγνωριστικό Lansweeper. Η σειρά μετράει: πρώτος ο καλών της κύριας.
class LansweeperTicketCaller {
  const LansweeperTicketCaller({
    required this.displayName,
    this.departmentName = '',
    this.username,
  });

  /// Πώς αναγνωρίζει ο χρήστης τον άνθρωπο («Ελένη Πλακογιάννη»).
  final String displayName;

  /// Το τμήμα του, για την ομαδοποίηση στον επιλογέα.
  final String departmentName;

  /// Το προσωπικό του αναγνωριστικό· null/κενό = δεν έχει.
  final String? username;

  bool get hasUsername => (username ?? '').trim().isNotEmpty;
}

/// Τι θα σταλεί ως αιτών και τι μπορεί να διαλέξει ο χρήστης πριν την αποστολή.
class LansweeperRequesterOptions {
  const LansweeperRequesterOptions({
    required this.selectedUsername,
    required this.candidates,
    required this.isChoosable,
  });

  /// Το αναγνωριστικό που θα φύγει στο ticket· `null` = αιτών ο πράκτορας.
  final String? selectedUsername;

  /// Οι λογαριασμοί των τμημάτων, με σειρά εμφάνισης.
  final List<LansweeperRequesterCandidate> candidates;

  /// `true` μόνο όταν αξίζει ερώτηση: ο καλών δεν έχει δικό του αναγνωριστικό
  /// και τα τμήματα προσφέρουν περισσότερους από έναν λογαριασμούς.
  final bool isChoosable;
}

/// Ποιος μπαίνει αιτών στο ticket, με σταθερή ιεραρχία:
///
/// **Ένα μόνο εμπλεκόμενο πρόσωπο** (μία κλήση, ή όλες του ίδιου καλούντα):
/// 1. Ο ίδιος ο καλών, όταν έχει αναγνωριστικό — δεν ρωτιέται τίποτα.
/// 2. Ο μοναδικός λογαριασμός του τμήματος — μπαίνει αυτόματα, φαίνεται όμως
///    στη φόρμα ώστε να μην είναι κρυφή απόφαση.
/// 3. Ένας από τους λογαριασμούς των τμημάτων — προεπιλέγεται ο πρώτος
///    ΕΓΚΥΡΟΣ (κατά τη διάγνωση ταυτότητας)· λογαριασμός με λάθος μορφή
///    δεν προτείνεται από μόνος του όταν υπάρχει καλύτερος, μένει όμως
///    επιλέξιμος — ίσως είναι η σπάνια εξαίρεση που το Lansweeper δέχεται,
///    και τον τελικό λόγο τον έχει έτσι κι αλλιώς το SearchUsers.
/// 4. Κανένας — το ticket βγαίνει με τον πράκτορα, όπως πριν από αυτή τη
///    δυνατότητα.
///
/// **Περισσότερα εμπλεκόμενα πρόσωπα** (διαφορετικοί καλούντες ή και
/// άγνωστοι μαζί): ο αιτών είναι ΑΠΟΦΑΣΗ, όχι αυτονόητο — ο επιλογέας
/// εμφανίζεται πάντα, με τα προσωπικά αναγνωριστικά όλων των καλούντων,
/// τους λογαριασμούς των τμημάτων όλων των κλήσεων και το «Χωρίς αιτούντα».
/// Προεπιλογή: ο καλών της κύριας (πρώτης) κλήσης όταν έχει αναγνωριστικό —
/// η συνηθισμένη ροή δεν χρειάζεται κανένα κλικ, αλλά η απόφαση είναι ορατή.
LansweeperRequesterOptions resolveLansweeperRequester({
  List<LansweeperTicketCaller> callers = const [],
  bool hasUnidentifiedCalls = false,
  required List<({String departmentName, List<LansweeperAccount> accounts})>
  departments,
}) {
  final partyCount = callers.length + (hasUnidentifiedCalls ? 1 : 0);

  // Ένα πρόσωπο με δικό του αναγνωριστικό: κερδίζει, χωρίς ερώτηση.
  if (partyCount <= 1 && callers.length == 1 && callers.first.hasUsername) {
    return LansweeperRequesterOptions(
      selectedUsername: callers.first.username!.trim(),
      candidates: const [],
      isChoosable: false,
    );
  }

  final candidates = <LansweeperRequesterCandidate>[];
  final seen = <String>{};

  // Πρώτα τα προσωπικά αναγνωριστικά των καλούντων — με το όνομά τους ως
  // ονομασία, ώστε ο επιλογέας να μιλά για ανθρώπους, όχι για λογαριασμούς.
  for (final caller in callers) {
    if (!caller.hasUsername) continue;
    final username = caller.username!.trim();
    if (!seen.add(username.toLowerCase())) continue;
    candidates.add(
      LansweeperRequesterCandidate(
        account: LansweeperAccount(
          username: username,
          label: caller.displayName,
        ),
        departmentName: caller.departmentName,
      ),
    );
  }

  for (final department in departments) {
    for (final account in department.accounts) {
      if (!seen.add(account.username.toLowerCase())) continue;
      candidates.add(
        LansweeperRequesterCandidate(
          account: account,
          departmentName: department.departmentName,
        ),
      );
    }
  }

  if (candidates.isEmpty) {
    return const LansweeperRequesterOptions(
      selectedUsername: null,
      candidates: [],
      isChoosable: false,
    );
  }

  // Προεπιλογή: ο καλών της κύριας κλήσης, αλλιώς ο πρώτος με έγκυρη μορφή,
  // αλλιώς ο πρώτος ως έχει (σημασμένος στο UI) — ποτέ σιωπηλός αποκλεισμός.
  final primaryUsername = callers.firstOrNull?.hasUsername ?? false
      ? callers.first.username!.trim()
      : null;
  final firstValid = candidates
      .where(
        (candidate) =>
            diagnoseLansweeperIdentity(candidate.account.username).isValid,
      )
      .firstOrNull;

  return LansweeperRequesterOptions(
    selectedUsername:
        primaryUsername ?? (firstValid ?? candidates.first).account.username,
    candidates: candidates,
    // Με πολλά εμπλεκόμενα πρόσωπα η απόφαση εμφανίζεται ΠΑΝΤΑ· με ένα,
    // μόνο όταν υπάρχουν όντως εναλλακτικές.
    isChoosable: partyCount > 1 || candidates.length > 1,
  );
}
