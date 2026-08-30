import '../../../core/models/operator.dart';

/// Το επίθημα που ξεχωρίζει ένα απενεργοποιημένο προφίλ μέσα σε λίστα επιλογής.
///
/// Ίδιο ύφος με το «(διαγραμμένο)» των οντοτήτων καταλόγου: παρένθεση και
/// πλάγια γράμματα — ο χρήστης έχει μάθει ότι έτσι δηλώνεται κάτι που υπάρχει
/// ακόμη ως πληροφορία αλλά δεν προσφέρεται πια για νέα δουλειά.
const String kOperatorDisabledSuffix = ' (απενεργοποιημένος)';

/// Τα προφίλ που προσφέρονται όταν αλλάζει η ανάθεση μιας εκκρεμότητας: τα
/// ενεργά, **συν** τον σημερινό υπεύθυνο ακόμη κι αν έχει απενεργοποιηθεί.
///
/// Η απενεργοποίηση σταματά τη ΝΕΑ δουλειά, δεν σβήνει την ταυτότητα. Ο
/// υπεύθυνος που εξαφανίζεται από τη λίστα κάνει την εκκρεμότητα να μοιάζει
/// αδέσποτη ενώ ανήκει σε συγκεκριμένο πρόσωπο — και ο χρήστης δεν έχει τρόπο
/// να καταλάβει σε ποιον, ούτε γιατί το φίλτρο τη φέρνει εκεί που τη φέρνει.
///
/// Η σειρά της αρχικής λίστας διατηρείται: είναι η σειρά της οθόνης «Χρήστες»,
/// και το μάτι ξέρει πού να ψάξει τον καθένα.
List<Operator> operatorsForAssignment(
  List<Operator> all,
  int? currentAssigneeId,
) {
  return [
    for (final operator in all)
      if (operator.isActive ||
          (currentAssigneeId != null && operator.id == currentAssigneeId))
        operator,
  ];
}

/// Το όνομα ενός προφίλ όπως γράφεται σε λίστα επιλογής.
///
/// Το επίθημα μπαίνει μία φορά — αν το όνομα το κουβαλά ήδη, δεν διπλασιάζεται.
String operatorChoiceLabel(Operator operator) {
  if (operator.isActive) return operator.displayName;
  if (operator.displayName.endsWith(kOperatorDisabledSuffix)) {
    return operator.displayName;
  }
  return '${operator.displayName}$kOperatorDisabledSuffix';
}
