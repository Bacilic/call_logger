import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Μήνυμα πράσινης λωρίδας επιτυχούς αλλαγής διαδρομής βάσης.
String databaseSwitchSuccessMessage(String databasePath) =>
    'Έγινε με επιτυχία η αλλαγή βάσης: $databasePath';

/// Ποια λωρίδα βάσης ζωγραφίζεται στην κορυφή του κελύφους.
enum TopDatabaseBanner { none, warning, success }

/// Η κίτρινη προειδοποίηση ΥΠΕΡΙΣΧΥΕΙ πάντα της πράσινης επιβεβαίωσης,
/// και οι δύο λωρίδες ΔΕΝ εμφανίζονται ποτέ μαζί.
TopDatabaseBanner topDatabaseBanner({
  required bool showStateNotice,
  required bool hasSwitchSuccess,
}) {
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
