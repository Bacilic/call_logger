import '../../calls/models/equipment_model.dart';
import '../../calls/models/user_model.dart';

/// Γραμμή πίνακα εξοπλισμού: εξοπλισμός + κάτοχος (από user_id). $1 = equipment, $2 = owner.
typedef EquipmentRow = (EquipmentModel, UserModel?);

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
  static final owner = EquipmentColumn(
    'owner',
    'Κάτοχος',
    (row) => row.$2?.name ?? 'Χωρίς κάτοχο',
    (row) => row.$2?.name ?? '',
  );
  static final location = EquipmentColumn(
    'location',
    'Τοποθεσία',
    (row) => row.$2?.location ?? '–',
    (row) => row.$2?.location ?? '',
  );
  static final phone = EquipmentColumn(
    'phone',
    'Τηλέφωνο',
    (row) => row.$2?.phone ?? '–',
    (row) => row.$2?.phone ?? '',
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

  /// Προεπιλεγμένες ορατές στήλες (κωδικός, τύπος, κάτοχος, IP).
  static final List<EquipmentColumn> defaults = [
    code,
    type,
    owner,
    customIp,
  ];

  /// Όλες οι διαθέσιμες στήλες για το μενού επιλογής.
  static final List<EquipmentColumn> all = [
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
}
