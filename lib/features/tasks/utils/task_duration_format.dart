String _unit(int value, String singular, String plural) =>
    '$value ${value == 1 ? singular : plural}';

/// Διαίρεση με στρογγυλοποίηση στον πλησιέστερο ακέραιο.
int _roundedDiv(int value, int divisor) => (value + divisor ~/ 2) ~/ divisor;

String _pair(
  int major,
  String majorSingular,
  String majorPlural,
  int minor,
  String minorSingular,
  String minorPlural,
) {
  final head = _unit(major, majorSingular, majorPlural);
  if (minor == 0) return head;
  return '$head και ${_unit(minor, minorSingular, minorPlural)}';
}

/// Ανθρώπινο διάστημα με **δύο** το πολύ μονάδες: ημέρες-ώρες, ώρες-λεπτά ή
/// λεπτά-δευτερόλεπτα.
///
/// Ό,τι κρύβεται στρογγυλοποιείται στην πλησιέστερη ορατή μονάδα, και το
/// κρατούμενο ανεβαίνει σωστά — «23 ώρες, 59 λεπτά και 40 δευτερόλεπτα» γίνεται
/// «1 μέρα», ποτέ «24 ώρες».
String twoUnitDuration(Duration duration) {
  final seconds = duration.inSeconds.abs();

  if (seconds < 60) {
    return _unit(seconds, 'δευτερόλεπτο', 'δευτερόλεπτα');
  }
  if (seconds < Duration.secondsPerHour) {
    return _pair(
      seconds ~/ 60,
      'λεπτό',
      'λεπτά',
      seconds % 60,
      'δευτερόλεπτο',
      'δευτερόλεπτα',
    );
  }
  if (seconds < Duration.secondsPerDay) {
    final minutes = _roundedDiv(seconds, 60);
    if (minutes >= Duration.minutesPerDay) {
      return twoUnitDuration(Duration(minutes: minutes));
    }
    return _pair(minutes ~/ 60, 'ώρα', 'ώρες', minutes % 60, 'λεπτό', 'λεπτά');
  }
  final hours = _roundedDiv(seconds, Duration.secondsPerHour);
  return _pair(hours ~/ 24, 'μέρα', 'μέρες', hours % 24, 'ώρα', 'ώρες');
}

/// Πόσο απομένει ως τη λήξη, ή πόσο έχει περάσει από τότε.
///
/// Και οι δύο διατυπώσεις έχουν υποκείμενο την εκκρεμότητα, ώστε να μη
/// χρειάζεται συμφωνία με το ουσιαστικό («Απομένουν 1 ώρα»).
String dueRelativeLabel(DateTime now, DateTime due) {
  final diff = due.difference(now);
  if (diff.inSeconds.abs() < 60) return 'Λήγει τώρα';
  final text = twoUnitDuration(diff);
  return diff.isNegative ? 'Εκκρεμεί $text' : 'Λήγει σε $text';
}

/// Ανθρώπινη μορφοποίηση διαστήματος χρόνου για εκκρεμότητες.
String durationSince(DateTime from, DateTime to) {
  var diff = to.difference(from);
  if (diff.isNegative) diff = Duration.zero;

  var totalMinutes = diff.inMinutes;
  if (totalMinutes <= 0) totalMinutes = 1;

  final days = totalMinutes ~/ (24 * 60);
  final hours = (totalMinutes % (24 * 60)) ~/ 60;
  final minutes = totalMinutes % 60;

  if (days > 0) {
    if (hours > 0 && minutes > 0) {
      return '$days μ. $hours ώρες και $minutes λεπτά';
    }
    if (hours > 0) return '$days μ. και $hours ώρες';
    if (minutes > 0) return '$days μ. και $minutes λεπτά';
    return '$days μ.';
  }
  if (hours > 0 && minutes > 0) return '$hours ώρες και $minutes λεπτά';
  if (hours > 0) return '$hours ώρες';
  return '$minutes λεπτά';
}
