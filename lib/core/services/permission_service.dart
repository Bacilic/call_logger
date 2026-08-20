import '../models/app_permission.dart';
import '../models/operator.dart';
import 'current_operator.dart';

/// Απαντά στο μοναδικό ερώτημα «επιτρέπεται;».
///
/// Υπάρχει ώστε η επιβολή δικαιωμάτων, όταν έρθει η ώρα της, να μπει σε ένα
/// σημείο και όχι σε δεκάδες. **Σήμερα δεν απαγορεύει τίποτα**: όλα τα
/// δικαιώματα του καταλόγου επιτρέπονται από προεπιλογή, οπότε η απάντηση είναι
/// πάντα «ναι» μέχρι να οριστούν ρητά περιορισμοί από τον διαχειριστή.
class PermissionService {
  const PermissionService();

  static const PermissionService instance = PermissionService();

  /// Σειρά απόφασης:
  ///
  /// 1. **Καμία ταυτότητα → επιτρέπεται.** Αν η αναγνώριση απέτυχε ή δεν έχει
  ///    τρέξει, ο χρήστης δουλεύει όπως πάντα. Τα δικαιώματα είναι ζώνη
  ///    ασφαλείας από λάθη, όχι κλειδαριά — δεν επιτρέπεται να κλειδώσουν
  ///    κάποιον έξω από την ίδια του την εφαρμογή.
  /// 2. **Διαχειριστής → επιτρέπεται**, χωρίς να κοιταχτεί η λίστα.
  /// 3. **Ρητή παράκαμψη** του διαχειριστή για αυτόν τον χρήστη, αν υπάρχει.
  /// 4. Αλλιώς η **προεπιλογή του ίδιου του δικαιώματος**.
  bool can(AppPermission permission, {Operator? operator}) {
    final who = operator ?? CurrentOperator.active;
    if (who == null) return true;
    if (who.isAdmin) return true;
    final override = who.permissionOverrides[permission.key];
    if (override != null) return override;
    return permission.allowedByDefault;
  }
}
