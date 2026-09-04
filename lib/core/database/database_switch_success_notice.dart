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

  warning,
  success,
}

/// **Η σειρά προτεραιότητας είναι η ουσία αυτής της συνάρτησης.**
///
/// Η χαμένη βάση υπερισχύει των πάντων: όσο δεν απαντά το αρχείο, μια
/// προειδοποίηση για «παλιά βάση» ή μια επιβεβαίωση «άλλαξε η βάση» είναι στην
/// καλύτερη περίπτωση άσχετες και στη χειρότερη παραπλανητικές. Μετά έρχεται η
/// κίτρινη προειδοποίηση και τελευταία η πράσινη επιβεβαίωση.
///
/// Ποτέ δύο λωρίδες μαζί.
TopDatabaseBanner topDatabaseBanner({
  required bool showStateNotice,
  required bool hasSwitchSuccess,
  bool isUnreachable = false,
}) {
  if (isUnreachable) return TopDatabaseBanner.unreachable;
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
