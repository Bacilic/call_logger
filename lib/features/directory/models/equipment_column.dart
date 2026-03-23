import '../../../core/services/lookup_service.dart';
import '../../calls/models/equipment_model.dart';
import '../../calls/models/user_model.dart';

/// Γραμμή πίνακα εξοπλισμού: εξοπλισμός + κάτοχος (από `user_equipment`, εμφάνιση πρώτου). $1 = equipment, $2 = owner.
typedef EquipmentRow = (EquipmentModel, UserModel?);

/// Στήλη «Τοποθεσία»: `[Κτίριο] Τμήμα - Τοποθεσία` με αυστηρή πηγή (κάτοχος ή εξοπλισμός).
/// Με [showBuilding]: false παραλείπεται το πρόθεμα `[Κτίριο]`.
String equipmentRowLocationFormattedLine(
  EquipmentRow row, {
  bool showBuilding = true,
}) {
  final owner = row.$2;
  final eq = row.$1;
  final int? deptId;
  final String? locRaw;
  if (owner != null) {
    deptId = owner.departmentId;
    locRaw = owner.location;
  } else {
    deptId = eq.departmentId;
    locRaw = eq.location;
  }
  final deptName =
      (deptId != null
              ? LookupService.instance.getDepartmentName(deptId)
              : null)
          ?.trim() ??
      '';
  final building =
      (LookupService.instance.getDepartmentBuilding(deptId) ?? '').trim();
  final loc = (locRaw ?? '').trim();

  final hasB = building.isNotEmpty;
  final hasD = deptName.isNotEmpty;
  final hasL = loc.isNotEmpty;

  if (!hasB && !hasD && !hasL) return '–';

  String deptLoc;
  if (hasD && hasL) {
    deptLoc = '$deptName - $loc';
  } else if (hasD) {
    deptLoc = deptName;
  } else if (hasL) {
    deptLoc = loc;
  } else {
    deptLoc = '';
  }

  if (!showBuilding) {
    if (deptLoc.isNotEmpty) return deptLoc;
    return '–';
  }

  if (hasB && deptLoc.isNotEmpty) {
    return '[$building] $deptLoc';
  }
  if (hasB) {
    return '[$building]';
  }
  if (deptLoc.isNotEmpty) return deptLoc;
  return '–';
}

/// Ορισμός στηλών πίνακα εξοπλισμού με key, label, displayValue και sortValue.
class EquipmentColumn {
  EquipmentColumn(
    this.key,
    this.label,
    this.displayValue,
    this.sortValue,
  );

  final String key;
  final String label;
  final String Function(EquipmentRow row) displayValue;
  final Comparable? Function(EquipmentRow row)? sortValue;

  static final selection = EquipmentColumn(
    'selection',
    'Επιλογή',
    (_) => '',
    null,
  );
  static final id = EquipmentColumn(
    'id',
    'ID',
    (row) => row.$1.id != null ? '${row.$1.id}' : '–',
    (row) => row.$1.id,
  );

  static final code = EquipmentColumn(
    'code',
    'Κωδικός',
    (row) => row.$1.code ?? '–',
    (row) => row.$1.code ?? '',
  );
  static final type = EquipmentColumn(
    'type',
    'Τύπος',
    (row) => row.$1.type ?? '–',
    (row) => row.$1.type ?? '',
  );
  /// Κείμενο όταν δεν υπάρχει συνδεδεμένος κάτοχος (user_equipment).
  static const String emptyOwnerDisplayLabel = 'Χωρίς κάτοχο';

  static final owner = EquipmentColumn(
    'owner',
    'Κάτοχος',
    (row) => row.$2?.name ?? emptyOwnerDisplayLabel,
    (row) => row.$2?.name ?? '',
  );
  static final location = EquipmentColumn(
    'location',
    'Τοποθεσία',
    (row) => equipmentRowLocationFormattedLine(row),
    (row) => equipmentRowLocationFormattedLine(row),
  );
  static final phone = EquipmentColumn(
    'phone',
    'Τηλέφωνο',
    (row) {
      final p = row.$2?.phoneJoined ?? '';
      return p.isEmpty ? '–' : p;
    },
    (row) => row.$2?.phoneJoined ?? '',
  );
  static final notes = EquipmentColumn(
    'notes',
    'Σημειώσεις',
    (row) => row.$1.notes ?? '–',
    (row) => row.$1.notes ?? '',
  );
  static final customIp = EquipmentColumn(
    'customIp',
    'Προσαρμοσμένη IP',
    (row) => row.$1.customIp ?? '–',
    (row) => row.$1.customIp ?? '',
  );
  static final anydeskId = EquipmentColumn(
    'anydeskId',
    'AnyDesk ID',
    (row) => row.$1.anydeskId ?? '–',
    (row) => row.$1.anydeskId ?? '',
  );
  static final defaultRemote = EquipmentColumn(
    'defaultRemote',
    'Εργαλείο Απομακρυσμένης',
    (row) => row.$1.defaultRemoteTool ?? '–',
    (row) => row.$1.defaultRemoteTool ?? '',
  );

  /// Προεπιλεγμένες ορατές στήλες (επιλογή, id, κωδικός, τύπος, κάτοχος, IP).
  static final List<EquipmentColumn> defaults = [
    selection,
    id,
    code,
    type,
    owner,
    customIp,
  ];

  /// Όλες οι διαθέσιμες στήλες για το μενού επιλογής.
  static final List<EquipmentColumn> all = [
    selection,
    id,
    code,
    type,
    owner,
    location,
    phone,
    notes,
    customIp,
    anydeskId,
    defaultRemote,
  ];

  static EquipmentColumn? fromKey(String k) {
    for (final c in all) {
      if (c.key == k) return c;
    }
    return null;
  }

  /// Η στήλη [selection] πάντα στην πρώτη θέση (αν υπάρχει στη λίστα).
  static List<EquipmentColumn> pinSelectionFirst(List<EquipmentColumn> order) {
    if (!order.any((c) => c.key == selection.key)) {
      return List<EquipmentColumn>.from(order);
    }
    return [
      selection,
      ...order.where((c) => c.key != selection.key),
    ];
  }
}
