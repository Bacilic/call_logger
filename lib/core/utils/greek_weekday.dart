const List<String> _weekdayShortEl = [
  'ΔΕΥ',
  'ΤΡΙ',
  'ΤΕΤ',
  'ΠΕΜ',
  'ΠΑΡ',
  'ΣΑΒ',
  'ΚΥΡ',
];

/// Τρίγραμμο ημέρας εβδομάδας στα ελληνικά, κεφαλαία.
String weekdayShortEl(DateTime date) => _weekdayShortEl[date.weekday - 1];
