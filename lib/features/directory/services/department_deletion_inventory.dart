import '../../../core/services/lookup_service.dart';
import 'bulk_deletion_summary.dart';

/// Απογραφή εξαρτημάτων τμήματος πριν από διαγραφή (καθαρή λογική, χωρίς UI).
class DepartmentDeletionInventory {
  const DepartmentDeletionInventory({
    required this.departmentId,
    required this.departmentName,
    required this.employeeNames,
    required this.employeeOwnedPhoneCount,
    required this.employeeOwnedEquipmentCount,
    required this.sharedPhones,
    required this.sharedEquipmentCodes,
  });

  /// Ταυτότητα τμήματος — ο διάλογος επιστρέφει ποια τμήματα έμειναν, και η
  /// αντιστοίχιση με όνομα θα ήταν εύθραυστη (δύο τμήματα μπορούν να έχουν
  /// ίδιο όνομα σε διαφορετικά κτίρια).
  final int departmentId;

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
    final ownedEquipment = svc.getCallerOwnedEquipmentByDepartment(
      departmentId,
    );
    return DepartmentDeletionInventory(
      departmentId: departmentId,
      departmentName: departmentName,
      employeeNames: employeeNames,
      employeeOwnedPhoneCount: ownedPhones.length,
      employeeOwnedEquipmentCount: ownedEquipment.length,
      sharedPhones: svc.getDirectPhonesByDepartment(departmentId),
      sharedEquipmentCodes: svc.getSharedEquipmentCodesByDepartment(
        departmentId,
      ),
    );
  }
}

/// Συγκεντρωτικά πλήθη πολλαπλής διαγραφής τμημάτων, για τη σύνοψη που μένει
/// σταθερή πάνω από τη λίστα.
///
/// Ο διαχωρισμός «κοινόχρηστα» / «ανήκουν σε υπαλλήλους» είναι σκόπιμος: τα
/// πρώτα ζητούν απόφαση από τον χρήστη, τα δεύτερα ακολουθούν τον κάτοχό τους.
/// Ένα ενιαίο άθροισμα θα έκρυβε αυτή τη διαφορά.
class DepartmentDeletionTotals {
  const DepartmentDeletionTotals({
    required this.departmentCount,
    required this.employeeCount,
    required this.sharedPhoneCount,
    required this.sharedEquipmentCount,
    required this.employeeOwnedPhoneCount,
    required this.employeeOwnedEquipmentCount,
  });

  factory DepartmentDeletionTotals.from(
    List<DepartmentDeletionInventory> inventories,
  ) {
    var employees = 0;
    var sharedPhones = 0;
    var sharedEquipment = 0;
    var ownedPhones = 0;
    var ownedEquipment = 0;
    for (final inv in inventories) {
      employees += inv.employeeNames.length;
      sharedPhones += inv.sharedPhones.length;
      sharedEquipment += inv.sharedEquipmentCodes.length;
      ownedPhones += inv.employeeOwnedPhoneCount;
      ownedEquipment += inv.employeeOwnedEquipmentCount;
    }
    return DepartmentDeletionTotals(
      departmentCount: inventories.length,
      employeeCount: employees,
      sharedPhoneCount: sharedPhones,
      sharedEquipmentCount: sharedEquipment,
      employeeOwnedPhoneCount: ownedPhones,
      employeeOwnedEquipmentCount: ownedEquipment,
    );
  }

  final int departmentCount;
  final int employeeCount;
  final int sharedPhoneCount;
  final int sharedEquipmentCount;
  final int employeeOwnedPhoneCount;
  final int employeeOwnedEquipmentCount;

  /// Κύρια γραμμή: τι ακριβώς αγγίζει η διαγραφή. Τα μηδενικά είδη λείπουν.
  ///
  /// Όταν ο χρήστης αφαίρεσε τμήματα μέσα στον διάλογο, το [initiallySelected]
  /// κάνει το πρώτο σκέλος «Ν από τα Μ επιλεγμένα»: αλλιώς η σύνοψη διαφωνεί
  /// σιωπηλά με το «Μ επιλεγμένα» της λίστας από πίσω.
  String headline({int? initiallySelected}) {
    return buildBulkDeletionHeadline(
      subject: SummaryCount(departmentCount, 'τμήμα', 'τμήματα'),
      initiallySelected: initiallySelected,
      details: [
        SummaryCount(employeeCount, 'υπάλληλος', 'υπάλληλοι'),
        SummaryCount(
          sharedPhoneCount,
          'κοινόχρηστο τηλέφωνο',
          'κοινόχρηστα τηλέφωνα',
        ),
        SummaryCount(
          sharedEquipmentCount,
          'κοινόχρηστος εξοπλισμός',
          'κοινόχρηστοι εξοπλισμοί',
        ),
      ],
    );
  }

