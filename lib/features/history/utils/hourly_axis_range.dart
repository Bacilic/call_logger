import '../models/dashboard_summary_model.dart';

/// Το ορατό εύρος ωρών του διαγράμματος «Κατανομή ανά ώρα».
class HourlyAxisRange {
  const HourlyAxisRange({required this.firstHour, required this.lastHour});

  final int firstHour;
  final int lastHour;

  int get span => lastHour - firstHour + 1;

  bool contains(int hour) => hour >= firstHour && hour <= lastHour;
}

const int _lastHourOfDay = 23;

/// Κόβει τις κενές ώρες στα άκρα, κρατώντας μία ώρα ανάσα εκατέρωθεν.
///
/// Ο άξονας ακολουθεί αποκλειστικά τα δεδομένα — δεν ξέρει τίποτα για ωράρια,
/// οπότε αν προστεθεί απογευματινή βάρδια απλώνεται μόνος του. Το [minSpan]
/// εμποδίζει μια ήσυχη μέρα να δείξει άξονα τριών ωρών με μία γιγάντια μπάρα.
///
/// Χωρίς καμία κλήση επιστρέφει ολόκληρη τη μέρα: δεν υπάρχει τίποτα να
/// δείξει, οπότε το να κρύψει αυθαίρετα ώρες θα ήταν παραπλανητικό.
HourlyAxisRange visibleHourRange(
  List<HourlyBucket> buckets, {
  int minSpan = 8,
}) {
  final withCalls = buckets.where((b) => b.callCount > 0).toList();
  if (withCalls.isEmpty) {
    return const HourlyAxisRange(firstHour: 0, lastHour: _lastHourOfDay);
  }

  var first = withCalls.first.hour;
  var last = withCalls.first.hour;
  for (final bucket in withCalls) {
    if (bucket.hour < first) first = bucket.hour;
    if (bucket.hour > last) last = bucket.hour;
  }

  // Μία ώρα ανάσα, ώστε η πρώτη και η τελευταία μπάρα να μην ακουμπούν το άκρο.
  if (first > 0) first--;
  if (last < _lastHourOfDay) last++;

  var expandLeft = true;
  while (last - first + 1 < minSpan && (first > 0 || last < _lastHourOfDay)) {
    if (expandLeft && first > 0) {
      first--;
    } else if (last < _lastHourOfDay) {
      last++;
    } else {
      first--;
    }
    expandLeft = !expandLeft;
  }

  return HourlyAxisRange(firstHour: first, lastHour: last);
}
