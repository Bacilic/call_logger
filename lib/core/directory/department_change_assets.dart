import 'package:sqflite_common/sqlite_api.dart';

import '../../features/calls/models/equipment_model.dart';
import '../database/equipment_repository.dart';
import '../database/phone_repository.dart';
import '../database/user_repository.dart';

/// Εκτελεί την απόφαση «μένει πίσω» όταν ένας υπάλληλος αλλάζει τμήμα.
///
/// **Γιατί ζει εδώ και όχι μέσα σε κάθε οθόνη:** την ίδια απόφαση την παίρνουν
/// η φόρμα υπαλλήλου και η γρήγορη προσθήκη της κλήσης. Γραμμένη δύο φορές θα
/// απέκλινε στην πρώτη αλλαγή — και η οθόνη που θα την ξεχνούσε θα γινόταν
/// σιωπηλή τρύπα στα δεδομένα.
///
/// Η μαζική μεταφορά ΔΕΝ την καλεί: εκεί οι ίδιες ενέργειες τρέχουν μέσα σε
/// μία συναλλαγή με πακέτο αναίρεσης, οπότε δεν μπορούν να βγουν έξω από
/// αυτήν. Ο **κανόνας** που κρίνει τι μένει πίσω είναι ήδη κοινός και για τις
/// τρεις (`judgePhoneStayBehind`, `judgeEquipmentStayBehind`).
///
/// Είναι ασφαλές να κληθεί πριν ή μετά την εγγραφή της καρτέλας: η αφαίρεση
/// τηλεφώνου από υπάλληλο που δεν το κρατά πια, και η προσθήκη αριθμού σε
/// τμήμα που ήδη τον έχει, δεν κάνουν τίποτα.
Future<void> applyAssetsStayingBehind({
  required Database db,
  required int userId,
  required int? oldDepartmentId,

  /// Οι αριθμοί που ο χρήστης αποφάσισε να αφήσει στο τμήμα.
  Iterable<String> phones = const [],

  /// Τα μηχανήματα που ο χρήστης αποφάσισε να αφήσει στο τμήμα.
  Iterable<EquipmentModel> equipment = const [],

  /// Τα τηλέφωνα που κρατά σήμερα ο υπάλληλος — τα δίνει ο καλών, ώστε η
  /// συνάρτηση να μη μαντεύει ποια είναι η «τρέχουσα» εικόνα του.
  Iterable<String> currentPhones = const [],
}) async {
  final leaving = {
    for (final p in phones)
      if (p.trim().isNotEmpty) p.trim(),
  };
  final machines = equipment.where((e) => e.id != null).toList();
  if (leaving.isEmpty && machines.isEmpty) return;

  if (leaving.isNotEmpty) {
    final remaining = [
      for (final p in currentPhones)
        if (!leaving.contains(p.trim())) p,
    ];
    if (remaining.length != currentPhones.length) {
      await UserRepository(db).replaceUserPhones(userId, remaining);
    }
    if (oldDepartmentId != null) {
      final phoneRepo = PhoneRepository(db);
      for (final number in leaving) {
        await phoneRepo.addDepartmentDirectPhone(oldDepartmentId, number);
      }
    }
  }

  if (machines.isNotEmpty) {
    final equipmentRepo = EquipmentRepository(db);
    for (final item in machines) {
      await equipmentRepo.unlinkUserFromEquipment(userId, item.id!);
      // Το μηχάνημα χωρίς τμήμα παίρνει εκείνο που αφήνει ο άνθρωπος: ο
      // εξοπλισμός δεν μένει ποτέ ορφανός.
      final code = (item.code ?? '').trim();
      if (item.departmentId == null &&
          oldDepartmentId != null &&
          code.isNotEmpty) {
        await equipmentRepo.updateEquipmentDepartment(code, oldDepartmentId);
      }
    }
  }
}
