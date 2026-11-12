import 'package:intl/intl.dart';

import 'lamp_equipment_view_model.dart';

/// Ό,τι γράφει ο χρήστης στα αριθμητικά πεδία της Λάμπας: πώς διαβάζεται,
/// πώς δείχνεται και πώς αποθηκεύεται.
///
/// **Ο χρήστης γράφει ελληνικά** (απόφαση Διευθυντή 04/11/2026): κόμμα για
/// δεκαδικά, τελεία για χιλιάδες. Το «1.537» είναι 1.537 €, και γραφή που δεν
/// είναι ελληνική, όπως το «1537.50», απορρίπτεται με μήνυμα — ποτέ δεν
/// μαντεύεται.
abstract final class LampFieldInput {
  static const String moneyFormatError =
      'Γράψτε το ποσό ελληνικά, π.χ. 1.537,50 (τελεία για χιλιάδες, κόμμα '
      'για δεκαδικά).';

  static const String floorFormatError =
      'Ο όροφος είναι ακέραιος αριθμός, π.χ. 2.';

  static final RegExp _greekMoney = RegExp(r'^(\d{1,3}(\.\d{3})+|\d+)(,\d+)?$');

  /// Ποσό σε ελληνική γραφή, ή `null` όταν η γραφή δεν είναι ελληνική.
  static num? parseGreekMoney(String text) {
    final t = text.replaceAll('€', '').replaceAll(' ', '').trim();
    if (!_greekMoney.hasMatch(t)) return null;
    return num.tryParse(t.replaceAll('.', '').replaceAll(',', '.'));
  }

  /// Το αποθηκευμένο ποσό («1537.5000») όπως το βλέπει ο χρήστης στο πεδίο
  /// επεξεργασίας («1.537,50»). Ό,τι δεν διαβάζεται μένει όπως είναι.
  static String? moneyForEdit(String? stored) {
    if (stored == null || stored.trim().isEmpty) return stored;
    final number = EquipmentViewModel.parseLampMoney(stored);
    if (number == null) return stored;
    return NumberFormat('#,##0.00', 'el').format(number);
  }

  /// Η μορφή που έχουν όλα τα κόστη της Λάμπας («1537.5000»): η βάση μένει
  /// ομοιόμορφη, και η ανάγνωση δεν χρειάζεται να μαντέψει.
  static String moneyForStorage(num value) => value.toStringAsFixed(4);

  /// Μήνυμα όταν ο όροφος δεν είναι ακέραιος — `null` όταν είναι.
  static String? floorError(String text) =>
      int.tryParse(text.trim()) == null ? floorFormatError : null;
}
