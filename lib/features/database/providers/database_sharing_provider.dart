import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/operator_presence_repository.dart';

/// Έχει ανοίξει αυτή η βάση από περισσότερους από έναν υπολογιστές;
///
/// Το αυθεντικό κριτήριο της κοινοχρησίας: όχι η διαδρομή του αρχείου (τυφλή σε
/// συνδεδεμένο γράμμα δίσκου) ούτε το όνομα που της έδωσε ο χρήστης, αλλά τα
/// **ίχνη σύνδεσης** που κρατά η ίδια η βάση — ένα ανά υπολογιστή, γραμμένα
/// αυτόματα, χωρίς διαγραφή.
///
/// Ψευδές όταν δεν μπορεί να απαντηθεί: η άγνοια πέφτει στην πλευρά που δεν
/// ισχυρίζεται τίποτα.
final databaseIsSharedProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    final db = await DatabaseHelper.instance.database;
    return await OperatorPresenceRepository(db).countDistinctStations() > 1;
  } catch (_) {
    return false;
  }
});
