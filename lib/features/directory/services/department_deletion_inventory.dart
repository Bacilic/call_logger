import '../../../core/services/lookup_service.dart';

/// Απογραφή εξαρτημάτων τμήματος πριν από διαγραφή (καθαρή λογική, χωρίς UI).
class DepartmentDeletionInventory {
  const DepartmentDeletionInventory({
    required this.departmentName,
    required this.employeeNames,
    required this.employeeOwnedPhoneCount,
    required this.employeeOwnedEquipmentCount,
    required this.sharedPhones,
    required this.sharedEquipmentCodes,
  });

  final String departmentName;
  final List<String> employeeNames;
  final int employeeOwnedPhoneCount;
  final int employeeOwnedEquipmentCount;
  final List<String> sharedPhones;
  final List<String> sharedEquipmentCodes;

  bool get hasEmployees => employeeNames.isNotEmpty;

  bool get hasSharedAssets =>
      sharedPhones.isNotEmpty || sharedEquipmentCodes.isNotEmpty;

  /// True μόνο όταν δεν υπάρχει κανένα εξάρτημα.
  bool get isEmpty => !hasEmployees && !hasSharedAssets;

  /// Ελληνικές γραμμές περίληψης· παραλείπει μηδενικά πλήθη.
  List<String> buildSummaryLines() {
    final lines = <String>[];

    final employeeCount = employeeNames.length;
    if (employeeCount > 0) {
      final noun = employeeCount == 1 ? 'υπάλληλος' : 'υπάλληλοι';
      var line = '$employeeCount $noun';
      if (employeeOwnedPhoneCount + employeeOwnedEquipmentCount > 0) {
        line +=
            ' — ο εξοπλισμός και τα τηλέφωνά τους θα τους ακολουθήσουν αν μεταφερθούν';
      }
      lines.add(line);
    }

    final phoneCount = sharedPhones.length;
    if (phoneCount > 0) {
      lines.add(
        phoneCount == 1
            ? '1 κοινόχρηστο τηλέφωνο'
            : '$phoneCount κοινόχρηστα τηλέφωνα',
      );
    }

    final equipmentCount = sharedEquipmentCodes.length;
    if (equipmentCount > 0) {
      lines.add(
        equipmentCount == 1
            ? '1 κοινόχρηστος εξοπλισμός'
            : '$equipmentCount κοινόχρηστοι εξοπλισμοί',
      );
    }

    return lines;
  }

  /// Αντλεί σύνολα από [LookupService] (ή από το δοθέν [lookup]).
  factory DepartmentDeletionInventory.fromLookup(
    int departmentId,
    String departmentName, {
    LookupService? lookup,
  }) {
    final svc = lookup ?? LookupService.instance;
    final employeeNames = svc
        .getUsersByDepartment(departmentId)
        .map((u) => (u.name ?? '').trim())
        .where((n) => n.isNotEmpty)
        .toList();
    final ownedPhones = svc.getCallerOwnedPhonesByDepartment(departmentId);
    final ownedEquipment =
        svc.getCallerOwnedEquipmentByDepartment(departmentId);
    return DepartmentDeletionInventory(
      departmentName: departmentName,
      employeeNames: employeeNames,
      employeeOwnedPhoneCount: ownedPhones.length,
      employeeOwnedEquipmentCount: ownedEquipment.length,
      sharedPhones: svc.getDirectPhonesByDepartment(departmentId),
      sharedEquipmentCodes:
          svc.getSharedEquipmentCodesByDepartment(departmentId),
    );
  }
}
