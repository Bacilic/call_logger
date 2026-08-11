import 'lansweeper_department_accounts.dart';

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
/// 1. Ο ίδιος ο καλών, όταν έχει αναγνωριστικό — δεν ρωτιέται τίποτα.
/// 2. Ο μοναδικός λογαριασμός του τμήματος — μπαίνει αυτόματα, φαίνεται όμως
///    στη φόρμα ώστε να μην είναι κρυφή απόφαση.
/// 3. Ένας από τους πολλούς λογαριασμούς των τμημάτων — προεπιλέγεται ο
///    πρώτος και ο χρήστης μπορεί να τον αλλάξει ή να τον αφαιρέσει.
/// 4. Κανένας — το ticket βγαίνει με τον πράκτορα, όπως πριν από αυτή τη
///    δυνατότητα.
LansweeperRequesterOptions resolveLansweeperRequester({
  required String? callerUsername,
  required List<({String departmentName, List<LansweeperAccount> accounts})>
  departments,
}) {
  final caller = callerUsername?.trim() ?? '';
  if (caller.isNotEmpty) {
    return LansweeperRequesterOptions(
      selectedUsername: caller,
      candidates: const [],
      isChoosable: false,
    );
  }

  final candidates = <LansweeperRequesterCandidate>[];
  final seen = <String>{};
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

  return LansweeperRequesterOptions(
    selectedUsername: candidates.first.account.username,
    candidates: candidates,
    isChoosable: candidates.length > 1,
  );
}
