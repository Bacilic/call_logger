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

/// «Αφαίρεση από τον χάρτη»: αφαίρεση τμήματος από το τρέχον φύλλο κατόψης.
Future<bool> showBuildingMapRemoveDepartmentConfirmDialog(
  BuildContext context, {
  required String departmentName,
}) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Αφαίρεση από τον χάρτη'),
      content: Text(
        'Να αφαιρεθεί το τμήμα «$departmentName» από αυτό το φύλλο κατόψης;',
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
