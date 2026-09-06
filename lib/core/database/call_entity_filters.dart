/// Τα κριτήρια «ποιανού είναι η κλήση»: τμήμα, υπάλληλος, εξοπλισμός.
///
/// Γράφονται **μία φορά** γιατί τα ρωτούν δύο οθόνες: τα Στατιστικά Κλήσεων και
/// το Ιστορικό. Το κουμπί «Προβολή όλων» περνά από τη μία στην άλλη, οπότε αν οι
/// δύο έκριναν με δικό της κριτήρια η καθεμιά, η μετάβαση θα άλλαζε σιωπηλά το
/// σύνολο των κλήσεων — ίδιο φίλτρο, άλλο αποτέλεσμα.
///
/// Οι εκφράσεις πέφτουν πίσω στο ελεύθερο κείμενο της κλήσης όταν δεν υπάρχει
/// σύνδεση με τον κατάλογο: μια παλιά κλήση κρατά το τμήμα ως κείμενο και πρέπει
/// να βρίσκεται κι αυτή.
library;

import '../utils/search_text_normalizer.dart';

/// Το τμήμα της κλήσης — από τον κατάλογο, αλλιώς το κείμενο της κλήσης.
const String kCallDepartmentExpr =
    "COALESCE(departments.name, calls.department_text, '-')";

/// Ο κωδικός εξοπλισμού της κλήσης — από τον κατάλογο, αλλιώς το κείμενο.
const String kCallEquipmentExpr =
    "COALESCE(equipment.code_equipment, calls.equipment_text, '')";

/// Τα τηλέφωνα του καλούντα — από την κλήση, αλλιώς όσα έχει ο υπάλληλος.
const String kCallUserPhoneExpr =
    "COALESCE(NULLIF(TRIM(calls.phone_text), ''), upl.phone_list, '-')";

/// Ονοματεπώνυμο καλούντα από τον κατάλογο (κενό όταν δεν υπάρχει σύνδεση).
const String kCallCallerNameExpr =
    "TRIM(COALESCE(users.first_name, '') || ' ' || COALESCE(users.last_name, ''))";

/// Το όνομα που εμφανίζεται: του καταλόγου, αλλιώς το κείμενο της κλήσης.
const String kCallCallerLabelExpr =
    "CASE WHEN TRIM($kCallCallerNameExpr) = '' "
    "THEN COALESCE(NULLIF(TRIM(calls.caller_text), ''), '-') "
    "ELSE TRIM($kCallCallerNameExpr) END";

/// Οι συνδέσεις που χρειάζονται οι παραπάνω εκφράσεις.
///
/// Όλες είναι `LEFT JOIN` ένα-προς-ένα, οπότε δεν πολλαπλασιάζουν γραμμές:
/// μπαίνουν με ασφάλεια και σε ερώτημα που μετράει.
const String kCallEntityFilterJoins = '''
      LEFT JOIN users ON calls.caller_id = users.id
      LEFT JOIN (
        SELECT up.user_id AS uid,
               GROUP_CONCAT(p.number, ', ') AS phone_list
        FROM user_phones up
        JOIN phones p ON p.id = up.phone_id
        GROUP BY up.user_id
      ) upl ON upl.uid = users.id
      LEFT JOIN equipment ON calls.equipment_id = equipment.id
      LEFT JOIN departments ON users.department_id = departments.id''';

/// Προσθέτει τα κριτήρια οντότητας σε ένα ερώτημα κλήσεων.
///
/// Η σημασία κάθε κριτηρίου είναι σκόπιμα διαφορετική και δεν αλλάζει:
/// - **τμήμα**: ακριβές ταίριασμα — έρχεται από κλειστή λίστα.
/// - **υπάλληλος**: όνομα **ή** τηλέφωνο, μερικό — ο χρήστης πληκτρολογεί ό,τι
///   θυμάται, και συχνά θυμάται το τηλέφωνο αντί για το επώνυμο.
/// - **εξοπλισμός**: μερικός κωδικός — τα «5010» και «501» πρέπει να βρίσκουν.
void appendCallEntityFilters(
  List<String> whereClauses,
  List<Object?> args, {
  String? department,
  String? userName,
  String? equipmentCode,
}) {
  final dept = department?.trim();
  if (dept != null && dept.isNotEmpty) {
    whereClauses.add('$kCallDepartmentExpr = ?');
    args.add(dept);
  }

  final user = userName?.trim();
  if (user != null && user.isNotEmpty) {
    final normalized = SearchTextNormalizer.normalizeForSearch(user);
    if (normalized.isNotEmpty) {
      whereClauses.add(
        '(calls.search_index LIKE ? OR $kCallUserPhoneExpr LIKE ?)',
      );
      args.add('%$normalized%');
      args.add('%$normalized%');
    }
  }

  final code = equipmentCode?.trim();
  if (code != null && code.isNotEmpty) {
    whereClauses.add('$kCallEquipmentExpr LIKE ?');
    args.add('%$code%');
  }
}

/// Προσθέτει το κριτήριο «κατηγορία κλήσης» σε ένα ερώτημα κλήσεων.
///
/// Γράφεται εδώ, δίπλα στα κριτήρια οντότητας, για τον ίδιο λόγο με εκείνα: το
/// ίδιο φίλτρο ζει στο Ιστορικό και στα Στατιστικά, και το «Προβολή όλων»
/// περνά από τη μία οθόνη στην άλλη. Δύο χωριστές εκφράσεις θα άλλαζαν σιωπηλά
/// το σύνολο των κλήσεων στη μετάβαση.
///
/// Κρίνει το **αποθηκευμένο κείμενο** της κλήσης και όχι το όνομα του
/// καταλόγου: η μετονομασία κατηγορίας ενημερώνει το κείμενο κάθε κλήσης, οπότε
/// τα δύο μένουν πάντα ταυτόσημα — και το κείμενο καλύπτει επιπλέον τις παλιές
/// κλήσεις που δεν έχουν σύνδεση με τον κατάλογο.
void appendCallCategoryFilter(
  List<String> whereClauses,
  List<Object?> args, {
  String? category,
}) {
  final name = category?.trim();
  if (name == null || name.isEmpty) return;
  whereClauses.add('calls.category_text = ?');
  args.add(name);
}
