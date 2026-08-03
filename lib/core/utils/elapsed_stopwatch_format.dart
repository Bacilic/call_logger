/// Μορφοποίηση χρονομέτρου εργασίας που τρέχει (π.χ. χτίσιμο έκδοσης).
///
/// Διαφέρει από τη διάρκεια κλήσης ([formatCallDurationSeconds]): εκεί μετράει
/// η ανθρώπινη ανάγνωση μιας ολοκληρωμένης κλήσης, εδώ η αίσθηση ότι κάτι
/// **τρέχει τώρα** — γι' αυτό φαίνονται τα χιλιοστά.
///
/// Τα ψηφία προστίθενται δυναμικά: η μεγαλύτερη μονάδα που εμφανίζεται δεν
/// παίρνει μηδενικά μπροστά, οι επόμενες παίρνουν σταθερό πλάτος ώστε ο
/// αριθμός να μην «χοροπηδά».
///
///     :1 → :999 → 1:001 → 59:999 → 1:01:652 → 23:46:732 → 1:00:00:000
String formatElapsedWithMillis(Duration elapsed) {
  final total = elapsed.isNegative ? Duration.zero : elapsed;
  final millis = total.inMilliseconds.remainder(1000);
  final seconds = total.inSeconds.remainder(60);
  final minutes = total.inMinutes.remainder(60);
  final hours = total.inHours;

  final ms = millis.toString().padLeft(3, '0');
  if (hours > 0) {
    return '$hours:${_pad2(minutes)}:${_pad2(seconds)}:$ms';
  }
  if (minutes > 0) {
    return '$minutes:${_pad2(seconds)}:$ms';
  }
  if (seconds > 0) {
    return '$seconds:$ms';
  }
  return ':$millis';
}

String _pad2(int value) => value.toString().padLeft(2, '0');
