/// Τι χάνει μια καρτέλα όταν το Είδος της τη βγάζει από την κάτοψη.
///
/// Το κτίριο, ο όροφος και η θέση στον χάρτη αφορούν **τον χάρτη του
/// νοσοκομείου**. Μόλις μια καρτέλα πάρει Είδος που δεν ανήκει εκεί (εταιρεία,
/// εξωτερική μονάδα), τα τρία αυτά παύουν να έχουν νόημα — αλλά έμεναν
/// γραμμένα: η φόρμα τα έκρυβε και η λίστα του Καταλόγου τα έδειχνε, οπότε η
/// καρτέλα έλεγε «εκτός κάτοψης» και ο κατάλογος από δίπλα έδειχνε όροφο.
///
/// Καθαρή κρίση: καμία πρόσβαση σε βάση, κανένα widget.
class BuildingMapPlacementLoss {
  const BuildingMapPlacementLoss({
    this.building,
    this.floorLabel,
    this.group,
    this.hasShape = false,
  });

  /// Τίποτα προς απώλεια — η συνηθισμένη περίπτωση.
  static const none = BuildingMapPlacementLoss();

  /// Το κτίριο που θα σβηστεί· `null` όταν δεν υπάρχει.
  final String? building;

  /// Ο όροφος όπως τον λέει ο κατάλογος κατόψεων· `null` όταν δεν υπάρχει.
  final String? floorLabel;

  /// Η ομάδα του επιλογέα χάρτη· `null` όταν δεν υπάρχει.
  final String? group;

  /// True όταν η καρτέλα έχει σχεδιασμένο σχήμα πάνω στην κάτοψη.
  final bool hasShape;

  /// True όταν υπάρχει έστω ένα από τα τρία — μόνο τότε ρωτιέται ο χρήστης.
  bool get hasAnything =>
      building != null || floorLabel != null || group != null || hasShape;
}

/// Τι θα χαθεί με την αποθήκευση, δεδομένου του Είδους που επιλέχθηκε.
///
/// Όταν το Είδος ανήκει στον χάρτη δεν χάνεται τίποτα: η κρίση επιστρέφει
/// [BuildingMapPlacementLoss.none] και η αποθήκευση προχωρά αθόρυβα.
BuildingMapPlacementLoss judgeBuildingMapPlacementLoss({
  required bool kindBelongsOnMap,
  required String? building,
  required String? floorLabel,
  required double? mapWidth,
  required double? mapHeight,
  String? group,
}) {
  if (kindBelongsOnMap) return BuildingMapPlacementLoss.none;

  final trimmedBuilding = building?.trim();
  final trimmedFloor = floorLabel?.trim();
  final trimmedGroup = group?.trim();
  return BuildingMapPlacementLoss(
    building: (trimmedBuilding == null || trimmedBuilding.isEmpty)
        ? null
        : trimmedBuilding,
    floorLabel: (trimmedFloor == null || trimmedFloor.isEmpty)
        ? null
        : trimmedFloor,
    group: (trimmedGroup == null || trimmedGroup.isEmpty) ? null : trimmedGroup,
    // Σχήμα υπάρχει μόνο με πραγματικές διαστάσεις: το μηδέν σημαίνει
    // «δεν σχεδιάστηκε ποτέ», όχι «σχεδιάστηκε και είναι αόρατο».
    hasShape: (mapWidth ?? 0) > 0 && (mapHeight ?? 0) > 0,
  );
}

/// Το κείμενο της προειδοποίησης — απαριθμεί **μόνο ό,τι υπάρχει**.
///
/// Το άρθρο δένει με τη λέξη «καρτέλα», ποτέ με το όνομα: τα ονόματα των
/// τμημάτων μένουν άκλιτα μέσα στα εισαγωγικά τους και έχουν κάθε γένος.
String buildingMapPlacementLossMessage({
  required String departmentName,
  required String kindLabel,
  required BuildingMapPlacementLoss loss,
}) {
  final lines = <String>[
    'Η καρτέλα «$departmentName» παίρνει Είδος «$kindLabel», που δεν ανήκει '
        'στον χάρτη του νοσοκομείου.',
    '',
    'Με την αποθήκευση θα διαγραφούν:',
    if (loss.building != null) '• Κτίριο: ${loss.building}',
    if (loss.floorLabel != null) '• Όροφος: ${loss.floorLabel}',
    if (loss.group != null) '• Ομάδα: ${loss.group}',
    if (loss.hasShape) '• Η θέση στην κάτοψη',
    '',
    'Αν αργότερα γυρίσετε το Είδος σε τμήμα του νοσοκομείου, θα χρειαστεί να '
        'τα ορίσετε ξανά.',
  ];
  return lines.join('\n');
}
