import 'package:flutter/foundation.dart';

/// Οι ενέργειες που προσφέρει η οθόνη πάνω σε μία εκκρεμότητα.
///
/// Ταξιδεύουν μαζί ως ένα αντικείμενο αντί για οκτώ ξεχωριστές παραμέτρους σε
/// κάθε υπο-κομμάτι της κάρτας: ο καλών δεν μπορεί να ξεχάσει κάποια, και τα
/// κομμάτια μένουν ανεξάρτητα από την κάρτα που τα φιλοξενεί — δοκιμάζονται
/// μόνα τους, χωρίς να χρειάζεται να στηθεί ολόκληρη η κάρτα.
///
/// Ενέργεια που λείπει σημαίνει «η οθόνη δεν την προσφέρει εδώ»: το αντίστοιχο
/// κουμπί τότε μένει απλή ένδειξη ή δεν εμφανίζεται καθόλου.
@immutable
class TaskCardCallbacks {
  const TaskCardCallbacks({
    this.onEdit,
    this.onAssign,
    this.onSnooze,
    this.onDelete,
    this.onComplete,
    this.onEditCaller,
    this.onEditDepartment,
    this.onEditEquipment,
  });

  final VoidCallback? onEdit;

  /// Άνοιγμα του διαλόγου γρήγορης ανάθεσης — δίνεται από την οθόνη.
  final VoidCallback? onAssign;
  final VoidCallback? onSnooze;
  final VoidCallback? onDelete;
  final VoidCallback? onComplete;

  /// Οι φόρμες επεξεργασίας οντοτήτων επιστρέφουν `true` όταν αποθηκεύτηκε
  /// κάτι — μόνο τότε έχει νόημα το επόμενο βήμα της κάρτας.
  final Future<bool> Function()? onEditCaller;
  final Future<bool> Function()? onEditDepartment;
  final Future<bool> Function()? onEditEquipment;
}
