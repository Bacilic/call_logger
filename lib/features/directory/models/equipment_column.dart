import '../../../core/services/lookup_service.dart';
import '../../calls/models/equipment_model.dart';
import '../../calls/models/user_model.dart';

/// Γραμμή πίνακα εξοπλισμού: εξοπλισμός + κάτοχος (από `user_equipment`, εμφάνιση πρώτου). $1 = equipment, $2 = owner.
typedef EquipmentRow = (EquipmentModel, UserModel?);

String _departmentLocationCombinedLine(String dept, String loc) {
  final d = dept.trim();
  final l = loc.trim();
  if (d.isEmpty && l.isEmpty) return '';
  if (d.isEmpty) return l;
  if (l.isEmpty) return d;
  return '$d - $l';
}

/// «Τμήμα - Τοποθεσία»: πρώτα από κάτοχο· αν λείπει πεδίο, fallback στον εξοπλισμό ([LookupService] για τμήμα).
String _equipmentRowDepartmentLocationDisplay(EquipmentRow row) {
  final u = row.$2;
  final e = row.$1;
  var dept = u?.departmentName?.trim() ?? '';
  var loc = u?.location?.trim() ?? '';
  if (dept.isEmpty) {
    final id = e.departmentId;
    if (id != null) {
      dept = LookupService.instance.getDepartmentName(id)?.trim() ?? '';
    }
  }
  if (loc.isEmpty) {
    loc = e.location?.trim() ?? '';
  }
  final line = _departmentLocationCombinedLine(dept, loc);
  return line.isEmpty ? '–' : line;
}

String _equipmentRowDepartmentLocationSortKey(EquipmentRow row) {
  final u = row.$2;
  final e = row.$1;
  var dept = u?.departmentName?.trim() ?? '';
  var loc = u?.location?.trim() ?? '';
  if (dept.isEmpty) {
    final id = e.departmentId;
    if (id != null) {
      dept = LookupService.instance.getDepartmentName(id)?.trim() ?? '';
    }
  }
  if (loc.isEmpty) {
    loc = e.location?.trim() ?? '';
  }
  return _departmentLocationCombinedLine(dept, loc);
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
    _equipmentRowDepartmentLocationDisplay,
    _equipmentRowDepartmentLocationSortKey,
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
