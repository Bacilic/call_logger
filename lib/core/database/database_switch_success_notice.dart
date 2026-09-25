import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Μήνυμα πράσινης λωρίδας επιτυχούς αλλαγής διαδρομής βάσης.
String databaseSwitchSuccessMessage(String databasePath) =>
    'Έγινε με επιτυχία η αλλαγή βάσης: $databasePath';

/// Ποια λωρίδα βάσης ζωγραφίζεται στην κορυφή του κελύφους.
enum TopDatabaseBanner {
  none,

  /// Η βάση έπαψε να απαντά — τίποτα από όσα βλέπει ο χειριστής δεν είναι
  /// αξιόπιστο όσο διαρκεί.
  unreachable,

  /// Το αρχείο απαντά, αλλά η σύνδεση της εφαρμογής έχει πεθάνει.
  ///
  /// Χωριστή λωρίδα από την [unreachable] επειδή λέει **άλλο πράγμα στον
  /// άνθρωπο**: εδώ η αναμονή δεν πρόκειται να βοηθήσει, και η μόνη διέξοδος
  /// είναι νέο άνοιγμα της εφαρμογής.
  staleConnection,

  /// Το αρχείο απαντά, αλλά η βάση μένει κλειδωμένη — οι φορτώσεις και οι
  /// αποθηκεύσεις καθυστερούν, και ο χειριστής πρέπει να ξέρει γιατί.
  busy,

  warning,
  success,
}

/// **Η σειρά προτεραιότητας είναι η ουσία αυτής της συνάρτησης.**
///
/// Η χαμένη βάση υπερισχύει των πάντων: όσο δεν απαντά το αρχείο, μια
/// προειδοποίηση για «παλιά βάση» ή μια επιβεβαίωση «άλλαξε η βάση» είναι στην
/// καλύτερη περίπτωση άσχετες και στη χειρότερη παραπλανητικές. Ακολουθεί η
/// νεκρή σύνδεση — εξίσου σοβαρή, αλλά με άλλη διέξοδο. Ακολουθεί η
/// απασχολημένη βάση — εξηγεί κάτι που συμβαίνει ΤΩΡΑ στα χέρια του χειριστή.
/// Μετά έρχεται η κίτρινη προειδοποίηση και τελευταία η πράσινη επιβεβαίωση.
///
/// Ποτέ δύο λωρίδες μαζί.
TopDatabaseBanner topDatabaseBanner({
  required bool showStateNotice,
  required bool hasSwitchSuccess,
  bool isUnreachable = false,
  bool isStaleConnection = false,
  bool isBusy = false,
}) {
  if (isUnreachable) return TopDatabaseBanner.unreachable;
  if (isStaleConnection) return TopDatabaseBanner.staleConnection;
  if (isBusy) return TopDatabaseBanner.busy;
  if (showStateNotice) return TopDatabaseBanner.warning;
  if (hasSwitchSuccess) return TopDatabaseBanner.success;
  return TopDatabaseBanner.none;
}

/// Καθολική κατάσταση πράσινης λωρίδας — όχι autoDispose, ώστε να επιζεί
/// του ξαναχτίσματος μετά από επαναρχικοποίηση εφαρμογής.
final databaseSwitchSuccessNoticeProvider =
    NotifierProvider<DatabaseSwitchSuccessNoticeNotifier, String?>(
      DatabaseSwitchSuccessNoticeNotifier.new,
    );

class DatabaseSwitchSuccessNoticeNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String databasePath) {
    state = databaseSwitchSuccessMessage(databasePath);
  }

  void clear() {
    state = null;
  }
}