  /// Δευτερεύουσα γραμμή για όσα ακολουθούν τον κάτοχό τους — `null` όταν δεν
  /// υπάρχουν, ώστε να μη γράφεται «0 τηλέφωνα».
  String? get followingAssetsLine {
    final phones = employeeOwnedPhoneCount;
    final equipment = employeeOwnedEquipmentCount;
    if (phones <= 0 && equipment <= 0) return null;

    final parts = <String>[];
    if (phones > 0) {
      parts.add(phones == 1 ? '1 τηλέφωνο' : '$phones τηλέφωνα');
    }
    if (equipment > 0) {
      parts.add(equipment == 1 ? '1 εξοπλισμός' : '$equipment εξοπλισμοί');
    }
    return 'Επιπλέον ${parts.join(' και ')} ανήκουν σε υπαλλήλους και θα '
        'τους ακολουθήσουν αν μεταφερθούν.';
  }
}

/// Τα τμήματα χωρισμένα κατά **το τι θα ζητηθεί από τον χρήστη**, όχι
/// αλφαβητικά.
///
/// Σε μαζική διαγραφή τα περισσότερα τμήματα δεν χρειάζονται καμία απόφαση —
/// διαγράφονται σιωπηλά. Η κατάταξη φέρνει μπροστά όσα θα σταματήσουν τη ροή
/// με ερώτηση, ώστε ο χρήστης να μη σαρώνει δεκάδες κάρτες για να τα βρει.
class DepartmentDeletionZones {
  const DepartmentDeletionZones({
    required this.withEmployees,
    required this.sharedOnly,
    required this.empty,
  });

  factory DepartmentDeletionZones.from(
    List<DepartmentDeletionInventory> inventories,
  ) {
    final withEmployees = <DepartmentDeletionInventory>[];
    final sharedOnly = <DepartmentDeletionInventory>[];
    final empty = <DepartmentDeletionInventory>[];
    for (final inv in inventories) {
      // Οι υπάλληλοι κερδίζουν: τμήμα με υπαλλήλους ΚΑΙ κοινόχρηστα ρωτά και
      // για τα δύο, οπότε ανήκει στη βαρύτερη ζώνη.
      if (inv.hasEmployees) {
        withEmployees.add(inv);
      } else if (inv.hasSharedAssets) {
        sharedOnly.add(inv);
      } else {
        empty.add(inv);
      }
    }
    return DepartmentDeletionZones(
      withEmployees: withEmployees,
      sharedOnly: sharedOnly,
      empty: empty,
    );
  }

  /// Ζητούν αποφάσεις για υπαλλήλους (και ό,τι άλλο έχουν).
  final List<DepartmentDeletionInventory> withEmployees;

  /// Ζητούν αποφάσεις μόνο για κοινόχρηστα τηλέφωνα / εξοπλισμό.
  final List<DepartmentDeletionInventory> sharedOnly;

  /// Δεν ζητούν τίποτα — διαγράφονται κατευθείαν.
  final List<DepartmentDeletionInventory> empty;

  /// Οι επικεφαλίδες έχουν νόημα μόνο όταν υπάρχει κάτι να ξεχωρίσουν· με μία
  /// γεμάτη ζώνη είναι σκέτος θόρυβος.
  bool get showsZoneHeaders {
    var filled = 0;
    if (withEmployees.isNotEmpty) filled++;
    if (sharedOnly.isNotEmpty) filled++;
    if (empty.isNotEmpty) filled++;
    return filled > 1;
  }

  String get withEmployeesHeader => 'Με υπαλλήλους (${withEmployees.length})';

  String get sharedOnlyHeader =>
      'Με κοινόχρηστα τηλέφωνα ή εξοπλισμό (${sharedOnly.length})';

  /// Γραμμή για τα άδεια τμήματα — `null` όταν δεν υπάρχουν.
  String? get emptyHeader {
    final count = empty.length;
    if (count <= 0) return null;
    if (count == 1) {
      return '1 τμήμα χωρίς εξαρτήματα — διαγράφεται χωρίς ερώτηση';
    }
    return '$count τμήματα χωρίς εξαρτήματα — διαγράφονται χωρίς ερώτηση';
  }
}

/// Ονόματα των τμημάτων που είναι **αυτή τη στιγμή** χωρίς κανένα εξάρτημα,
/// από τα [departmentIds] που άγγιξε μια ενέργεια.
///
/// Καλείται ΜΕΤΑ τη μεταβολή και το ξαναχτίσιμο του lookup: απαντά «τι ισχύει
/// τώρα», όχι «τι άλλαξε». Τα `null` και τα διπλότυπα id αγνοούνται, ώστε ο
/// καλών να μπορεί να δώσει ωμά τα τμήματα των εγγραφών που έσβησε.
List<String> emptiedDepartmentNames(
  Iterable<int?> departmentIds, {
  LookupService? lookup,
}) {
  final svc = lookup ?? LookupService.instance;
  final seen = <int>{};
  final names = <String>[];
  for (final id in departmentIds) {
    if (id == null || !seen.add(id)) continue;
    final name = svc.getDepartmentName(id)?.trim() ?? '';
    if (name.isEmpty) continue;
    if (DepartmentDeletionInventory.fromLookup(id, name, lookup: svc).isEmpty) {
      names.add(name);
    }
  }
  return names;
}
