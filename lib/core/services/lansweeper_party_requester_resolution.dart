import '../database/user_repository.dart';
import '../../features/directory/models/department_kind.dart';
import 'lansweeper_department_accounts.dart';
import 'lansweeper_requester_resolution.dart';
import 'lookup_service.dart';

/// Ένα πρόσωπο-και-τμήμα που συμμετέχει σε ένα αίτημα, ό,τι κι αν το γέννησε.
///
/// Η ιεραρχία του αιτούντα δεν χρειάζεται να ξέρει αν πίσω της στέκεται κλήση
/// ή εκκρεμότητα: χρειάζεται **ποιος** και **από ποιο τμήμα**. Κρατώντας μόνο
/// αυτά, η ίδια απόφαση εξυπηρετεί κάθε πύλη που θα ανοίξει αύριο, αντί να
/// αντιγράφεται μία φορά ανά οντότητα.
class LansweeperRequesterParty {
  const LansweeperRequesterParty({
    this.personId,
    this.personLabel = '',
    this.departmentText = '',
  });

  /// Η καρτέλα του Καταλόγου· `null` = το πρόσωπο έμεινε άγνωστο.
  final int? personId;

  /// Πώς θα φανεί στον επιλογέα. Το φτιάχνει ο καλών, ώστε κάθε πύλη να λέει
  /// τη δική της γλώσσα («Καλών #42» για κλήση) χωρίς ο πυρήνας να μαντεύει.
  final String personLabel;

  /// Το τμήμα όπως γράφτηκε — το ίδιο κείμενο που ψάχνει ο Κατάλογος.
  final String departmentText;
}

/// Ποιος μπαίνει αιτών στο αίτημα για τα δοσμένα [parties] — **η μοναδική
/// υλοποίηση της ιεραρχίας**, κοινή για την προεπισκόπηση και την υποβολή.
///
/// Η προεπισκόπηση και η αποστολή έλυναν κάποτε το ίδιο ερώτημα με δύο
/// διαφορετικούς τρόπους: η φόρμα έδειχνε λογαριασμό τμήματος, ενώ η αποστολή
/// κοίταζε μόνο το προσωπικό αναγνωριστικό. Με «Άγνωστο» πρόσωπο το αίτημα
/// έφευγε σιωπηλά χωρίς αιτούντα — δηλαδή η φόρμα υποσχόταν κάτι που δεν
/// συνέβαινε. Ό,τι αλλάξει στην ιεραρχία, αλλάζει εδώ και ισχύει παντού.
///
/// Η σειρά των [parties] μετράει: πρώτο το πρόσωπο της κύριας εγγραφής.
Future<LansweeperRequesterOptions> resolveLansweeperRequesterForParties({
  required UserRepository userRepository,
  required LookupService lookup,
  required List<LansweeperRequesterParty> parties,
}) async {
  if (parties.isEmpty) {
    return const LansweeperRequesterOptions(
      selectedUsername: null,
      candidates: [],
      isChoosable: false,
    );
  }

  // Τα ΔΙΑΚΡΙΤΑ πρόσωπα, με σειρά πρώτης εμφάνισης. Εγγραφή χωρίς συνδεδεμένο
  // πρόσωπο μετρά ως επιπλέον «πρόσωπο»: κάνει τον αιτούντα απόφαση.
  final callers = <LansweeperTicketCaller>[];
  final seenPersonIds = <int>{};
  var hasUnidentifiedParties = false;
  for (final party in parties) {
    final personId = party.personId;
    if (personId == null) {
      hasUnidentifiedParties = true;
      continue;
    }
    if (!seenPersonIds.add(personId)) continue;
    // Ο ΙΔΙΟΣ κανόνας με τα τμήματα παρακάτω, στο ίδιο σημείο κρίσης:
    // εξωτερική εταιρεία ή μονάδα δεν έχει λογαριασμό Lansweeper, ούτε η
    // ίδια ούτε οι άνθρωποί της. Χωρίς αυτόν τον έλεγχο ο συνεργάτης
    // περνούσε από τον έναν δρόμο ενώ αποκλειόταν από τον άλλον.
    final personDepartment = lookup.findDepartmentByName(party.departmentText);
    final personKind = personDepartment?.kind ?? DepartmentKind.hospital;
    final username = personKind.participatesInLansweeper
        ? await userRepository.getLansweeperUsernameById(personId)
        : null;
    callers.add(
      LansweeperTicketCaller(
        displayName: party.personLabel,
        departmentName: party.departmentText.trim(),
        username: username,
      ),
    );
  }
  final partyCount = callers.length + (hasUnidentifiedParties ? 1 : 0);

  // Τα τμήματα διαβάζονται μόνο όταν η απόφαση τα χρειάζεται: το μοναδικό
  // πρόσωπο με δικό του αναγνωριστικό κερδίζει χωρίς λίστα.
  final departments =
      <({String departmentName, List<LansweeperAccount> accounts})>[];
  // Οι συνάδελφοι του τμήματος: μόνο όταν κάποια εγγραφή έμεινε σε «Άγνωστο».
  // Με γνωστό πρόσωπο ο χρήστης ξέρει ήδη ποιος ζήτησε, οπότε μια λίστα
  // συναδέλφων εκεί θα ήταν ευκαιρία για λάθος και όχι βοήθεια.
  final colleagues =
      <({String departmentName, List<LansweeperAccount> accounts})>[];
  final needDepartments =
      partyCount > 1 || !(callers.length == 1 && callers.first.hasUsername);
  if (needDepartments) {
    final seenDepartments = <int>{};
    for (final party in parties) {
      final department = lookup.findDepartmentByName(party.departmentText);
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

      if (!hasUnidentifiedParties) continue;
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
    hasUnidentifiedCalls: hasUnidentifiedParties,
    departments: departments,
    departmentColleagues: colleagues,
  );
}
