import 'package:flutter/material.dart';

import '../../../calls/models/user_model.dart';

/// Επιλογή τμήματος στο άλμα αναζήτησης: αναγνωριστικό + έτοιμη ετικέτα.
typedef BuildingMapDepartmentOption = ({int id, String label});

/// «Επιλογή υπαλλήλου»: όταν ο εξοπλισμός ανήκει σε περισσότερους από έναν.
/// Επιστρέφει null σε ακύρωση.
Future<UserModel?> showBuildingMapUserPickDialog(
  BuildContext context, {
  required List<UserModel> users,
}) {
  return showDialog<UserModel>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Επιλογή υπαλλήλου'),
      children: [
        for (final user in users)
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(user),
            child: Text(
              user.name?.trim().isNotEmpty == true ? user.name! : 'Χωρίς όνομα',
            ),
          ),
      ],
    ),
  );
}

/// «Επιλογή τμήματος»: όταν το άλμα καταλήγει σε περισσότερα από ένα τμήματα.
/// Επιστρέφει το αναγνωριστικό του επιλεγμένου ή null σε ακύρωση.
Future<int?> showBuildingMapDepartmentPickDialog(
  BuildContext context, {
  required List<BuildingMapDepartmentOption> options,
}) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Επιλογή τμήματος'),
      children: [
        for (final option in options)
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(option.id),
            child: Text(option.label),
          ),
      ],
    ),
  );
}
