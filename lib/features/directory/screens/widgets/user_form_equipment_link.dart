import '../../../calls/models/equipment_model.dart';
import '../../../calls/provider/lookup_provider.dart';
import '../../services/equipment_form_launcher.dart';
import '../../services/user_equipment_codes.dart';
import 'user_form_dialog.dart';
import 'user_form_equipment_chips.dart';

/// Ο δεσμός της φόρμας υπαλλήλου με τον εξοπλισμό του: ποιον κουβαλά και τι
/// γίνεται όταν πατηθεί.
///
/// Συνεργάτης του [UserFormDialogState] (Σύνθεση) — κρατά την ενορχήστρωση
/// έξω από το `build` της φόρμας.
class UserFormEquipmentLink {
  UserFormEquipmentLink(this.host);

  final UserFormDialogState host;

  /// Ο εξοπλισμός εμφανίζεται μόνο σε επεξεργασία: ο νέος υπάλληλος δεν έχει
  /// ακόμη ταυτότητα, και το αντίγραφο δεν κληρονομεί τον εξοπλισμό της πηγής.
  bool get isVisible => host.isEdit;

  /// Ο εξοπλισμός του υπαλλήλου μαζί με το πλήθος κατόχων του καθενός.
  List<UserEquipmentChipEntry> get entries {
    if (!isVisible) return const [];
    return [
      for (final e in UserEquipmentCodes.forUser(host.widget.initialUser?.id))
        (equipment: e, ownerCount: UserEquipmentCodes.ownerCount(e)),
    ];
  }

  /// Άνοιγμα της καρτέλας του εξοπλισμού πάνω από τη φόρμα του υπαλλήλου.
  Future<void> openEquipment(EquipmentModel item) async {
    final id = item.id;
    if (id == null) return;
    final allowed = await host.dismissGuard.requestSideTrip();
    if (!allowed || !host.mounted) return;

    await EquipmentFormLauncher.openById(host.context, host.ref, id);
    if (!host.mounted) return;

    // Η καρτέλα μπορεί να άλλαξε κάτοχο ή τμήμα: ο κατάλογος ξαναδιαβάζεται
    // πριν ξανασχεδιαστεί η λίστα, αλλιώς τα chips δείχνουν την παλιά εικόνα.
    await host.ref.read(lookupServiceProvider.future);
    if (!host.mounted) return;
    host.refreshEquipmentSection();
  }
}
