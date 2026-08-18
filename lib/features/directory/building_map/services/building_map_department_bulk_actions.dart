import 'package:flutter/material.dart' show Color;
import 'package:sqflite_common/sqflite.dart';

import '../../../../core/database/building_map_repository.dart';
import '../../../../core/database/department_repository.dart';
import '../../models/department_model.dart';
import '../../screens/widgets/department_color_palette.dart';

/// Μαζικές ενέργειες τμημάτων πάνω σε φύλλο κατόψης — **σε μία συναλλαγή**.
///
/// Γιατί χωριστά από τον διάλογο: ένας βρόχος που καλεί το repository μία φορά
/// ανά τμήμα ανοίγει **δική του συναλλαγή κάθε φορά**. Τοπικά με WAL αυτό δεν
/// φαίνεται ποτέ· σε βάση δικτύου κοστίζει ~76 ms ανά εγγραφή, οπότε είκοσι
/// επιλεγμένα τμήματα γίνονται δευτερόλεπτα αναμονής σε κουμπί που μοιάζει
/// στιγμιαίο. Και το ουσιωδέστερο: μια αποτυχία στη μέση άφηνε τα μισά
/// τμήματα αλλαγμένα και τα μισά όχι.

/// Κρύβει ή εμφανίζει πολλά τμήματα στην κάτοψη, μέσα στο [txn].
Future<void> setDepartmentsHiddenOnMapInTxn(
  DatabaseExecutor txn, {
  required DepartmentRepository repository,
  required Iterable<int> departmentIds,
  required bool hidden,
}) async {
  for (final id in departmentIds) {
    await repository.updateDepartment(id, {
      'map_hidden': hidden ? 1 : 0,
    }, executor: txn);
  }
}

/// Αφαιρεί πολλά τμήματα από το τρέχον φύλλο κατόψης, μέσα στο [txn].
///
/// Επιστρέφει τα χρώματα που **ελευθερώθηκαν**, χωρίς να πειράξει το μητρώο
/// χρωμάτων. Η αποδέσμευσή τους ανήκει στον καλούντα και γίνεται **μετά** την
/// επιτυχή ολοκλήρωση: το μητρώο ζει στη μνήμη και δεν γυρίζει πίσω μαζί με τη
/// συναλλαγή — αν το πειράζαμε εδώ, μια αποτυχία θα άφηνε την εφαρμογή να
/// θεωρεί ελεύθερα χρώματα που στη βάση είναι ακόμη πιασμένα.
Future<List<Color>> removeDepartmentsFromFloorInTxn(
  DatabaseExecutor txn, {
  required DepartmentRepository repository,
  required Iterable<DepartmentModel> departments,
}) async {
  final releasedColors = <Color>[];
  for (final d in departments) {
    final id = d.id;
    if (id == null) continue;
    final removedColor = tryParseDepartmentHex(d.color);
    await repository.updateDepartment(
      id,
      BuildingMapRepository.clearedBuildingMapPlacementColumns(
        clearFloorId: true,
        clearDepartmentHex: true,
      ),
      executor: txn,
    );
    if (removedColor != null) releasedColors.add(removedColor);
  }
  return releasedColors;
}
