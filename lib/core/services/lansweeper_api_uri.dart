/// Συναρμολόγηση της διεύθυνσης κλήσης του Lansweeper Ticket API.
///
/// Το κλειδί ταξιδεύει ΜΕΣΑ στη διεύθυνση, ως παράμετρος `key` — έτσι το ορίζει
/// το API της Lansweeper, δεν υπάρχει εναλλακτική με κεφαλίδα. Γι' αυτό η
/// συναρμολόγηση ζει σε ΕΝΑ σημείο: αν κάποτε το κλειδί πάψει να μπαίνει εκεί,
/// αλλάζει μόνο αυτό το αρχείο και κανένας καλών δεν μπορεί να το ξεχάσει.
library;

/// Τι εμποδίζει την κλήση — `null` σημαίνει ότι η διεύθυνση χτίστηκε.
enum LansweeperApiUriProblem {
  /// Δεν δόθηκε διεύθυνση API.
  missingUrl,

  /// Δεν δόθηκε κλειδί API.
  missingKey,

  /// Η διεύθυνση δεν έχει σχήμα ή διακομιστή.
  invalidUrl,
}

/// Η διεύθυνση, ή ο λόγος που δεν χτίστηκε.
///
/// Ο καλών μεταφράζει το [problem] στο δικό του λεξιλόγιο: η αποστολή πετάει
/// εξαίρεση («Δεν έχει οριστεί…», γιατί μιλά για ρύθμιση της βάσης), ο έλεγχος
/// ρυθμίσεων επιστρέφει μήνυμα οθόνης («Συμπληρώστε…», γιατί μιλά για πεδίο).
class LansweeperApiUriResult {
  const LansweeperApiUriResult.built(Uri this.uri) : problem = null;
  const LansweeperApiUriResult.blocked(LansweeperApiUriProblem this.problem)
    : uri = null;

  final Uri? uri;
  final LansweeperApiUriProblem? problem;
}

/// Χτίζει τη διεύθυνση για το [action], με το κλειδί και τυχόν [extraQueryParams].
///
/// Οι παράμετροι που υπάρχουν ήδη στη [apiUrl] διατηρούνται· το `action` και το
/// `key` τις επικαλύπτουν, και τα [extraQueryParams] επικαλύπτουν τα πάντα.
LansweeperApiUriResult buildLansweeperApiActionUri({
  required String apiUrl,
  required String apiKey,
  required String action,
  Map<String, String> extraQueryParams = const {},
}) {
  final url = apiUrl.trim();
  final key = apiKey.trim();
  if (url.isEmpty) {
    return const LansweeperApiUriResult.blocked(
      LansweeperApiUriProblem.missingUrl,
    );
  }
  if (key.isEmpty) {
    return const LansweeperApiUriResult.blocked(
      LansweeperApiUriProblem.missingKey,
    );
  }

  final baseUri = Uri.tryParse(url);
  if (baseUri == null || !baseUri.hasScheme || baseUri.host.isEmpty) {
    return const LansweeperApiUriResult.blocked(
      LansweeperApiUriProblem.invalidUrl,
    );
  }

  return LansweeperApiUriResult.built(
    baseUri.replace(
      queryParameters: <String, String>{
        ...baseUri.queryParameters,
        'action': action,
        'key': key,
        ...extraQueryParams,
      },
    ),
  );
}
