// Ζώνες μαζικής διαγραφής εξοπλισμού — καθαρή λογική, χωρίς UI.
//
// Το κριτήριο εδώ δεν είναι «τι θα ρωτηθεί» (ο εξοπλισμός δεν ρωτά τίποτα)
// αλλά «τι αφήνει πίσω του»: εξοπλισμός με κλήσεις ή ανοιχτές εκκρεμότητες
// αξίζει ένα δεύτερο βλέμμα, ο υπόλοιπος όχι.

import 'equipment_deletion_summary.dart';

class EquipmentDeletionZones {
  const EquipmentDeletionZones({
    required this.withTraces,
    required this.withoutTraces,
  });

  factory EquipmentDeletionZones.from(
    List<EquipmentDeletionSummary> summaries,
  ) {
    final withTraces = <EquipmentDeletionSummary>[];
    final withoutTraces = <EquipmentDeletionSummary>[];
    for (final s in summaries) {
      if (s.hasTraces) {
        withTraces.add(s);
      } else {
        withoutTraces.add(s);
      }
    }
    return EquipmentDeletionZones(
      withTraces: withTraces,
      withoutTraces: withoutTraces,
    );
  }

  /// Έχει κλήσεις ιστορικού ή εκκρεμότητες — δείχνεται αναλυτικά.
  final List<EquipmentDeletionSummary> withTraces;

  /// Κανένα ίχνος χρήσης — συμπτύσσεται.
  final List<EquipmentDeletionSummary> withoutTraces;

  /// Οι επικεφαλίδες έχουν νόημα μόνο όταν υπάρχει κάτι να ξεχωρίσουν.
  bool get showsZoneHeaders =>
      withTraces.isNotEmpty && withoutTraces.isNotEmpty;

  String get withTracesHeader =>
      'Με ιστορικό ή ανοιχτές εκκρεμότητες (${withTraces.length})';

  /// Γραμμή για όσους δεν αφήνουν τίποτα πίσω — `null` όταν δεν υπάρχουν.
  String? get withoutTracesHeader {
    final count = withoutTraces.length;
    if (count <= 0) return null;
    if (count == 1) {
      return '1 εξοπλισμός χωρίς κανένα ίχνος χρήσης';
    }
    return '$count εξοπλισμοί χωρίς κανένα ίχνος χρήσης';
  }
}
