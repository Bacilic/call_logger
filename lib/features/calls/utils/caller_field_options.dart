import '../../../core/services/lookup_service.dart';
import '../../../core/utils/name_parser.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../models/user_model.dart';

/// Το κείμενο της γραμμής «Άγνωστος» της μικρής λίστας του Καλούντα.
const String kCallerUnknownOption = 'Άγνωστος';

/// Τι είδους γραμμή είναι μια επιλογή της μικρής λίστας του Καλούντα.
enum CallerOverlayRowKind {
  /// Υποψήφιος από την αναζήτηση με τηλέφωνο.
  candidate,

  /// Ο καλών που είναι ήδη επιλεγμένος.
  selected,

  /// «Άγνωστος».
  unknown,
}

/// Μία γραμμή της μικρής λίστας κάτω από το πεδίο Καλούντα.
class CallerOverlayRow {
  const CallerOverlayRow({
    required this.kind,
    required this.label,
    this.user,
    this.isPhoneOwner = false,
  });

  final CallerOverlayRowKind kind;

  /// Ό,τι γράφει η γραμμή — και ό,τι επιλέγει το Enter όταν είναι επισημασμένη.
  final String label;

  /// Ο υπάλληλος της γραμμής· `null` για τον «Άγνωστο».
  final UserModel? user;

  /// Ο υπάλληλος έχει το τηλέφωνο της φόρμας — η γραμμή σημαδεύεται, ώστε
  /// μέσα σε όλο το τμήμα να ξεχωρίζουν όσοι κατέχουν τη γραμμή που καλεί.
  final bool isPhoneOwner;
}

/// Οι γραμμές της μικρής λίστας του Καλούντα, με τη σειρά τους: πρώτα οι
/// υποψήφιοι εκτός του επιλεγμένου, μετά ο επιλεγμένος, και τελευταίος ο
/// «Άγνωστος» όταν το πεδίο είναι άδειο. Οι υποψήφιοι κρατούν τη σειρά που
/// τους έδωσε η φόρμα (κάτοχοι του τηλεφώνου πρώτοι)· το [phone] κρίνει
/// μόνο ποιες γραμμές σημαδεύονται ως κάτοχοι.
///
/// **Μία λίστα για σχέδιο και πληκτρολόγιο.** Κάποτε γραφόταν δύο φορές — μία
/// για ό,τι ζωγραφίζεται και μία για ό,τι διαλέγουν τα βελάκια και το Enter.
/// Αν άλλαζε μόνο η μία, το Enter θα διάλεγε άλλον υπάλληλο από αυτόν που
/// φαινόταν επισημασμένος.
List<CallerOverlayRow> callerOverlayRows({
  required UserModel? selectedCaller,
  required List<UserModel> candidates,
  required bool showUnknownOption,
  String? phone,
}) {
  final selectedName =
      selectedCaller?.name ?? selectedCaller?.fullNameWithDepartment ?? '';
  bool ownsPhone(UserModel user) =>
      phone != null && LookupService.userHasPhone(user, phone);
  return [
    for (final user in candidates)
      if (_isOtherThanSelected(user, selectedName))
        CallerOverlayRow(
          kind: CallerOverlayRowKind.candidate,
          label: user.fullNameWithDepartment,
          user: user,
          isPhoneOwner: ownsPhone(user),
        ),
    if (selectedName.isNotEmpty)
      CallerOverlayRow(
        kind: CallerOverlayRowKind.selected,
        label: selectedName,
        user: selectedCaller,
        isPhoneOwner: selectedCaller != null && ownsPhone(selectedCaller),
      ),
    if (showUnknownOption)
      const CallerOverlayRow(
        kind: CallerOverlayRowKind.unknown,
        label: kCallerUnknownOption,
      ),
  ];
}

bool _isOtherThanSelected(UserModel user, String selectedName) {
  final name = (user.name ?? user.fullNameWithDepartment).trim();
  return name.isNotEmpty && name != selectedName;
}

/// Οι προτάσεις καθώς γράφεις στο πεδίο Καλούντα για το [query].
///
/// **Μία λίστα για σχέδιο και πληκτρολόγιο, με το ίδιο κείμενο.** Η ορατή
/// λίστα και τα βελάκια υπολογίζονταν χωριστά και είχαν ήδη αποκλίνει: με
/// άδειο πεδίο και υποψηφίους από το τηλέφωνο, η ορατή λίστα ήταν κενή ενώ τα
/// βελάκια διάλεγαν αόρατους υπαλλήλους.
///
/// Με υποψηφίους, η αναζήτηση μένει μέσα σε αυτούς — και με άδειο κείμενο δεν
/// προτείνει τίποτα, γιατί τότε τους δείχνει ήδη η μικρή λίστα
/// ([callerOverlayRows]). Χωρίς υποψηφίους, ψάχνει στον κατάλογο με το
/// [searchUsers].
List<String> callerAutocompleteOptions({
  required String query,
  required List<UserModel> candidates,
  required List<UserModel> Function(String query) searchUsers,
}) {
  final q = SearchTextNormalizer.normalizeForSearch(query);
  if (q.isEmpty) return const <String>[];
  final pool = candidates.isNotEmpty ? candidates : searchUsers(query.trim());
  return [
    for (final user in pool)
      if (SearchTextNormalizer.matchesNormalizedQuery(
        user.fullNameWithDepartment,
        q,
      ))
        user.fullNameWithDepartment,
  ];
}

/// Το όνομα που γράφεται στο πεδίο για μια επιλογή: χωρίς τα διακοσμητικά της
/// γραμμής (τμήμα σε παρένθεση, ψευδώνυμο).
String callerSelectionDisplayName(String selection) {
  if (selection == kCallerUnknownOption) return selection;
  return NameParserUtility.stripDisplayDecorations(selection);
}

/// Ποιος υπάλληλος είναι η επιλογή [selection] της λίστας του Καλούντα.
///
/// Πρώτα οι [candidates], με ταύτιση στο πλήρες κείμενο της γραμμής ή στο
/// όνομα. Αλλιώς ο κατάλογος ([searchUsers], `null` = δεν υπάρχει κατάλογος),
/// όπου το ακριβές πλήρες κείμενο της γραμμής προηγείται του σκέτου ονόματος.
/// `null` όταν δεν βρεθεί κανείς.
UserModel? resolveCallerSelection(
  String selection, {
  required List<UserModel> candidates,
  required List<UserModel> Function(String query)? searchUsers,
}) {
  for (final user in candidates) {
    if (user.fullNameWithDepartment == selection || user.name == selection) {
      return user;
    }
  }
  if (searchUsers == null) return null;
  final displayName = callerSelectionDisplayName(selection);
  final matches = searchUsers(displayName).where((user) {
    return user.fullNameWithDepartment == selection || user.name == displayName;
  }).toList();
  if (matches.isEmpty) return null;
  for (final user in matches) {
    if (user.fullNameWithDepartment == selection) return user;
  }
  return matches.first;
}

/// Τι γράφει το πεδίο όσο τα βελάκια περνούν πάνω από μια γραμμή της μικρής
/// λίστας: το όνομα του υπαλλήλου, χωρίς τμήμα.
String callerPreviewText(
  String selection, {
  required List<UserModel> candidates,
  required List<UserModel> Function(String query)? searchUsers,
}) {
  if (selection == kCallerUnknownOption) return selection;
  final user = resolveCallerSelection(
    selection,
    candidates: candidates,
    searchUsers: searchUsers,
  );
  final name = user?.name?.trim() ?? '';
  return name.isNotEmpty ? name : callerSelectionDisplayName(selection);
}
