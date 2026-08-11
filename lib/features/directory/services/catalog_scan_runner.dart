import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/audit_entity_stamps.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/services/lookup_service.dart';
import '../../../core/services/settings_service.dart';
import '../../calls/provider/lookup_provider.dart';
import '../models/catalog_validation_finding.dart';
import '../providers/catalog_validation_provider.dart';
import '../providers/department_directory_provider.dart';
import '../providers/directory_provider.dart';
import '../providers/equipment_directory_provider.dart';
import '../screens/widgets/department_form_dialog.dart';
import '../screens/widgets/user_form_dialog.dart';
import 'equipment_form_launcher.dart';

/// Ενορχήστρωση του «Έλεγχος δεδομένων»: φόρτωση καταλόγου, σάρωση με τους
/// ενεργούς κανόνες, και άνοιγμα του σωστού διαλόγου επεξεργασίας ανά εύρημα.
///
/// Ζει έξω από το widget ώστε η οθόνη ρυθμίσεων να δηλώνει μόνο UI.
class CatalogScanRunner {
  const CatalogScanRunner._();

  /// Διαβάζει ΟΛΟΝ τον κατάλογο από τη βάση και τον περνά από τους κανόνες.
  ///
  /// Φορτώνει ρητά τους τρεις καταλόγους: η οθόνη των κανόνων μπορεί να
  /// ανοίξει χωρίς να έχει επισκεφθεί ποτέ ο χρήστης τις καρτέλες τους.
  static Future<List<CatalogValidationFinding>> scan(WidgetRef ref) async {
    final service = await ref.read(catalogValidationServiceProvider.future);
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

    // Κάτοχοι ανά εξοπλισμό (user_equipment) — τους χρειάζεται η
    // διασταύρωση «εξοπλισμός σε υπάλληλο άλλου τμήματος».
    final owners = <int, List<int>>{};
    for (final item in equipment) {
      final id = item.id;
      if (id == null) continue;
      final ownerIds = lookup
          .findUsersForEquipment(id)
          .map((u) => u.id)
          .whereType<int>()
          .toList();
      if (ownerIds.isNotEmpty) owners[id] = ownerIds;
    }

    // Η ταυτότητα του πράκτορα (Ρυθμίσεις API) τροφοδοτεί τις ήπιες υποψίες
    // τομέα· χωρίς αυτήν, απλώς δεν υπάρχουν υποψίες.
    String? agentIdentity;
    try {
      agentIdentity = await SettingsService().remoteLansweeper
          .getLansweeperAgentUsername();
    } catch (_) {}

    final findings = service.scan(
      users: directoryNotifier.allUsersForUi,
      departments: departments,
      equipment: equipment,
      sharedPhonesByDepartmentId: sharedPhones,
      ownerUserIdsByEquipmentId: owners,
      lansweeperAgentIdentity: agentIdentity,
    );

    return _withAuditStamps(findings);
  }

  /// Συμπληρώνει στα chips των διενέξεων τις χρονοσφραγίδες από το
  /// Ιστορικό Εφαρμογής: πρώτη εγγραφή «ΔΗΜΙΟΥΡΓΙΑ…» = δημιουργία,
  /// τελευταία οποιαδήποτε = τελευταία αλλαγή. Οι πίνακες του καταλόγου
  /// δεν κρατούν δικές τους χρονοσφραγίδες — το Ιστορικό είναι η μόνη
  /// πηγή, και εγγραφές χωρίς ίχνος εμφανίζονται τίμια ως «άγνωστες».
  static Future<List<CatalogValidationFinding>> _withAuditStamps(
    List<CatalogValidationFinding> findings,
  ) async {
    final involved = <String, Set<int>>{};
    for (final finding in findings) {
      if (!finding.isConflict) continue;
      for (final record in finding.records) {
        involved
            .putIfAbsent(_auditEntityType(record.kind), () => {})
            .add(record.entityId);
      }
    }
    if (involved.isEmpty) return findings;

    // Το ερώτημα ζει στο core/database — «SQL μόνο στα Repositories».
    final db = await DatabaseHelper.instance.database;
    final stamps = await fetchAuditEntityStamps(db, involved);

    return [
      for (final finding in findings)
        if (!finding.isConflict)
          finding
        else
          finding.withRecords([
            for (final record in finding.records)
              switch (stamps['${_auditEntityType(record.kind)}'
                  '#${record.entityId}']) {
                null => record,
                (final created, final changed) => record.withStamps(
                  createdAt: created,
                  lastChangedAt: changed,
                ),
              },
          ]),
    ];
  }

  /// Το `entity_type` του Ιστορικού για κάθε είδος εγγραφής καταλόγου.
  static String _auditEntityType(CatalogEntityKind kind) {
    return switch (kind) {
      CatalogEntityKind.user => 'user',
      CatalogEntityKind.department => 'department',
      CatalogEntityKind.equipment => 'equipment',
    };
  }

  /// Ανοίγει την καρτέλα μιας εγγραφής ευρήματος, εστιασμένη στο πεδίο
  /// που φταίει.
  static Future<void> openRecord(
    BuildContext context,
    WidgetRef ref,
    CatalogFindingRecord record,
  ) {
    return openEntity(
      context,
      ref,
      kind: record.kind,
      entityId: record.entityId,
      focusedField: record.focusedField,
    );
  }

  /// Ανοίγει την καρτέλα οποιασδήποτε οντότητας του καταλόγου.
  ///
  /// Χρησιμοποιεί τις ΙΔΙΕΣ διαδρομές με τις καρτέλες του Καταλόγου, ώστε
  /// αποθήκευση, φρουρός κλεισίματος και ιστορικό να συμπεριφέρονται ίδια.
  static Future<void> openEntity(
    BuildContext context,
    WidgetRef ref, {
    required CatalogEntityKind kind,
    required int entityId,
    String? focusedField,
  }) async {
    switch (kind) {
      case CatalogEntityKind.user:
        final notifier = ref.read(directoryProvider.notifier);
        final user = notifier.allUsersForUi
            .where((u) => u.id == entityId)
            .firstOrNull;
        if (user == null) {
          _notFound(context, 'Ο υπάλληλος δεν βρέθηκε στον κατάλογο.');
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (_) => UserFormDialog(
            initialUser: user,
            notifier: notifier,
            focusedField: focusedField,
          ),
        );

      case CatalogEntityKind.department:
        final notifier = ref.read(departmentDirectoryProvider.notifier);
        final department = ref
            .read(departmentDirectoryProvider)
            .allDepartments
            .where((d) => d.id == entityId)
            .firstOrNull;
        if (department == null) {
          _notFound(context, 'Το τμήμα δεν βρέθηκε στον κατάλογο.');
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (_) => DepartmentFormDialog(
            initialDepartment: department,
            notifier: notifier,
            focusedField: focusedField,
          ),
        );

      case CatalogEntityKind.equipment:
        // Ο κοινός εκκινητής φορτώνει μόνος του τον κατάλογο και βρίσκει
        // και τον κάτοχο — τον ίδιο χρησιμοποιούν ιστορικό και εκκρεμότητες.
        await EquipmentFormLauncher.openById(context, ref, entityId);
    }
  }

  static void _notFound(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
