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
