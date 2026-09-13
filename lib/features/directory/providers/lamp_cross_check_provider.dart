import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/old_database/lamp_cross_check_snapshot.dart';
import '../../../core/database/old_database/lamp_settings_store.dart';
import '../../../core/services/settings_service.dart';
import '../models/lamp_cross_check_rules.dart';

/// Οι διακόπτες της διασταύρωσης για την ΕΝΕΡΓΗ βάση.
///
/// Ζουν στο `app_settings`, άρα η cache είναι database-scoped: ακυρώνεται
/// στην αλλαγή βάσης και μετά από κάθε αποθήκευση στην οθόνη.
final lampCrossCheckRulesProvider = FutureProvider<LampCrossCheckRules>((
  ref,
) async {
  final raw = await SettingsService().catalogs.getLampCrossCheckRulesRaw();
  return LampCrossCheckRules.fromRawJson(raw);
});

/// Ο τελευταίος κωδικός εξοπλισμού που ξέρει η Λάμπα.
///
/// Η οθόνη τον δείχνει δίπλα στον έλεγχο «δεν υπάρχει στη Λάμπα», ώστε να
/// φαίνεται πού σταματά το μητρώο και γιατί τα καινούργια μηχανήματα δεν
/// βγαίνουν ποτέ ως ευρήματα. `null` όταν η Λάμπα δεν είναι διαθέσιμη — τότε
/// η ετικέτα απλώς λείπει.
final lampLastEquipmentCodeProvider = FutureProvider<int?>((ref) async {
  final path = await LampSettingsStore().getReadPath();
  if (path == null) return null;
  return readLampLastEquipmentCode(path);
});
