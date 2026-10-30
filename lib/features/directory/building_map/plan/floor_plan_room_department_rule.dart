/// Τι γίνεται όταν ένας χώρος παίρνει τμήμα — ο κανόνας «ο όροφος του
/// Καταλόγου και ο χάρτης συμφωνούν πάντα» (απόφαση Διευθυντή, ενότητα 4 του
/// σχεδίου).
enum RoomDepartmentOutcome {
  /// Το τμήμα ανήκει ήδη σε αυτόν τον όροφο και δεν έχει άλλον χώρο εδώ.
  create,

  /// Ίδιος όροφος, αλλά το τμήμα έχει ήδη χώρο εδώ: επιτρέπεται, με
  /// ενημέρωση ότι υπάρχει και αλλού.
  createAlsoElsewhereOnFloor,

  /// Το τμήμα δεν έχει όροφο στον Κατάλογο: παίρνει αυτόν, ώστε να
  /// συμφωνούν.
  createAndAssignFloor,

  /// Ο Κατάλογος γράφει άλλον όροφο: ο χρήστης αποφασίζει «Μεταφορά» ή
  /// «Παραμονή».
  askMoveOrStay,

  /// Ο Κατάλογος γράφει άλλον όροφο και το τμήμα **έχει ήδη χώρο εκεί**: η
  /// μεταφορά θα άφηνε εκείνον τον χώρο ασύμφωνο, άρα προσφέρεται μόνο η
  /// παραμονή — ο χώρος εδώ δεν δημιουργείται.
  stayOnly,
}

RoomDepartmentOutcome resolveRoomDepartment({
  required int targetFloorId,
  required int? catalogFloorId,
  required Set<int> floorsWithRoom,
}) {
  if (catalogFloorId == null) return RoomDepartmentOutcome.createAndAssignFloor;
  if (catalogFloorId == targetFloorId) {
    return floorsWithRoom.contains(targetFloorId)
        ? RoomDepartmentOutcome.createAlsoElsewhereOnFloor
        : RoomDepartmentOutcome.create;
  }
  return floorsWithRoom.contains(catalogFloorId)
      ? RoomDepartmentOutcome.stayOnly
      : RoomDepartmentOutcome.askMoveOrStay;
}
