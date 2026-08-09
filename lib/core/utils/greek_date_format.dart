/// Ελληνικές σύντομες μορφές ημερομηνίας — ένα σπίτι για όλες.
///
/// Ο λόγος που υπάρχουν δύο γραφές της ημέρας: τα γραφήματα και τα chips θέλουν
/// κεφαλαία («ΠΕΜ»), το τρέχον κείμενο θέλει κανονική γραφή («Πεμ»). Το
/// περιεχόμενο όμως είναι το ίδιο και ζει σε ένα σημείο.
library;

const List<String> _weekdayShortElUpper = [
  'ΔΕΥ',
  'ΤΡΙ',
  'ΤΕΤ',
  'ΠΕΜ',
  'ΠΑΡ',
  'ΣΑΒ',
  'ΚΥΡ',
];

const List<String> _weekdayShortElTitle = [
  'Δευ',
  'Τρι',
  'Τετ',
  'Πεμ',
  'Παρ',
  'Σαβ',
  'Κυρ',
];

/// Ιούνιος και Ιούλιος δεν ξεχωρίζουν με τρία γράμματα — παίρνουν τέσσερα, όπως
/// σε κάθε ελληνικό ημερολόγιο.
const List<String> _monthShortEl = [
  'Ιαν',
  'Φεβ',
  'Μαρ',
  'Απρ',
  'Μαι',
  'Ιουν',
  'Ιουλ',
  'Αυγ',
  'Σεπ',
  'Οκτ',
  'Νοε',
  'Δεκ',
];

/// Τρίγραμμο ημέρας εβδομάδας στα ελληνικά, κεφαλαία — «ΠΕΜ».
String weekdayShortEl(DateTime date) => _weekdayShortElUpper[date.weekday - 1];

/// Τρίγραμμο ημέρας με κεφαλαίο μόνο το πρώτο γράμμα — «Πεμ».
String weekdayShortElTitle(DateTime date) =>
    _weekdayShortElTitle[date.weekday - 1];

/// Σύντομο όνομα μήνα στα ελληνικά — «Αυγ».
String monthShortEl(DateTime date) => _monthShortEl[date.month - 1];

/// Ημερομηνία σε ελληνική σύντομη μορφή — «Τετ 05 - Αυγ - 2026».
///
/// Η ημέρα της εβδομάδας μπαίνει μπροστά επίτηδες: η σύγκριση «σήμερα Τετάρτη,
/// αυτό βγήκε Τρίτη» γίνεται με το μάτι, ενώ με γυμνούς αριθμούς θέλει λογισμό.
String formatGreekShortDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  return '${weekdayShortElTitle(date)} $day - ${monthShortEl(date)} - ${date.year}';
}

/// Το ίδιο από ημερομηνία σε μορφή `yyyy-MM-dd`.
///
/// Ό,τι δεν αναγνωρίζεται επιστρέφεται αυτούσιο: το κείμενο έρχεται από αρχείο
/// έκδοσης που μπορεί να γραφτεί λάθος, και μια αλλοιωμένη ημερομηνία είναι πιο
/// χρήσιμη στην οθόνη από ένα κενό.
String formatGreekShortDateFromIso(String isoDate) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(isoDate.trim());
  if (match == null) return isoDate;

  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final parsed = DateTime(year, month, day);

  // Ο κατασκευαστής του [DateTime] δεν παραπονιέται για «2026-13-45»: το κυλά
  // σε 14 Φεβρουαρίου 2027. Μια ημερομηνία που δεν υπάρχει πρέπει να φανεί ως
  // έχει, όχι να μεταμφιεστεί σε άλλη που μοιάζει σωστή.
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return isoDate;
  }
  return formatGreekShortDate(parsed);
}
