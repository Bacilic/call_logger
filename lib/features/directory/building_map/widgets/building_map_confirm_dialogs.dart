import 'package:flutter/material.dart';

/// Απλοί διάλογοι επιβεβαίωσης (ναι/όχι) του χάρτη κτιρίου.
/// Όλοι επιστρέφουν false σε ακύρωση/κλείσιμο.

/// «Επικάλυψη»: το ορθογώνιο σχεδίασης πέφτει πάνω σε άλλο τμήμα.
Future<bool> showBuildingMapOverlapConfirmDialog(BuildContext context) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Επικάλυψη'),
      content: const Text(
        'Το ορθογώνιο επικαλύπτει άλλο τμήμα σε αυτό το φύλλο. Να συνεχιστεί;',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Συνέχεια'),
        ),
      ],
    ),
  );
  return go ?? false;
}

/// «Αφαίρεση από τον χάρτη»: αφαίρεση τμήματος από το τρέχον φύλλο κάτοψης.
Future<bool> showBuildingMapRemoveDepartmentConfirmDialog(
  BuildContext context, {
  required String departmentName,
}) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Αφαίρεση από τον χάρτη'),
      content: Text(
        'Να αφαιρεθεί το τμήμα «$departmentName» από αυτό το φύλλο κάτοψης;',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Αφαίρεση'),
        ),
      ],
    ),
  );
  return go ?? false;
}

/// Τι διάλεξε ο χρήστης για τμήμα που είναι ήδη σχεδιασμένο σε άλλον όροφο.
enum BuildingMapMappedDepartmentChoice {
  /// Μετάβαση στον όροφο όπου βρίσκεται, για επεξεργασία εκεί.
  goToItsFloor,

  /// Μετακίνηση του τμήματος στον τρέχοντα όροφο.
  moveToCurrentFloor,
}

/// «Ήδη σχεδιασμένο αλλού»: επιλογή τμήματος που έχει θέση σε άλλον όροφο.
/// Επιστρέφει `null` σε ακύρωση/κλείσιμο.
Future<BuildingMapMappedDepartmentChoice?>
showBuildingMapMappedDepartmentChoiceDialog(
  BuildContext context, {
  required String departmentName,
  required String itsFloorLabel,
  required String currentFloorLabel,
}) {
  return showDialog<BuildingMapMappedDepartmentChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Το τμήμα είναι ήδη σχεδιασμένο'),
      content: Text(
        'Το τμήμα «$departmentName» είναι σχεδιασμένο στον όροφο «$itsFloorLabel».',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Άκυρο'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            ctx,
            BuildingMapMappedDepartmentChoice.moveToCurrentFloor,
          ),
          child: Text('Μετακίνηση στον όροφο «$currentFloorLabel»'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            ctx,
            BuildingMapMappedDepartmentChoice.goToItsFloor,
          ),
          child: Text('Μετάβαση στον όροφο «$itsFloorLabel»'),
        ),
      ],
    ),
  );
}

/// «Μετακίνηση σε άλλον όροφο»: η Επιβεβαίωση (✓) πρόκειται να μετακομίσει
/// τμήμα που έχει αποθηκευμένη θέση σε άλλο φύλλο.
Future<bool> showBuildingMapMovePlacementConfirmDialog(
  BuildContext context, {
  required String departmentName,
  required String fromFloorLabel,
  required String toFloorLabel,
}) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Μετακίνηση σε άλλον όροφο'),
      content: Text(
        'Το τμήμα «$departmentName» είναι σχεδιασμένο στον όροφο «$fromFloorLabel». '
        'Αν συνεχίσεις, θα αφαιρεθεί από εκεί και θα πάρει τη νέα θέση στον όροφο «$toFloorLabel».',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Μετακίνηση'),
        ),
      ],
    ),
  );
  return go ?? false;
}

/// «Εντοπισμός μέσω υπαλλήλου»: ο εξοπλισμός δεν έχει τμήμα — άλμα στον
/// υπάλληλο που τον κατέχει.
Future<bool> showBuildingMapJumpToUserConfirmDialog(
  BuildContext context, {
  required String userDisplayName,
}) async {
  final approved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Εντοπισμός μέσω υπαλλήλου'),
      content: Text(
        'Δεν έχει οριστεί τμήμα για τον εξοπλισμό. Επιθυμείτε εντοπισμό του υπαλλήλου $userDisplayName;',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Συνέχεια'),
        ),
      ],
    ),
  );
  return approved ?? false;
}
