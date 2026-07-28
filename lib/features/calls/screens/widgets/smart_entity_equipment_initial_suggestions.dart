import '../../../../core/services/lookup_service.dart';
import '../../models/equipment_model.dart';
import '../../models/user_model.dart';
import '../../provider/smart_entity_selector_provider.dart';
import 'smart_entity_selector_equipment_models.dart';

String equipmentDedupeKey(EquipmentModel equipment) {
  final code = equipment.code?.trim() ?? '';
  if (code.isNotEmpty) {
    return code;
  }
  return equipment.displayLabel.trim();
}

List<EquipmentModel> dedupeEquipments(Iterable<EquipmentModel> list) {
  final seen = <String>{};
  final result = <EquipmentModel>[];
  for (final equipment in list) {
    if (seen.add(equipmentDedupeKey(equipment))) {
      result.add(equipment);
    }
  }
  return result;
}

List<EquipmentModel> phoneEquipmentsForSuggestions(
  SmartEntitySelectorState header,
  LookupService? lookupService,
) {
  final phone = header.selectedPhone?.trim() ?? '';
  if (phone.isEmpty || lookupService == null) {
    return const [];
  }
  final users = lookupService.findUsersByPhone(phone);
  final result = <EquipmentModel>[];
  for (final user in users) {
    if (user.id != null) {
      result.addAll(lookupService.findEquipmentsForUser(user.id!));
    }
  }
  return dedupeEquipments(result);
}

List<EquipmentModel> callerEquipmentsForSuggestions(
  SmartEntitySelectorState header,
  LookupService? lookupService,
) {
  if (lookupService == null) {
    return dedupeEquipments(header.equipmentCandidates);
  }
  final callerId = header.selectedCaller?.id;
  if (callerId == null) {
    return dedupeEquipments(header.equipmentCandidates);
  }
  // Ο εξοπλισμός του καλούντα προηγείται, αλλά ΔΕΝ κρύβει τους υποψήφιους που
  // ήδη υπάρχουν στη φόρμα.
  return dedupeEquipments([
    ...lookupService.findEquipmentsForUser(callerId),
    ...header.equipmentCandidates,
  ]);
}

/// Εξοπλισμός του επιλεγμένου τμήματος — **ανεξάρτητη** πηγή προτάσεων.
///
/// Διαβάζεται κατευθείαν από τον κατάλογο και όχι από το
/// `equipmentCandidates`, που σημαίνει αποκλειστικά «δεν αποφασίστηκε ακόμα».
/// Έτσι το overlay εξακολουθεί να δείχνει τα μηχανήματα του τμήματος ακόμη κι
/// όταν ένα από αυτά έχει ήδη συμπληρωθεί αυτόματα.
List<EquipmentModel> departmentEquipmentsForSuggestions(
  SmartEntitySelectorState header,
  LookupService? lookupService,
) {
  final departmentId = header.selectedDepartmentId;
  if (departmentId == null || lookupService == null) {
    return const [];
  }
  return dedupeEquipments(
    lookupService.getAllEquipmentByDepartment(departmentId),
  );
}

/// Ετικέτα πηγής για εξοπλισμό που προέρχεται από καλούντα / υποψήφιους (όχι τηλέφωνο).
String callerEquipmentSourceLabel(
  EquipmentModel equipment,
  LookupService lookupService,
) {
  final equipmentId = equipment.id;
  if (equipmentId != null) {
    final owners = lookupService.findUsersForEquipment(equipmentId);
    if (owners.isNotEmpty) {
      return _formatUserDisplayNames(owners);
    }
  }
  if (equipment.departmentId != null) {
    return 'Κοινόχρηστο';
  }
  return 'Όνομα';
}

String _formatUserDisplayNames(Iterable<UserModel> users) {
  return users
      .map((user) => (user.name ?? user.fullNameWithDepartment).trim())
      .where((name) => name.isNotEmpty)
      .join(', ');
}

/// Αρχικές προτάσεις εξοπλισμού για overlay (τηλέφωνο / καλών / και τα δύο).
List<SmartEntityEquipmentSuggestion> buildInitialEquipmentSuggestions(
  SmartEntitySelectorState header,
  LookupService? lookupService,
) {
  final phoneEquipments = phoneEquipmentsForSuggestions(header, lookupService);
  final callerEquipments = callerEquipmentsForSuggestions(
    header,
    lookupService,
  );
  final phoneKeys = phoneEquipments.map(equipmentDedupeKey).toSet();
  final callerKeys = callerEquipments.map(equipmentDedupeKey).toSet();

  final combined = <SmartEntityEquipmentSuggestion>[];
  final seen = <String>{};

  for (final equipment in phoneEquipments) {
    final key = equipmentDedupeKey(equipment);
    if (callerKeys.contains(key) && seen.add(key)) {
      combined.add(
        SmartEntityEquipmentSuggestion(
          equipment: equipment,
          sourceLabel: 'Τηλ. + Όνομα',
        ),
      );
    }
  }

  for (final equipment in phoneEquipments) {
    final key = equipmentDedupeKey(equipment);
    if (!callerKeys.contains(key) && seen.add(key)) {
      combined.add(
        SmartEntityEquipmentSuggestion(
          equipment: equipment,
          sourceLabel: 'Τηλέφωνο',
        ),
      );
    }
  }

  for (final equipment in callerEquipments) {
    final key = equipmentDedupeKey(equipment);
    if (!phoneKeys.contains(key) && seen.add(key)) {
      final sourceLabel = lookupService != null
          ? callerEquipmentSourceLabel(equipment, lookupService)
          : 'Όνομα';
      combined.add(
        SmartEntityEquipmentSuggestion(
          equipment: equipment,
          sourceLabel: sourceLabel,
        ),
      );
    }
  }

  // Ό,τι δεν ήρθε από τηλέφωνο ή καλούντα αλλά ανήκει στο επιλεγμένο τμήμα.
  for (final equipment in departmentEquipmentsForSuggestions(
    header,
    lookupService,
  )) {
    if (seen.add(equipmentDedupeKey(equipment))) {
      combined.add(
        SmartEntityEquipmentSuggestion(
          equipment: equipment,
          sourceLabel: lookupService != null
              ? callerEquipmentSourceLabel(equipment, lookupService)
              : 'Τμήμα',
        ),
      );
    }
  }

  return combined;
}
