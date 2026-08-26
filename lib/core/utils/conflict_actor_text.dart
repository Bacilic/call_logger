/// Το «ποιος και πότε» ενός διαλόγου διένεξης, γραμμένο μία φορά.
///
/// Κάθε φρουρός μπαγιάτικης εγγραφής ανοίγει την ίδια πρόταση: «Ο χρήστης «Χ»
/// <έκανε κάτι> στις 13:10.» Το υποκείμενο και ο χρόνος είναι πάντα ίδια — μόνο
/// το ρήμα αλλάζει ανά οντότητα. Όσο ήταν αντιγραμμένα, μια διόρθωση στη
/// διατύπωση έπρεπε να γίνει σε κάθε αντίγραφο και το τελευταίο ξεχνιόταν.
library;

import '../services/current_operator.dart';

/// «Ο χρήστης «Βασίλης»» — ή «Κάποιος άλλος» όταν το Ιστορικό δεν απαντά.
///
/// Η παύλα του [CurrentOperator.unknownAuditName] **δεν** είναι όνομα: είναι
/// η σφραγίδα «δεν ξέρουμε ποιος». Όσο περνούσε ως κανονική τιμή, ο διάλογος
/// έγραφε «Ο χρήστης «—»» — κατηγορούσε κάποιον ενώ η εφαρμογή αγνοούσε, και
/// ο άγνωστος μπορεί κάλλιστα να ήταν ο ίδιος ο χρήστης που διαβάζει.
String conflictActorName(String? changedBy) {
  final trimmed = (changedBy ?? '').trim();
  if (trimmed.isEmpty || trimmed == CurrentOperator.unknownAuditName) {
    return 'Κάποιος άλλος';
  }
  return 'Ο χρήστης «$trimmed»';
}

/// « στις 13:10» — με ημερομηνία όταν δεν είναι σήμερα, κενό όταν δεν ξέρουμε.
///
/// Το σκέτο «στις 18:00» για κάτι που έγινε προχθές είναι παραπλανητικό: ο
/// αναγνώστης το διαβάζει ως σημερινό και ψάχνει ποιος δούλευε τότε.
String conflictMomentSuffix(DateTime? changedAt, {required DateTime now}) {
  if (changedAt == null) return '';
  String two(int value) => value.toString().padLeft(2, '0');
  final time = '${two(changedAt.hour)}:${two(changedAt.minute)}';
  final sameDay =
      changedAt.year == now.year &&
      changedAt.month == now.month &&
      changedAt.day == now.day;
  return sameDay
      ? ' στις $time'
      : ' στις ${two(changedAt.day)}/${two(changedAt.month)} $time';
}
