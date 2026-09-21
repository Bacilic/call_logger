import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/app_permission.dart';
import '../../../core/providers/history_audit_immersive_provider.dart';
import '../../../core/services/permission_service.dart';

/// Επιτρέπεται σε αυτόν τον χρήστη το Ιστορικό Εφαρμογής;
///
/// **Μοναδικό σημείο για κάθε πύλη που οδηγεί εκεί** — σήμερα μόνο το κουμπί
/// εναλλαγής στο Ιστορικό Κλήσεων. Κάθε νέα πύλη ρωτά εδώ και κληρονομεί
/// αυτόματα τον έλεγχο, χωρίς να ξέρει ότι υπάρχει.
///
/// Δεν συνδυάζεται με προτίμηση χρήστη, σε αντίθεση με την Περιήγηση Βάσης: το
/// Ιστορικό Εφαρμογής δεν έχει διακόπτη στις Ρυθμίσεις, μόνο δικαίωμα.
///
/// **Ακυρώνεται ρητά στην αλλαγή χρήστη** — δες `invalidateOperatorScopedCaches`.
/// Το δικαίωμα δεν είναι provider· διαβάζεται από τον συνδεδεμένο χρήστη τη
/// στιγμή του υπολογισμού, οπότε χωρίς ακύρωση θα έμενε η απάντηση του
/// προηγούμενου.
final applicationAuditVisibleProvider = Provider<bool>(
  (ref) => PermissionService.instance.can(AppPermission.viewApplicationAudit),
);

/// Κλείνει την προβολή όταν ο χρήστης δεν τη δικαιούται.
///
/// **Δεν αρκεί να κρυφτεί το κουμπί.** Ο προηγούμενος μπορεί να άφησε το
/// Ιστορικό Εφαρμογής ανοιχτό και να πάτησε «Αλλαγή χρήστη» από μέσα: τότε ο
/// επόμενος θα καθόταν σε οθόνη που δεν δικαιούται, με το κουμπί επιστροφής
/// ορατό και το κουμπί ανοίγματος κρυμμένο.
///
/// Ζει εδώ ως **ξεχωριστή συνάρτηση** και όχι μέσα στον καλούντα, ώστε ο
/// έλεγχος να φυλάει τον ίδιο τον κώδικα που τρέχει — όχι ένα αντίγραφό του.
void closeApplicationAuditIfNotAllowed({
  required bool allowed,
  required HistoryApplicationAuditViewNotifier view,
  required HistoryAuditImmersiveNotifier immersive,
}) {
  if (allowed) return;
  view.setFalse();
  immersive.setFalse();
}

/// Όταν true, εμφανίζεται «Ιστορικό Εφαρμογής» αντί για ιστορικό κλήσεων.
class HistoryApplicationAuditViewNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;

  void setFalse() => state = false;
}

final historyApplicationAuditViewProvider =
    NotifierProvider<HistoryApplicationAuditViewNotifier, bool>(
      HistoryApplicationAuditViewNotifier.new,
    );
