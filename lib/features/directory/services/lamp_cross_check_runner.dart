import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/old_database/lamp_cross_check_snapshot.dart';
import '../../../core/database/old_database/lamp_settings_store.dart';
import '../../../core/services/lookup_service.dart';
import '../../calls/provider/lookup_provider.dart';
import '../models/lamp_cross_check_finding.dart';
import '../providers/department_directory_provider.dart';
import '../providers/directory_provider.dart';
import '../providers/equipment_directory_provider.dart';
import '../providers/lamp_cross_check_provider.dart';
import 'lamp_cross_check_service.dart';

/// Τι βγήκε από μια διασταύρωση.
///
/// Το [unavailableReason] δεν είναι σφάλμα προγράμματος: η Λάμπα μπορεί να
/// μην έχει ρυθμιστεί σε αυτό το μηχάνημα, και η οθόνη οφείλει να το πει
/// καθαρά αντί να δείξει «καμία απόκλιση» — που θα ήταν ψέμα.
class LampCrossCheckResult {
  const LampCrossCheckResult({
    required this.findings,
    this.unavailableReason,
  });

  const LampCrossCheckResult.unavailable(String reason)
    : findings = const [],
      unavailableReason = reason;

  final List<LampCrossCheckFinding> findings;
  final String? unavailableReason;

  bool get isAvailable => unavailableReason == null;
}

/// Ενορχήστρωση της διασταύρωσης: φορτώνει τον Κατάλογο, διαβάζει τη Λάμπα
/// και τα δίνει στην καθαρή υπηρεσία σύγκρισης.
///
/// Ζει έξω από το widget ώστε η οθόνη να δηλώνει μόνο διεπαφή.
class LampCrossCheckRunner {
  const LampCrossCheckRunner._();

  static Future<LampCrossCheckResult> run(WidgetRef ref) async {
    final rules = await ref.read(lampCrossCheckRulesProvider.future);
    if (rules.allDisabled) {
      return const LampCrossCheckResult.unavailable(
        'Δεν είναι ενεργός κανένας έλεγχος. Ανάψτε τουλάχιστον έναν παραπάνω.',
      );
    }

    final path = await LampSettingsStore().getReadPath();
    if (path == null || path.trim().isEmpty) {
      return const LampCrossCheckResult.unavailable(
        'Δεν έχει οριστεί βάση Λάμπας σε αυτό το μηχάνημα. '
        'Ορίστε τη στις ρυθμίσεις της Λάμπας.',
      );
    }

    final LampCrossCheckSnapshot snapshot;
    try {
      snapshot = await readLampCrossCheckSnapshot(path);
    } on FileSystemException {
      return LampCrossCheckResult.unavailable(
        'Δεν βρέθηκε η βάση της Λάμπας στη διαδρομή «$path».',
      );
    } catch (error) {
      // Χαλασμένο ή ξένο αρχείο: η αιτία φτάνει ως το μήνυμα, αλλιώς ο
      // χρήστης μένει με ένα «κάτι πήγε στραβά» που δεν λέει τίποτα.
      return LampCrossCheckResult.unavailable(
        'Η βάση της Λάμπας δεν διαβάστηκε: $error',
      );
    }

    // Οι τρεις κατάλογοι φορτώνονται ρητά: η οθόνη μπορεί να ανοίξει χωρίς
    // να έχει επισκεφθεί ποτέ ο χρήστης τις καρτέλες τους.
    await ref.read(lookupServiceProvider.future);
    final directoryNotifier = ref.read(directoryProvider.notifier);
    final departmentNotifier = ref.read(departmentDirectoryProvider.notifier);
    final equipmentNotifier = ref.read(equipmentDirectoryProvider.notifier);
    await directoryNotifier.loadUsers();
    await departmentNotifier.loadDepartments();
    await equipmentNotifier.load();

    final departments = ref.read(departmentDirectoryProvider).allDepartments;
    final lookup = LookupService.instance;
    final sharedPhones = <int, List<String>>{
      for (final department in departments)
        if (department.id != null)
          department.id!: lookup.getDirectPhonesByDepartment(department.id!),
    };

    final equipment = ref
        .read(equipmentDirectoryProvider)
        .allItems
        .map((row) => row.$1)
        .toList();

    final owners = <int, List<int>>{};
    for (final item in equipment) {
      final id = item.id;
      if (id == null) continue;
      final ownerIds = lookup
          .findUsersForEquipment(id)
          .map((user) => user.id)
          .whereType<int>()
          .toList();
      if (ownerIds.isNotEmpty) owners[id] = ownerIds;
    }

    final findings = LampCrossCheckService(rules).compare(
      users: directoryNotifier.allUsersForUi,
      departments: departments,
      equipment: equipment,
      snapshot: snapshot,
      sharedPhonesByDepartmentId: sharedPhones,
      ownerUserIdsByEquipmentId: owners,
    );

    return LampCrossCheckResult(findings: findings);
  }
}
