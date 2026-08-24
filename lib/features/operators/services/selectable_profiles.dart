import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/database/operator_presence_repository.dart';
import '../../../core/database/operator_repository.dart';
import '../../../core/models/operator.dart';
import '../../../core/models/operator_presence.dart';
import '../../../core/services/operator_identity.dart';
import '../../../core/services/workstation_operators.dart';
import 'operator_presence_summary.dart';

/// Ό,τι χρειάζεται ο επιλογέας ταυτότητας, διαβασμένο μαζί σε μία στιγμή.
class SelectableProfiles {
  const SelectableProfiles({
    required this.profiles,
    required this.presence,
    this.workstationProfiles = const <Operator>[],
  });

  static const empty = SelectableProfiles(
    profiles: <Operator>[],
    presence: <int, List<OperatorPresenceLine>>{},
  );

  /// Τα ενεργά προφίλ, χωρίς τον ήδη συνδεδεμένο — με πρώτους όσους έχουν
  /// δουλέψει σε αυτόν τον υπολογιστή.
  final List<Operator> profiles;

  /// Γραμμές σύνδεσης ανά προφίλ, έτοιμες προς εμφάνιση.
  final Map<int, List<OperatorPresenceLine>> presence;

  /// Ποιους θυμάται αυτός ο υπολογιστής — **μαζί με τον ήδη συνδεδεμένο**.
  ///
  /// Απαντά στο «γιατί με ρωτά κάθε φορά»: δύο ή περισσότεροι εδώ σημαίνει ότι
  /// η εκκίνηση δεν μπορεί να μαντέψει και ρωτά.
  final List<Operator> workstationProfiles;
}

/// Φορτώνει προφίλ **και** ίχνη σύνδεσης για τον επιλογέα ταυτότητας.
///
/// Κοινή για τα δύο σημεία που ρωτούν «ποιος είσαι;» — την οθόνη εκκίνησης και
/// τον διάλογο «Αλλαγή χρήστη». Δύο αντίγραφα της φόρτωσης θα σήμαιναν ότι η
/// μία οθόνη δείχνει στοιχεία που η άλλη ξεχνά.
///
/// Η [now] δίνεται ρητά ώστε το «συνδεδεμένος τώρα» να κρίνεται με τη στιγμή
/// της ανάγνωσης και όχι με δεύτερο ρολόι μέσα στο `build`.
///
/// Τα [workstationNames] δίνονται μόνο από ελέγχους.
Future<SelectableProfiles> loadSelectableProfiles(
  DatabaseExecutor db, {
  DateTime? now,
  List<String>? workstationNames,
}) async {
  final all = await OperatorRepository(db).getAll();
  final remembered = workstationNames ?? await WorkstationOperators.names();

  // Τα ίχνη σύνδεσης είναι πληροφορία άνεσης: αν λείπει ο πίνακας (βάση από
  // παλαιότερη έκδοση που δεν αναβαθμίστηκε ακόμη) ο επιλογέας δείχνει κανονικά
  // τα προφίλ, απλώς χωρίς γραμμή σύνδεσης.
  var marks = const <OperatorPresence>[];
  try {
    marks = await OperatorPresenceRepository(db).getAll();
  } catch (_) {
    marks = const <OperatorPresence>[];
  }

  return SelectableProfiles(
    profiles: orderProfilesForWorkstation(
      OperatorIdentity.selectableFrom(all),
      remembered,
    ),
    presence: describeOperatorPresenceByOperator(marks, now ?? DateTime.now()),
    workstationProfiles: rememberedWorkstationProfiles(remembered, all),
  );
}
