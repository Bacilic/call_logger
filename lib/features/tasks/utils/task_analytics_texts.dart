import '../models/task_analytics_summary.dart';

/// Τα κείμενα του παραθύρου «Αναφορές Εκκρεμοτήτων»: μέση διάρκεια,
/// ετικέτες προέλευσης και η κάρτα συμπεράσματος. Καθαροί υπολογισμοί, έξω
/// από την οθόνη, ώστε να ελέγχονται με τεστ.

/// Μέσος χρόνος ολοκλήρωσης: «2 ώρ. 15 λ.» ή «40 λ.».
String formatTaskAnalyticsDuration(double seconds) {
  final sec = seconds.isNaN ? 0 : seconds.round().clamp(0, 31536000);
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  if (h > 0) return '$h ώρ. $m λ.';
  return '${m.clamp(0, 59)} λ.';
}

/// Η ελληνική ετικέτα ενός καναλιού προέλευσης εκκρεμότητας.
String taskAnalyticsOriginLabel(String origin) {
  return switch (origin) {
    'call_linked' => 'Από κλήση',
    'manual_fab' => 'Χειροκίνητη',
    'quick_add' => 'Γρήγορη προσθήκη',
    'legacy' => 'Παλαιές εγγραφές',
    _ => 'Άγνωστη προέλευση',
  };
}

/// Η κάρτα συμπεράσματος. Η μεταβολή της τελευταίας ημέρας λέγεται με τη
/// λέξη που της ταιριάζει — και το μηδέν «έμεινε σταθερό», όχι «αυξήθηκε
/// κατά 0» (απόφαση Διευθυντή 17/10/2026).
String buildTaskAnalyticsInsight({
  required int backlogLastDelta,
  required double overdueRateActive,
  TaskAnalyticsOriginSlice? dominantOrigin,
}) {
  final trend = switch (backlogLastDelta) {
    0 => 'έμεινε σταθερό',
    > 0 => 'αυξήθηκε κατά $backlogLastDelta',
    _ => 'μειώθηκε κατά ${backlogLastDelta.abs()}',
  };
  final originText = dominantOrigin == null
      ? 'δεν υπάρχει κυρίαρχο κανάλι προέλευσης'
      : 'κυρίαρχη προέλευση: '
            '${taskAnalyticsOriginLabel(dominantOrigin.origin)} '
            '(${dominantOrigin.percent.toStringAsFixed(1)}%)';
  return 'Το υπόλοιπο εκκρεμοτήτων $trend στην τελευταία ημέρα του εύρους. '
      'Ο δείκτης καθυστερήσεων στις ενεργές εκκρεμότητες είναι '
      '${overdueRateActive.toStringAsFixed(1)}%, ενώ $originText.';
}
