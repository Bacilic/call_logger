import '../../../../core/database/omnisearch_service.dart';
import '../../../calls/models/equipment_model.dart';
import '../../../calls/models/user_model.dart';

/// Στόχος μετάβασης στον χάρτη κτιρίου — ρητός τύπος-ένωση αντί για `dynamic`.
///
/// `sealed`: ο μεταγλωττιστής απαιτεί ο resolver να χειρίζεται ΟΛΕΣ τις
/// περιπτώσεις· νέο είδος στόχου = σφάλμα μεταγλώττισης μέχρι να προστεθεί
/// ο χειρισμός του, όχι σιωπηλή αποτυχία στην εκτέλεση.
sealed class BuildingMapJumpTarget {
  const BuildingMapJumpTarget();

  /// Κατευθείαν σε τμήμα (π.χ. από τον μικρό χάρτη της φόρμας κλήσης).
  const factory BuildingMapJumpTarget.department(int departmentId) =
      BuildingMapDepartmentJump;

  /// Μέσω τηλεφώνου — το τμήμα βρίσκεται από τη θέση του τηλεφώνου.
  const factory BuildingMapJumpTarget.phone(String phoneNumber) =
      BuildingMapPhoneJump;

  /// Μέσω υπαλλήλου — το τμήμα βρίσκεται από τις τοποθετήσεις του.
  const factory BuildingMapJumpTarget.user(UserModel user) =
      BuildingMapUserJump;

  /// Μέσω εξοπλισμού — το τμήμα βρίσκεται από τη θέση του εξοπλισμού.
  const factory BuildingMapJumpTarget.equipment(EquipmentModel equipment) =
      BuildingMapEquipmentJump;

  /// Επιλογή από την έξυπνη αναζήτηση του χάρτη.
  const factory BuildingMapJumpTarget.searchHit(BuildingMapOmnisearchHit hit) =
      BuildingMapSearchHitJump;
}

final class BuildingMapDepartmentJump extends BuildingMapJumpTarget {
  const BuildingMapDepartmentJump(this.departmentId);

  final int departmentId;
}

final class BuildingMapPhoneJump extends BuildingMapJumpTarget {
  const BuildingMapPhoneJump(this.phoneNumber);

  final String phoneNumber;
}

final class BuildingMapUserJump extends BuildingMapJumpTarget {
  const BuildingMapUserJump(this.user);

  final UserModel user;
}

final class BuildingMapEquipmentJump extends BuildingMapJumpTarget {
  const BuildingMapEquipmentJump(this.equipment);

  final EquipmentModel equipment;
}

final class BuildingMapSearchHitJump extends BuildingMapJumpTarget {
  const BuildingMapSearchHitJump(this.hit);

  final BuildingMapOmnisearchHit hit;
}
