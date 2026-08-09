import '../../../core/services/lookup_service.dart';
import '../../calls/models/equipment_model.dart';

/// Ο εξοπλισμός που κουβαλά ένας υπάλληλος, όπως τον διαβάζουν ο πίνακας
/// και η φόρμα του καταλόγου.
class UserEquipmentCodes {
  const UserEquipmentCodes._();

  /// Ο συνδεδεμένος εξοπλισμός του υπαλλήλου (κενή λίστα όταν δεν υπάρχει `id`).
  static List<EquipmentModel> forUser(int? userId) {
    if (userId == null) return const [];
    return LookupService.instance.findEquipmentsForUser(userId);
  }

  /// Το κείμενο της στήλης «Εξοπλισμός»: «2792, 3917».
  ///
  /// Καθαρή συνάρτηση — δέχεται τη λίστα, δεν τη διαβάζει η ίδια.
  static String joinCodes(List<EquipmentModel> equipment) {
    return equipment.map(codeLabel).where((v) => v.isNotEmpty).join(', ');
  }

  /// Ο κωδικός του εξοπλισμού· όταν λείπει, η ετικέτα εμφάνισής του.
  static String codeLabel(EquipmentModel equipment) {
    final code = equipment.code?.trim();
    if (code != null && code.isNotEmpty) return code;
    return equipment.displayLabel.trim();
  }

  /// Το κείμενο της στήλης για τον υπάλληλο [userId].
  static String textForUser(int? userId) => joinCodes(forUser(userId));

  /// Πόσοι υπάλληλοι κρατούν τον ίδιο εξοπλισμό (κοινόχρηστος όταν είναι >1).
  static int ownerCount(EquipmentModel equipment) {
    final id = equipment.id;
    if (id == null) return 0;
    return LookupService.instance.findUsersForEquipment(id).length;
  }
}
