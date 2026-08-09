import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/lookup_service.dart';
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

    return service.scan(
      users: directoryNotifier.allUsersForUi,
      departments: departments,
      equipment: ref
          .read(equipmentDirectoryProvider)
          .allItems
          .map((row) => row.$1)
          .toList(),
      sharedPhonesByDepartmentId: sharedPhones,
    );
  }

  /// Ανοίγει τον διάλογο επεξεργασίας της οντότητας του ευρήματος,
  /// εστιασμένο στο πεδίο που φταίει.
  ///
  /// Χρησιμοποιεί τις ΙΔΙΕΣ διαδρομές με τις καρτέλες του Καταλόγου, ώστε
  /// αποθήκευση, φρουρός κλεισίματος και ιστορικό να συμπεριφέρονται ίδια.
  static Future<void> openEditorFor(
    BuildContext context,
    WidgetRef ref,
    CatalogValidationFinding finding,
  ) async {
    switch (finding.kind) {
      case CatalogEntityKind.user:
        final notifier = ref.read(directoryProvider.notifier);
        final user = notifier.allUsersForUi
            .where((u) => u.id == finding.entityId)
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
            focusedField: finding.focusedField,
          ),
        );

      case CatalogEntityKind.department:
        final notifier = ref.read(departmentDirectoryProvider.notifier);
        final department = ref
            .read(departmentDirectoryProvider)
            .allDepartments
            .where((d) => d.id == finding.entityId)
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
            focusedField: finding.focusedField,
          ),
        );

      case CatalogEntityKind.equipment:
        // Ο κοινός εκκινητής φορτώνει μόνος του τον κατάλογο και βρίσκει
        // και τον κάτοχο — τον ίδιο χρησιμοποιούν ιστορικό και εκκρεμότητες.
        await EquipmentFormLauncher.openById(context, ref, finding.entityId);
    }
  }

  static void _notFound(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
