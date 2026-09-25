import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/database/operator_repository.dart';
import '../../../core/models/operator.dart';
import '../../../core/services/operator_identity.dart';
import '../../../core/services/operator_presence_heartbeat.dart';
import '../../../core/services/workstation_operators.dart';
import 'operator_presence_summary.dart';
import 'presence_read.dart';
import '../../../core/services/profile_availability.dart';

/// Ό,τι χρειάζεται ο επιλογέας ταυτότητας, διαβασμένο μαζί σε μία στιγμή.
class SelectableProfiles {
  const SelectableProfiles({
    required this.profiles,
    required this.presence,
    this.availability = const <int, ProfileAvailability>{},
    this.workstationProfiles = const <Operator>[],
    this.presenceUnavailable = false,
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

  /// Ποια προφίλ κρατά αυτή τη στιγμή **άλλο** ανοιχτό αντίγραφο της εφαρμογής.
  final Map<int, ProfileAvailability> availability;

  /// Ποιους θυμάται αυτός ο υπολογιστής — **μαζί με τον ήδη συνδεδεμένο**.
  ///
  /// Απαντά στο «γιατί με ρωτά κάθε φορά»: δύο ή περισσότεροι εδώ σημαίνει ότι
  /// η εκκίνηση δεν μπορεί να μαντέψει και ρωτά.
  final List<Operator> workstationProfiles;

  /// Η ανάγνωση των ιχνών απέτυχε — άρα **κανένα κλείδωμα δεν είναι γνωστό**.
  ///
  /// Η άγνοια πέφτει στην πλευρά που δεν εμποδίζει: τα προφίλ προσφέρονται
  /// κανονικά, αλλά η οθόνη το λέει αντί να παριστάνει ότι ξέρει.
  final bool presenceUnavailable;
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
/// Τα [workstationNames], το [windowsAccount] και το [instanceId] δίνονται μόνο
/// από ελέγχους.
Future<SelectableProfiles> loadSelectableProfiles(
  DatabaseExecutor db, {
  DateTime? now,
  List<String>? workstationNames,
  String? windowsAccount,
  String? instanceId,
}) async {
  final all = await OperatorRepository(db).getAll();
  final remembered = workstationNames ?? await WorkstationOperators.names();

  final read = await readOperatorPresence(db);
  final at = now ?? DateTime.now();
  final offered = orderProfilesForWorkstation(
    OperatorIdentity.selectableFrom(all),
    remembered,
    windowsAccount: windowsAccount ?? OperatorIdentity.currentWindowsAccount,
  );

  return SelectableProfiles(
    profiles: offered,
    presence: describeOperatorPresenceByOperator(read.marks, at),
    availability: profileAvailability(
      profiles: offered,
      marks: read.marks,
      now: at,
      myInstance: instanceId ?? OperatorPresenceHeartbeat.instanceId,
    ),
    workstationProfiles: rememberedWorkstationProfiles(remembered, all),
    presenceUnavailable: read.unavailable,
  );
}
