import '../database/user_repository.dart';
import '../../features/calls/models/call_model.dart';
import 'lansweeper_department_accounts.dart';
import 'lansweeper_requester_resolution.dart';
import 'lookup_service.dart';

/// Ποιος μπαίνει αιτών στο ticket για τις δοσμένες κλήσεις — **η μοναδική
/// υλοποίηση**, κοινή για την προεπισκόπηση της φόρμας και για την υποβολή.
///
/// Η προεπισκόπηση και η αποστολή έλυναν κάποτε το ίδιο ερώτημα με δύο
/// διαφορετικούς τρόπους: η φόρμα έδειχνε λογαριασμό τμήματος, ενώ η αποστολή
/// κοίταζε μόνο το προσωπικό αναγνωριστικό του καλούντα. Με κλήση «Άγνωστου»
/// το ticket έφευγε σιωπηλά χωρίς αιτούντα — δηλαδή η φόρμα υποσχόταν κάτι που
/// δεν συνέβαινε. Ό,τι αλλάξει στην ιεραρχία, αλλάζει εδώ και για τα δύο.
///
/// Η σειρά των [calls] μετράει: πρώτη η κύρια κλήση του ticket.
Future<LansweeperRequesterOptions> resolveLansweeperRequesterForCalls({
  required UserRepository userRepository,
  required LookupService lookup,
  required List<CallModel> calls,
}) async {
  if (calls.isEmpty) {
    return const LansweeperRequesterOptions(
      selectedUsername: null,
      candidates: [],
      isChoosable: false,
    );
  }

  // Οι ΔΙΑΚΡΙΤΟΙ καλούντες, με σειρά πρώτης εμφάνισης. Κλήση χωρίς συνδεδεμένο
  // καλούντα μετρά ως επιπλέον «πρόσωπο»: κάνει τον αιτούντα απόφαση.
  final callers = <LansweeperTicketCaller>[];
  final seenCallerIds = <int>{};
  var hasUnidentifiedCalls = false;
  for (final call in calls) {
    final callerId = call.callerId;
    if (callerId == null) {
      hasUnidentifiedCalls = true;
      continue;
    }
    if (!seenCallerIds.add(callerId)) continue;
    final username = await userRepository.getLansweeperUsernameById(callerId);
    final displayName = (call.callerText ?? '').trim();
    callers.add(
      LansweeperTicketCaller(
        displayName: displayName.isEmpty ? 'Καλών #$callerId' : displayName,
        departmentName: (call.departmentText ?? '').trim(),
        username: username,
      ),
    );
  }
  final partyCount = callers.length + (hasUnidentifiedCalls ? 1 : 0);

  // Τα τμήματα διαβάζονται μόνο όταν η απόφαση τα χρειάζεται: ο μοναδικός
  // καλών με δικό του αναγνωριστικό κερδίζει χωρίς λίστα.
  final departments =
      <({String departmentName, List<LansweeperAccount> accounts})>[];
  final needDepartments =
      partyCount > 1 || !(callers.length == 1 && callers.first.hasUsername);
  if (needDepartments) {
    final seenDepartments = <int>{};
    for (final call in calls) {
      final department = lookup.findDepartmentByName(call.departmentText ?? '');
      final departmentId = department?.id;
      if (department == null || departmentId == null) continue;
      if (!seenDepartments.add(departmentId)) continue;
      final accounts = decodeLansweeperAccounts(department.lansweeperUsernames);
      if (accounts.isEmpty) continue;
      departments.add((
        departmentName: department.name,
        accounts: accounts,
      ));
    }
  }

  return resolveLansweeperRequester(
    callers: callers,
    hasUnidentifiedCalls: hasUnidentifiedCalls,
    departments: departments,
  );
}
