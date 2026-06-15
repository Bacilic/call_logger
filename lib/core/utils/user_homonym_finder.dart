import '../../features/calls/models/user_model.dart';
import 'name_parser.dart';
import 'user_identity_normalizer.dart';

/// Τρόπος σύγκρισης ονοματεπώνυμου για έλεγχο συνωνυμίας.
enum UserHomonymMatchMode {
  /// Και όνομα και επώνυμο συμπληρωμένα — πλήρες κλειδί ταυτότητας.
  fullName,

  /// Μόνο όνομα (μία λέξη στο πεδίο καλούντα).
  firstNameOnly,

  /// Μόνο επώνυμο (σπάνιο στο UI κλήσεων· υποστηρίζεται για πληρότητα).
  lastNameOnly,
}

/// Εντοπισμός συνωνυμίας χρήστη: ίδιο κανονικοποιημένο όνομα, επώνυμο ή και τα δύο.
class UserHomonymFinder {
  UserHomonymFinder._();

  /// Εμφανιζόμενο ονοματεπώνυμο από ξεχωριστά πεδία.
  static String displayNameFor(String? firstName, String? lastName) {
    final f = (firstName ?? '').trim();
    final l = (lastName ?? '').trim();
    if (f.isEmpty && l.isEmpty) return '';
    if (f.isEmpty) return l;
    if (l.isEmpty) return f;
    return '$f $l';
  }

  /// Από ρητό κείμενο καλούντα (πεδίο κλήσεων) → parsed όνομα/επώνυμο.
  static ({String firstName, String lastName}) parseCallerText(
    String callerDisplayText,
  ) {
    final stripped = NameParserUtility.stripParentheticalSuffix(
      callerDisplayText.trim(),
    );
    return NameParserUtility.parse(stripped);
  }

  static UserHomonymMatchMode _matchMode(String firstName, String lastName) {
    final f = firstName.trim();
    final l = lastName.trim();
    if (f.isNotEmpty && l.isNotEmpty) return UserHomonymMatchMode.fullName;
    if (f.isNotEmpty) return UserHomonymMatchMode.firstNameOnly;
    return UserHomonymMatchMode.lastNameOnly;
  }

  static String _candidateKey(
    UserHomonymMatchMode mode,
    String firstName,
    String lastName,
  ) {
    return switch (mode) {
      UserHomonymMatchMode.fullName =>
        UserIdentityNormalizer.identityKeyForPerson(firstName, lastName),
      UserHomonymMatchMode.firstNameOnly =>
        UserIdentityNormalizer.firstNameKey(firstName),
      UserHomonymMatchMode.lastNameOnly =>
        UserIdentityNormalizer.lastNameKey(lastName),
    };
  }

  static bool _userMatches(
    UserHomonymMatchMode mode,
    UserModel user,
    String candidateKey,
  ) {
    if (candidateKey.isEmpty) return false;
    final uf = user.firstName?.trim() ?? '';
    final ul = user.lastName?.trim() ?? '';
    final otherKey = switch (mode) {
      UserHomonymMatchMode.fullName =>
        UserIdentityNormalizer.identityKeyForPerson(uf, ul),
      UserHomonymMatchMode.firstNameOnly =>
        UserIdentityNormalizer.firstNameKey(uf),
      UserHomonymMatchMode.lastNameOnly =>
        UserIdentityNormalizer.lastNameKey(ul),
    };
    return otherKey.isNotEmpty && otherKey == candidateKey;
  }

  /// Πρώτος ενεργός χρήστης με συνωνυμία (όνομα μόνο / επώνυμο μόνο / πλήρες όνομα).
  static UserModel? findHomonymUser({
    required Iterable<UserModel> users,
    required String firstName,
    required String lastName,
    int? excludeUserId,
  }) {
    final f = firstName.trim();
    final l = lastName.trim();
    if (f.isEmpty && l.isEmpty) return null;

    final mode = _matchMode(f, l);
    final candidateKey = _candidateKey(mode, f, l);
    if (candidateKey.isEmpty) return null;

    for (final u in users) {
      if (u.isDeleted) continue;
      if (excludeUserId != null && u.id == excludeUserId) continue;
      if (_userMatches(mode, u, candidateKey)) return u;
    }
    return null;
  }

  /// Συνωνυμία από το κείμενο του πεδίου καλούντα (μετά parse).
  static UserModel? findHomonymFromCallerText({
    required Iterable<UserModel> users,
    required String callerDisplayText,
    int? excludeUserId,
  }) {
    final parsed = parseCallerText(callerDisplayText);
    return findHomonymUser(
      users: users,
      firstName: parsed.firstName,
      lastName: parsed.lastName,
      excludeUserId: excludeUserId,
    );
  }
}
