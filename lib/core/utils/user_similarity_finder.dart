import '../../features/calls/models/user_model.dart';
import 'name_parser.dart';
import 'text_similarity.dart';
import 'user_identity_normalizer.dart';

/// Αποτέλεσμα ομοιότητας με υπάρχουσα εγγραφή καταλόγου.
class UserSimilarityMatch {
  const UserSimilarityMatch({required this.user, required this.score});

  /// Υπάρχουσα εγγραφή του καταλόγου.
  final UserModel user;

  /// Βαθμολογία ομοιότητας (100 = ταυτοπροσωπία).
  final int score;
}

/// Εντοπισμός παρόμοιων / ίδιων χρηστών βάσει ονοματεπωνύμου.
class UserSimilarityFinder {
  UserSimilarityFinder._();

  /// Ταυτοπροσωπία (ίδιο κανονικοποιημένο ονοματεπώνυμο).
  static const int kIdenticalScore = 100;

  /// Ελάχιστο score για πρόταση («Μήπως εννοείτε;»).
  static const int kSuggestionMinScore = 80;

  /// Κάτω από αυτό το μήκος κανονικοποιημένου ονόματος υποψηφίου
  /// επιστρέφονται μόνο τα ταιριάσματα με score 100 (δικλείδα θορύβου).
  static const int kMinLengthForSuggestion = 5;

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

  /// Υπάρχουσες εγγραφές καταλόγου που ταυτίζονται ή μοιάζουν με το δοθέν ονοματεπώνυμο.
  static List<UserSimilarityMatch> findSimilarUsers({
    required Iterable<UserModel> users,
    required String firstName,
    required String lastName,
    int? excludeUserId,
  }) {
    final f = firstName.trim();
    final l = lastName.trim();
    if (f.isEmpty && l.isEmpty) return const [];

    final queryDisplay = displayNameFor(f, l);
    final queryIdentity = UserIdentityNormalizer.identityKeyForPerson(f, l);
    final matches = <UserSimilarityMatch>[];

    for (final u in users) {
      if (u.isDeleted) continue;
      if (excludeUserId != null && u.id == excludeUserId) continue;

      final uf = u.firstName?.trim() ?? '';
      final ul = u.lastName?.trim() ?? '';
      final candidateDisplay = displayNameFor(uf, ul);
      if (candidateDisplay.isEmpty) continue;

      final candidateIdentity = UserIdentityNormalizer.identityKeyForPerson(
        uf,
        ul,
      );
      final int score;
      if (queryIdentity.isNotEmpty &&
          candidateIdentity.isNotEmpty &&
          queryIdentity == candidateIdentity) {
        score = kIdenticalScore;
      } else {
        score = TextSimilarity.score(queryDisplay, candidateDisplay);
      }

      if (score < kSuggestionMinScore) continue;

      final candidateNorm = TextSimilarity.normalize(candidateDisplay);
      if (candidateNorm.length < kMinLengthForSuggestion &&
          score < kIdenticalScore) {
        continue;
      }

      matches.add(UserSimilarityMatch(user: u, score: score));
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches;
  }

  /// Παρόμοιοι χρήστες από το κείμενο του πεδίου καλούντα (μετά parse).
  static List<UserSimilarityMatch> findSimilarUsersFromCallerText({
    required Iterable<UserModel> users,
    required String callerDisplayText,
    int? excludeUserId,
  }) {
    final parsed = parseCallerText(callerDisplayText);
    return findSimilarUsers(
      users: users,
      firstName: parsed.firstName,
      lastName: parsed.lastName,
      excludeUserId: excludeUserId,
    );
  }
}
