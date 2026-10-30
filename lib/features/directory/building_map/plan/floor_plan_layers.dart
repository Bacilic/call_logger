import '../../../../core/models/floor_plan_placement.dart';
import 'floor_plan_objects.dart';

/// Οι στρώσεις του χάρτη: μία για κάθε τύπο εγγραφής του Καταλόγου
/// (υπάλληλοι, τηλέφωνα, εξοπλισμός) και μία για κάθε είδος αντικειμένου.
/// Το κλειδί κάθε στρώσης γράφεται στην προσωπική ρύθμιση των κρυμμένων.

/// Η στρώση ενός τύπου του Καταλόγου.
String floorPlanPlacementLayer(FloorPlanPlacementType type) => type.key;

/// Η στρώση ενός είδους αντικειμένων.
String floorPlanKindLayer(int kindId) => 'kind:$kindId';

/// Σε ποια στρώση ανήκει το σύμβολο· `null` όταν δεν ανήκει σε καμία (π.χ.
/// αντικείμενο χωρίς γνωστό είδος) — τότε φαίνεται πάντα.
String? floorPlanLayerOf(FloorPlanObjectView view) {
  final type = view.placementType;
  if (type != null) return floorPlanPlacementLayer(type);
  final kind = view.kindId;
  return kind == null ? null : floorPlanKindLayer(kind);
}

/// Τα σύμβολα χωρίς όσα ανήκουν σε κρυμμένη στρώση. Το [keep] (π.χ. ό,τι
/// βρήκε η αναζήτηση) φαίνεται πάντα.
List<FloorPlanObjectView> visibleFloorPlanLayers(
  List<FloorPlanObjectView> views,
  Set<String> hidden, {
  ({FloorPlanItemSource source, int id})? keep,
}) {
  if (hidden.isEmpty) return views;
  return [
    for (final v in views)
      if ((v.source == keep?.source && v.id == keep?.id) ||
          !hidden.contains(floorPlanLayerOf(v)))
        v,
  ];
}
