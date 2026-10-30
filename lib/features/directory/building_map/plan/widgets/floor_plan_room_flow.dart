import 'package:flutter/material.dart';

import '../../../../../core/database/floor_plan_repository.dart';
import '../../../../../core/models/building_map_floor.dart';
import '../../../models/department_model.dart';
import '../../services/building_map_floor_ordering.dart';
import '../floor_plan_room_department_rule.dart';
import '../services/floor_plan_catalog.dart';
import 'floor_plan_room_identity_dialog.dart';

/// Η ταυτότητα που θα γραφτεί σε έναν χώρο.
typedef RoomIdentityChoice = ({String? name, int? departmentId});

/// Ρωτά τι είναι ο χώρος και εφαρμόζει τον κανόνα ορόφου του τμήματος.
///
/// Επιστρέφει τι πρέπει να γραφτεί στον χώρο· `null` όταν ο χώρος **δεν**
/// δημιουργείται ή δεν αλλάζει (ακύρωση, ή «Παραμονή» του τμήματος στον όροφό
/// του). Η μεταφορά του τμήματος σε άλλον όροφο γράφεται στον Κατάλογο εδώ,
/// πριν από τον χώρο.
Future<RoomIdentityChoice?> chooseRoomIdentity(
  BuildContext context, {
  required FloorPlanCatalog catalog,
  required FloorPlanRepository repository,
  required BuildingMapFloor floor,
  required String title,
  required void Function(String message) inform,
  int? currentDepartmentId,
  String? currentName,
}) async {
  final List<DepartmentModel> departments;
  final List<BuildingMapFloor> floors;
  try {
    departments = await catalog.departments();
    floors = await catalog.floors();
  } catch (e) {
    inform('Τα τμήματα δεν διαβάστηκαν: $e');
    return null;
  }
  if (!context.mounted) return null;

  final identity = await showFloorPlanRoomIdentityDialog(
    context,
    departments: departments,
    title: title,
    currentDepartmentId: currentDepartmentId,
    currentName: currentName,
  );
  if (identity == null || !context.mounted) return null;
  final department = identity.department;
  if (department == null) return (name: identity.name, departmentId: null);
  final departmentId = department.id;
  if (departmentId == null) return null;
  if (departmentId == currentDepartmentId) {
    return (name: null, departmentId: departmentId);
  }

  String floorName(int? id) {
    for (final f in floors) {
      if (f.id == id) return buildingMapFloorDisplayLabel(f);
    }
    return 'άγνωστος όροφος';
  }

  final outcome = resolveRoomDepartment(
    targetFloorId: floor.id,
    catalogFloorId: department.floorId,
    floorsWithRoom: await repository.floorsWithRoomOfDepartment(departmentId),
  );
  if (!context.mounted) return null;
  final here = floorName(floor.id);
  final there = floorName(department.floorId);

  switch (outcome) {
    case RoomDepartmentOutcome.create:
      return (name: null, departmentId: departmentId);
    case RoomDepartmentOutcome.createAlsoElsewhereOnFloor:
      inform(
        'Το τμήμα «${department.name}» έχει ήδη χώρο σε αυτόν τον όροφο· '
        'σχεδιάστηκε και δεύτερος.',
      );
      return (name: null, departmentId: departmentId);
    case RoomDepartmentOutcome.createAndAssignFloor:
      await catalog.moveDepartmentToFloor(departmentId, floor.id);
      inform(
        'Το τμήμα «${department.name}» δεν είχε όροφο· στον Κατάλογο '
        'γράφτηκε «$here».',
      );
      return (name: null, departmentId: departmentId);
    case RoomDepartmentOutcome.askMoveOrStay:
      final move = await _askMoveOrStay(
        context,
        department: department,
        here: here,
        there: there,
        hasOldBoxThere:
            (department.mapFloor?.trim().isNotEmpty ?? false) &&
            department.mapFloor!.trim() != '${floor.id}',
      );
      if (move != true) return null;
      await catalog.moveDepartmentToFloor(departmentId, floor.id);
      inform('Το τμήμα «${department.name}» μεταφέρθηκε στον όροφο «$here».');
      return (name: null, departmentId: departmentId);
    case RoomDepartmentOutcome.stayOnly:
      if (context.mounted) {
        await _explainStayOnly(
          context,
          department: department,
          here: here,
          there: there,
        );
      }
      return null;
  }
}

/// `true` = μεταφορά στον όροφο του χάρτη, `false`/`null` = παραμονή.
Future<bool?> _askMoveOrStay(
  BuildContext context, {
  required DepartmentModel department,
  required String here,
  required String there,
  required bool hasOldBoxThere,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Το τμήμα «${department.name}» είναι σε άλλον όροφο'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Στον Κατάλογο το τμήμα βρίσκεται στον όροφο «$there». Ο χάρτης '
            'και ο Κατάλογος πρέπει να συμφωνούν.',
          ),
          if (hasOldBoxThere) ...[
            const SizedBox(height: 12),
            Text(
              'Με τη μεταφορά φεύγει και το κουτάκι του από τον παλιό χάρτη '
              'του ορόφου «$there».',
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Παραμονή στον όροφο «$there»'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Μεταφορά του τμήματος στον όροφο «$here»'),
        ),
      ],
    ),
  );
}

Future<void> _explainStayOnly(
  BuildContext context, {
  required DepartmentModel department,
  required String here,
  required String there,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Το τμήμα «${department.name}» έχει χώρο σε άλλον όροφο'),
      content: Text(
        'Το τμήμα έχει ήδη χώρο στον όροφο «$there», όπου το γράφει και ο '
        'Κατάλογος. Η μεταφορά του εδώ θα άφηνε εκείνον τον χώρο ασύμφωνο, '
        'γι\' αυτό ο χώρος στον όροφο «$here» δεν δημιουργείται.\n\n'
        'Για χώρο σε άλλον όροφο χρειάζεται ξεχωριστό τμήμα με δικό του '
        'όνομα (π.χ. «Οφθαλμολογική - κλινική»).',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Παραμονή στον όροφο «$there»'),
        ),
      ],
    ),
  );
}
