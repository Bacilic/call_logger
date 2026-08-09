import '../../../core/services/lookup_service.dart';
import '../../calls/models/equipment_model.dart';
import '../../calls/models/user_model.dart';

/// Γραμμή πίνακα εξοπλισμού: εξοπλισμός + κάτοχος (από `user_equipment`, εμφάνιση πρώτου). $1 = equipment, $2 = owner.
typedef EquipmentRow = (EquipmentModel, UserModel?);

/// Η τοποθεσία που ισχύει για μια γραμμή εξοπλισμού.
///
/// Η δική του υπερισχύει· όταν είναι κενή, κληρονομεί από τον κάτοχο. Έτσι ο
/// φορητός ακολουθεί τον άνθρωπο, ενώ ο εκτυπωτής που κάθεται στον διάδρομο
/// κρατά δική του θέση.
String effectiveEquipmentLocation(EquipmentRow row) {
  final own = (row.$1.location ?? '').trim();
  if (own.isNotEmpty) return own;
  return (row.$2?.location ?? '').trim();
}

/// Το κείμενο που εξηγεί ότι ο εξοπλισμός **δεν** ακολουθεί τον κάτοχό του.
///
/// Είναι ένδειξη κατάστασης, όχι κατηγορία: ο εκτυπωτής που στέκεται αλλού από
/// το γραφείο του κατόχου είναι απόλυτα θεμιτός. Ο λόγος που φαίνεται πάντα
/// είναι ότι κάποιος πρέπει να ξέρει τι αφήνει πίσω του πριν το αφήσει.
String equipmentLocationDivergenceNotice({
  required String ownerName,
  String? ownerLocation,
}) {
  final name = ownerName.trim();
  final who = name.isEmpty ? 'ο κάτοχος' : 'ο/η $name';
  final loc = (ownerLocation ?? '').trim();
  if (loc.isEmpty) {
    return 'Δεν ακολουθεί τον κάτοχο — $who δεν έχει ορίσει θέση';
  }
  return 'Δεν ακολουθεί τον κάτοχο — $who είναι «$loc»';
}

/// Στήλη «Τοποθεσία»: `[Κτίριο Όροφος] Τμήμα - Τοποθεσία`.
///
/// Κτίριο, όροφος και τμήμα προκύπτουν από τη βάση· το ελεύθερο κείμενο της
/// τοποθεσίας συμπληρώνει μόνο ό,τι δεν ξέρει κανείς άλλος — τη θέση μέσα στο
/// γραφείο («πίσω από την πόρτα»). Με [showBuilding]: false φεύγει το πρόθεμα.
String equipmentRowLocationFormattedLine(
  EquipmentRow row, {
  bool showBuilding = true,
}) {
  final owner = row.$2;
  final eq = row.$1;
  final deptId = owner != null ? owner.departmentId : eq.departmentId;
  final deptName =
      (deptId != null ? LookupService.instance.getDepartmentName(deptId) : null)
          ?.trim() ??
      '';
  final building = [
    (LookupService.instance.getDepartmentBuilding(deptId) ?? '').trim(),
    (LookupService.instance.getDepartmentFloor(deptId) ?? '').trim(),
  ].where((part) => part.isNotEmpty).join(' ');
  final loc = effectiveEquipmentLocation(row);

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
  EquipmentColumn(this.key, this.label, this.displayValue, this.sortValue);

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
  static final phone = EquipmentColumn('phone', 'Τηλέφωνο', (row) {
    final p = row.$2?.phoneJoined ?? '';
    return p.isEmpty ? '–' : p;
  }, (row) => row.$2?.phoneJoined ?? '');
  static final notes = EquipmentColumn(
    'notes',
    'Σημειώσεις',
    (row) => row.$1.notes ?? '–',
    (row) => row.$1.notes ?? '',
  );
  static final remoteParams = EquipmentColumn(
    'remoteParams',
    'Παράμετροι απομακρυσμένης',
    (row) {
      final p = row.$1.remoteParams;
      if (p.isEmpty) return '–';
      return p.entries.map((e) => '${e.key}: ${e.value}').join(' · ');
    },
    (row) =>
        row.$1.remoteParams.entries.map((e) => '${e.key}:${e.value}').join('|'),
  );
  static final defaultRemote = EquipmentColumn(
    'defaultRemote',
    'Εργαλείο Απομακρυσμένης',
    (row) => row.$1.defaultRemoteTool ?? '–',
    (row) => row.$1.defaultRemoteTool ?? '',
  );

  /// Προεπιλεγμένες ορατές στήλες (επιλογή, id, κωδικός, τύπος, κάτοχος).
  static final List<EquipmentColumn> defaults = [
    selection,
    id,
    code,
    type,
    owner,
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
    remoteParams,
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
    return [selection, ...order.where((c) => c.key != selection.key)];
  }
}
