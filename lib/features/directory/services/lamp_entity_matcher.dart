import '../../../core/database/old_database/lamp_cross_check_snapshot.dart';
import '../../../core/database/old_database/lamp_owner_name_similarity.dart';
import '../../../core/utils/text_similarity.dart';
import '../../calls/models/user_model.dart';
import '../models/department_model.dart';

/// Πώς βρέθηκε (ή δεν βρέθηκε) η αντίστοιχη εγγραφή στη Λάμπα.
enum LampMatchOutcome {
  /// Ταιριάζει γράμμα προς γράμμα μετά την κανονικοποίηση.
  exact,

  /// Ταιριάζει ένας μόνο υποψήφιος, με μικρή διαφορά στη γραφή.
  spelling,

  /// Ταιριάζουν δύο ή περισσότεροι και κανένας ακριβώς.
  ambiguous,

  /// Κανένας υποψήφιος.
  missing,
}

/// Η αντιστοιχία ενός υπαλλήλου του Καταλόγου με τη Λάμπα.
class LampUserMatch {
  const LampUserMatch({
    required this.outcome,
    this.owner,
    this.candidates = const [],
    this.note = '',
  });

  final LampMatchOutcome outcome;

  /// Ο ιδιοκτήτης της Λάμπας, όταν η ταύτιση είναι βέβαιη.
  final LampOwnerRecord? owner;

  /// Οι υποψήφιοι, όταν είναι περισσότεροι από ένας.
  final List<LampOwnerRecord> candidates;

  /// Τι διαφέρει, σε ανθρώπινη γλώσσα.
  final String note;

  /// Αληθές όταν η σύγκριση σχέσεων (τμήμα, τηλέφωνα) έχει νόημα: ξέρουμε
  /// ποιον άνθρωπο κοιτάμε.
  bool get isResolved => owner != null;
}

/// Η αντιστοιχία ενός τμήματος του Καταλόγου με τα γραφεία της Λάμπας.
///
/// Κρατά **λίστα** γραφείων: στη Λάμπα το ίδιο όνομα εμφανίζεται συχνά σε
/// πολλά γραφεία του ίδιου φορέα, και για τον Κατάλογο είναι όλα το ίδιο
/// τμήμα. Τα τηλέφωνά τους συγκρίνονται μαζί.
class LampDepartmentMatch {
  const LampDepartmentMatch({
    required this.outcome,
    this.offices = const [],
    this.note = '',
  });

  final LampMatchOutcome outcome;
  final List<LampOfficeRecord> offices;
  final String note;

  bool get isResolved => offices.isNotEmpty;

  /// Πώς λέγεται το τμήμα στη Λάμπα, όταν βρέθηκε.
  String get lampName => offices.isEmpty ? '' : offices.first.displayName;

  /// Όλα τα τηλέφωνα των αντίστοιχων γραφείων.
  Set<String> get phones => {
    for (final office in offices) ...office.phones,
  };
}

/// Πόσο επιτρέπεται να διαφέρει η ονομασία τμήματος για να θεωρηθεί η ίδια.
const int kLampDepartmentNameTolerance = 2;

/// Κάτω από αυτό το μήκος η ανοχή δεν είναι ασφαλής: σε σύντομες ονομασίες
/// δύο γράμματα διαφορά είναι συνήθως άλλο τμήμα, όχι τυπογραφικό λάθος.
const int kLampDepartmentMinLengthForTolerance = 6;

/// Αποφασίζει **μία φορά** ποια εγγραφή της Λάμπας αντιστοιχεί σε κάθε
/// εγγραφή του Καταλόγου.
///
/// **Το συμβόλαιο:** όλοι οι έλεγχοι της διασταύρωσης πατούν σε αυτή τη μία
/// απόφαση. Αν κάθε έλεγχος ταύτιζε μόνος του, η οθόνη θα έλεγε «δεν βρέθηκε»
/// στη μια γραμμή και θα σύγκρινε τμήματα του ίδιου ανθρώπου στην επόμενη.
class LampEntityMatcher {
  const LampEntityMatcher._();

  /// Αντιστοιχία για κάθε υπάλληλο με ταυτότητα, με κλειδί το `users.id`.
  static Map<int, LampUserMatch> matchUsers(
    List<UserModel> users,
    LampCrossCheckSnapshot snapshot,
  ) {
    // Ευρετήρια στα ΑΚΡΙΒΗ ονόματα: ο κανόνας ομοιότητας απαιτεί ούτως ή
    // άλλως το ένα από τα δύο ονόματα να ταιριάζει απόλυτα, οπότε αυτά τα
    // δύο ευρετήρια δίνουν όλους τους δυνατούς υποψηφίους — χωρίς να
    // συγκριθεί ο καθένας με τον καθένα.
    final byLastName = <String, List<LampOwnerRecord>>{};
    final byFirstName = <String, List<LampOwnerRecord>>{};
    for (final owner in snapshot.owners.values) {
      byLastName
          .putIfAbsent(TextSimilarity.normalize(owner.lastName), () => [])
          .add(owner);
      byFirstName
          .putIfAbsent(TextSimilarity.normalize(owner.firstName), () => [])
          .add(owner);
    }

    final result = <int, LampUserMatch>{};
    for (final user in users) {
      final id = user.id;
      if (id == null) continue;
      result[id] = _matchOneUser(user, byLastName, byFirstName);
    }
    return result;
  }

