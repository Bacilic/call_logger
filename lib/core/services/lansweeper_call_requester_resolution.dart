import '../database/user_repository.dart';
import '../../features/calls/models/call_model.dart';
import '../../features/directory/models/department_kind.dart';
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
    // Ο ΙΔΙΟΣ κανόνας με τα τμήματα παρακάτω, στο ίδιο σημείο κρίσης:
    // εξωτερική εταιρεία ή μονάδα δεν έχει λογαριασμό Lansweeper, ούτε η
    // ίδια ούτε οι άνθρωποί της. Χωρίς αυτόν τον έλεγχο ο συνεργάτης
    // περνούσε από τον έναν δρόμο ενώ αποκλειόταν από τον άλλον.
    final callerDepartment = lookup.findDepartmentByName(
      call.departmentText ?? '',
    );
    final callerKind = callerDepartment?.kind ?? DepartmentKind.hospital;
    final username = callerKind.participatesInLansweeper
        ? await userRepository.getLansweeperUsernameById(callerId)
        : null;
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
  // Οι συνάδελφοι του τμήματος: μόνο όταν κάποια κλήση έμεινε σε «Άγνωστο».
  // Με γνωστό καλούντα ο χρήστης ξέρει ήδη ποιος τηλεφώνησε, οπότε μια λίστα
  // συναδέλφων εκεί θα ήταν ευκαιρία για λάθος και όχι βοήθεια.
  final colleagues =
      <({String departmentName, List<LansweeperAccount> accounts})>[];
  final needDepartments =
      partyCount > 1 || !(callers.length == 1 && callers.first.hasUsername);
  if (needDepartments) {
    final seenDepartments = <int>{};
    for (final call in calls) {
      final department = lookup.findDepartmentByName(call.departmentText ?? '');
      final departmentId = department?.id;
      if (department == null || departmentId == null) continue;
      // Εξωτερική εταιρεία ή μονάδα δεν έχει λογαριασμό Lansweeper — ούτε η
      // ίδια ούτε οι άνθρωποί της. Αν έμπαινε στη λίστα, ο επιλογέας αιτούντα
      // θα πρότεινε κάποιον που το Lansweeper δεν αναγνωρίζει.
      if (!department.kind.participatesInLansweeper) continue;
      if (!seenDepartments.add(departmentId)) continue;

      final accounts = decodeLansweeperAccounts(department.lansweeperUsernames);
      if (accounts.isNotEmpty) {
        departments.add((departmentName: department.name, accounts: accounts));
      }

      if (!hasUnidentifiedCalls) continue;
      final members = await userRepository.getLansweeperUsersByDepartmentId(
        departmentId,
      );
      if (members.isEmpty) continue;
      colleagues.add((
        departmentName: department.name,
        accounts: [
          for (final member in members)
            LansweeperAccount(username: member.username, label: member.name),
        ],
      ));
    }
  }

  return resolveLansweeperRequester(
    callers: callers,
    hasUnidentifiedCalls: hasUnidentifiedCalls,
    departments: departments,
    departmentColleagues: colleagues,
  );
}
