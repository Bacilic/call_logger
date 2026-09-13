import '../../../core/database/department_repository.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/phone_repository.dart';
import '../../../core/database/sqlite_types.dart';
import '../../../core/database/user_repository.dart';

/// Τι **γέννησε** μία γρήγορη καταχώρηση — το υλικό της αναίρεσης.
///
/// Κρατά μόνο δημιουργίες, σκόπιμα. Όταν η καταχώρηση **μετακινεί** κάτι που
/// ήδη υπήρχε (τηλέφωνο ή μηχάνημα άλλου τμήματος), ο χρήστης το έχει ήδη
/// εγκρίνει στον διάλογο σύγκρουσης — εκεί η απόφαση πάρθηκε με ανοιχτά μάτια.
/// Σιωπηλή είναι μόνο η δημιουργία, και μόνο αυτή χρειάζεται δεύτερη ευκαιρία.
///
/// Η εκκρεμότητα που γεννά η ίδια ροή κρατά μόνο **σε ποιον δείχνει** — δεν
/// ξεχωρίζει τι ήταν καινούριο, γι' αυτό δεν μπορεί να θεμελιώσει αναίρεση.
class QuickAddUndoRecord {
  const QuickAddUndoRecord({
    this.createdDepartmentId,
    this.createdDepartmentName,
    this.createdUserId,
    this.createdUserName,
    this.createdPhone,
    this.createdEquipmentCode,
  });

  static const empty = QuickAddUndoRecord();

  /// Τμήμα που δεν υπήρχε πριν από την καταχώρηση.
  final int? createdDepartmentId;
  final String? createdDepartmentName;

  /// Υπάλληλος που δημιουργήθηκε ως νέος καλών.
  final int? createdUserId;
  final String? createdUserName;

  /// Τηλέφωνο που μπήκε πρώτη φορά στον κατάλογο.
  final String? createdPhone;

  /// Κωδικός εξοπλισμού που μπήκε πρώτη φορά στον κατάλογο.
  final String? createdEquipmentCode;

  bool get isEmpty =>
      createdDepartmentId == null &&
      createdUserId == null &&
      createdPhone == null &&
      createdEquipmentCode == null;

  bool get isNotEmpty => !isEmpty;

  QuickAddUndoRecord copyWith({
    int? createdDepartmentId,
    String? createdDepartmentName,
    int? createdUserId,
    String? createdUserName,
    String? createdPhone,
    String? createdEquipmentCode,
  }) {
    return QuickAddUndoRecord(
      createdDepartmentId: createdDepartmentId ?? this.createdDepartmentId,
      createdDepartmentName:
          createdDepartmentName ?? this.createdDepartmentName,
      createdUserId: createdUserId ?? this.createdUserId,
      createdUserName: createdUserName ?? this.createdUserName,
      createdPhone: createdPhone ?? this.createdPhone,
      createdEquipmentCode: createdEquipmentCode ?? this.createdEquipmentCode,
    );
  }
}

/// Τι ακριβώς θα σβηστεί, σε μία πρόταση προς τον χρήστη.
///
/// Απαριθμεί **μόνο ό,τι υπάρχει**: κουμπί που υπόσχεται διαγραφή τμήματος
/// χωρίς να έχει δημιουργηθεί τμήμα είναι μήνυμα-ψέμα.
String quickAddUndoSummary(QuickAddUndoRecord record) {
  final parts = <String>[
    if (record.createdUserName?.trim().isNotEmpty == true)
      'ο υπάλληλος «${record.createdUserName!.trim()}»',
    if (record.createdPhone?.trim().isNotEmpty == true)
      'το τηλέφωνο ${record.createdPhone!.trim()}',
    if (record.createdEquipmentCode?.trim().isNotEmpty == true)
      'ο εξοπλισμός ${record.createdEquipmentCode!.trim()}',
    if (record.createdDepartmentName?.trim().isNotEmpty == true)
      'το τμήμα «${record.createdDepartmentName!.trim()}»',
  ];
  if (parts.isEmpty) return 'Δεν υπήρχε τίποτα να αναιρεθεί.';
  if (parts.length == 1) return 'Αναιρέθηκε: διαγράφηκε ${parts.single}.';
  final last = parts.removeLast();
  return 'Αναιρέθηκε: διαγράφηκαν ${parts.join(', ')} και $last.';
}

/// Εκτελεί την αναίρεση μιας γρήγορης καταχώρησης.
///
/// **Η σειρά είναι κανόνας, όχι προτίμηση:** πρώτα φεύγουν όσα κατοικούν στο
/// τμήμα (υπάλληλος, τηλέφωνο, εξοπλισμός) και τελευταίο το ίδιο το τμήμα —
/// αλλιώς θα σβηνόταν ενώ ακόμη το κατοικεί κάποιος.
Future<void> applyQuickAddUndo(
  QuickAddUndoRecord record, {
  required DatabaseExecutor executor,
  required UserRepository users,
  required PhoneRepository phones,
  required EquipmentRepository equipment,
  required DepartmentRepository departments,
}) async {
  final createdUserId = record.createdUserId;
  if (createdUserId != null) {
    await users.deleteUsers([createdUserId], executor: executor);
  }

  final createdPhone = record.createdPhone?.trim();
  if (createdPhone != null && createdPhone.isNotEmpty) {
    final id = await phones.getPhoneIdByNumber(createdPhone);
    if (id != null) {
      await phones.softDeletePhones([id], executor: executor);
    }
  }

  final createdEquipment = record.createdEquipmentCode?.trim();
  if (createdEquipment != null && createdEquipment.isNotEmpty) {
    final id = await equipment.getEquipmentIdByCode(createdEquipment);
    if (id != null) {
      await equipment.deleteEquipments([id], executor: executor);
    }
  }

  final createdDepartmentId = record.createdDepartmentId;
  if (createdDepartmentId != null) {
    await departments.softDeleteDepartment(createdDepartmentId);
  }
}