  static LampUserMatch _matchOneUser(
    UserModel user,
    Map<String, List<LampOwnerRecord>> byLastName,
    Map<String, List<LampOwnerRecord>> byFirstName,
  ) {
    final last = TextSimilarity.normalize(user.lastName ?? '');
    final first = TextSimilarity.normalize(user.firstName ?? '');
    if (last.isEmpty && first.isEmpty) {
      return const LampUserMatch(outcome: LampMatchOutcome.missing);
    }

    final pool = <int, LampOwnerRecord>{
      for (final owner in byLastName[last] ?? const <LampOwnerRecord>[])
        owner.id: owner,
      for (final owner in byFirstName[first] ?? const <LampOwnerRecord>[])
        owner.id: owner,
    };

    final exact = <LampOwnerRecord>[];
    final close = <(LampOwnerRecord, LampOwnerNameDeviation)>[];
    for (final owner in pool.values) {
      final deviation = lampOwnerNameDeviation(
        candidateLastName: user.lastName,
        candidateFirstName: user.firstName,
        ownerLastName: owner.lastName,
        ownerFirstName: owner.firstName,
      );
      if (deviation == null) continue;
      if (deviation.isExact) {
        exact.add(owner);
      } else {
        close.add((owner, deviation));
      }
    }

    if (exact.length == 1) {
      return LampUserMatch(
        outcome: LampMatchOutcome.exact,
        owner: exact.first,
      );
    }
    if (exact.length > 1) {
      return LampUserMatch(
        outcome: LampMatchOutcome.ambiguous,
        candidates: exact,
        note: 'Το ίδιο ονοματεπώνυμο υπάρχει ${exact.length} φορές στη Λάμπα',
      );
    }
    if (close.length == 1) {
      final (owner, deviation) = close.first;
      return LampUserMatch(
        outcome: LampMatchOutcome.spelling,
        owner: owner,
        note: _capitalize(deviation.description),
      );
    }
    if (close.length > 1) {
      return LampUserMatch(
        outcome: LampMatchOutcome.ambiguous,
        candidates: [for (final entry in close) entry.$1],
        note: 'Μοιάζει με ${close.length} ανθρώπους της Λάμπας',
      );
    }
    return const LampUserMatch(outcome: LampMatchOutcome.missing);
  }

  /// Αντιστοιχία για κάθε τμήμα με ταυτότητα, με κλειδί το `departments.id`.
  static Map<int, LampDepartmentMatch> matchDepartments(
    List<DepartmentModel> departments,
    LampCrossCheckSnapshot snapshot,
  ) {
    // Το ίδιο γραφείο μπορεί να μπει και με τα δύο ονόματά του: η ονομασία
    // του γραφείου είναι η πρώτη επιλογή, ο ανώτερος φορέας η δεύτερη.
    final byName = <String, List<LampOfficeRecord>>{};
    for (final office in snapshot.offices.values) {
      for (final name in [office.name, office.departmentName]) {
        final key = TextSimilarity.normalize(name);
        if (key.isEmpty) continue;
        final bucket = byName.putIfAbsent(key, () => []);
        if (!bucket.contains(office)) bucket.add(office);
      }
    }

    final result = <int, LampDepartmentMatch>{};
    for (final department in departments) {
      final id = department.id;
      if (id == null) continue;
      result[id] = _matchOneDepartment(department.name, byName);
    }
    return result;
  }

  static LampDepartmentMatch _matchOneDepartment(
    String name,
    Map<String, List<LampOfficeRecord>> byName,
  ) {
    final key = TextSimilarity.normalize(name);
    if (key.isEmpty) {
      return const LampDepartmentMatch(outcome: LampMatchOutcome.missing);
    }

    final exact = byName[key];
    if (exact != null && exact.isNotEmpty) {
      return LampDepartmentMatch(
        outcome: LampMatchOutcome.exact,
        offices: exact,
      );
    }

    final close = <String, List<LampOfficeRecord>>{};
    for (final entry in byName.entries) {
      final shorter = entry.key.length < key.length ? entry.key.length : key.length;
      if (shorter < kLampDepartmentMinLengthForTolerance) continue;
      final distance = TextSimilarity.levenshtein(key, entry.key);
      if (distance > kLampDepartmentNameTolerance) continue;
      close[entry.key] = entry.value;
    }

    if (close.length == 1) {
      final offices = close.values.first;
      return LampDepartmentMatch(
        outcome: LampMatchOutcome.spelling,
        offices: offices,
        note: 'Η ονομασία διαφέρει σε '
            '${_letters(TextSimilarity.levenshtein(key, close.keys.first))}',
      );
    }
    if (close.length > 1) {
      return LampDepartmentMatch(
        outcome: LampMatchOutcome.ambiguous,
        note: 'Μοιάζει με ${close.length} γραφεία της Λάμπας',
      );
    }
    return const LampDepartmentMatch(outcome: LampMatchOutcome.missing);
  }

  static String _letters(int count) =>
      count == 1 ? '1 γράμμα' : '$count γράμματα';

  static String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}
