import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/department_repository.dart';
import '../../../core/services/settings_service_catalogs.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/homoglyph_text_normalizer.dart';

/// Ο κατάλογος κτιρίων της ΕΝΕΡΓΗΣ βάσης, έτοιμος για τα πεδία επιλογής.
///
/// **Γιατί δεν διαβάζεται κατευθείαν από τη ρύθμιση:** μέχρι να οριστεί
/// κατάλογος, ο πίνακας των τμημάτων είναι η μόνη αλήθεια για το ποια κτίρια
/// υπάρχουν. Χωρίς αυτή την εφεδρεία, η φόρμα τμήματος θα άνοιγε με άδεια
/// λίστα σε βάση γεμάτη κτίρια — και η πρώτη αποθήκευση θα έσβηνε την τιμή.
///
/// Η cache είναι database-scoped: ακυρώνεται στην αλλαγή βάσης
/// (`invalidateDatabaseScopedCaches`) και μετά από κάθε αλλαγή του καταλόγου.
final buildingCatalogProvider = FutureProvider<List<String>>((ref) async {
  final stored = await SettingsService().catalogs.getBuildingCatalogList();
  if (stored.isNotEmpty) return sortBuildings(stored);
  final usage = await ref.watch(buildingUsageProvider.future);
  return sortBuildings(usage.perBuilding.keys);
});

/// Πόσα ενεργά τμήματα ανήκουν σε κάθε κτίριο (και πόσα σε κανένα) — η βάση
/// της οθόνης διαχείρισης: «τόσα θα μείνουν χωρίς κτίριο αν το σβήσεις».
final buildingUsageProvider = FutureProvider<BuildingUsage>((ref) async {
  final db = await DatabaseHelper.instance.database;
  return DepartmentRepository(db).countDepartmentsPerBuilding();
});

/// Ο κατάλογος ομάδων της ΕΝΕΡΓΗΣ βάσης, έτοιμος για τα πεδία επιλογής.
///
/// Ίδια εφεδρεία με τα κτίρια, και για τον ίδιο λόγο: μέχρι να οριστεί
/// κατάλογος, οι ομάδες που ήδη χρησιμοποιούν τα τμήματα είναι η μόνη αλήθεια.
/// Χωρίς αυτό, η φόρμα θα άνοιγε με άδεια λίστα σε βάση γεμάτη ομάδες — και η
/// πρώτη αποθήκευση θα έσβηνε την τιμή.
final departmentGroupCatalogProvider = FutureProvider<List<String>>((
  ref,
) async {
  final stored = await SettingsService().catalogs
      .getDepartmentGroupCatalogList();
  if (stored.isNotEmpty) return sortDepartmentGroups(stored);
  final usage = await ref.watch(departmentGroupUsageProvider.future);
  return sortDepartmentGroups(usage.perGroup.keys);
});

/// Πόσα τμήματα του χάρτη ανήκουν σε κάθε ομάδα (και πόσα σε καμία).
final departmentGroupUsageProvider = FutureProvider<DepartmentGroupUsage>((
  ref,
) async {
  final db = await DatabaseHelper.instance.database;
  return DepartmentRepository(db).countDepartmentsPerGroup();
});

/// Αλφαβητική σειρά με τους κανόνες του καταλόγου — ίδια παντού.
List<String> sortDepartmentGroups(Iterable<String> groups) {
  final out = groups.map((g) => g.trim()).where((g) => g.isNotEmpty).toList()
    ..sort(
      (a, b) => HomoglyphTextNormalizer.normalizeForComparison(
        a,
      ).compareTo(HomoglyphTextNormalizer.normalizeForComparison(b)),
    );
  return out;
}

/// Ταξινόμηση κτιρίων για την οθόνη: αλφαβητικά, χωρίς να μετράνε πεζά/κεφαλαία.
List<String> sortBuildings(Iterable<String> buildings) {
  final list =
      buildings.map((b) => b.trim()).where((b) => b.isNotEmpty).toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return list;
}

/// Το κτίριο του καταλόγου που είναι «το ίδιο» με το [candidate], ή `null`.
///
/// Η σύγκριση αγνοεί πεζά/κεφαλαία, τόνους **και** το αλφάβητο: στη Λάμπα το
/// ίδιο κτίριο γράφεται και «Β» και «B». Χρησιμεύει σε δύο σημεία — για να μη
/// μπει διπλότυπο στον κατάλογο, και για να αναγνωριστεί μια αποθηκευμένη τιμή
/// τμήματος ως στοιχείο του καταλόγου.
String? matchBuildingInCatalog(String? candidate, List<String> catalog) {
  final value = candidate?.trim() ?? '';
  if (value.isEmpty) return null;
  final normalized = HomoglyphTextNormalizer.normalizeForComparison(value);
  if (normalized.isEmpty) return null;
  for (final building in catalog) {
    if (HomoglyphTextNormalizer.normalizeForComparison(building) ==
        normalized) {
      return building;
    }
  }
  return null;
}

/// Γράφει τον κατάλογο και επιστρέφει `false` όταν ο χρήστης ακύρωσε επειδή
/// κάποιος άλλος πρόλαβε — ο καλών ξαναδιαβάζει και ρωτά ξανά.
///
/// Ζει εδώ ώστε η οθόνη διαχείρισης και κάθε μελλοντικός καλών να γράφουν από
/// το ίδιο σημείο, με την ίδια μορφοποίηση.
Future<void> writeBuildingCatalog(
  List<String> buildings, {
  required String? expected,
}) async {
  await SettingsService().catalogs.setBuildingCatalog(
    buildings.join(', '),
    expected: expected,
  );
}

/// Το ακατέργαστο κείμενο του καταλόγου — η αφετηρία που κρατά η οθόνη για
/// τον φρουρό διένεξης.
Future<String> readBuildingCatalogRaw() =>
    SettingsService().catalogs.getBuildingCatalogRaw();

/// Τι θα έδειχνε η οθόνη για μια αποθηκευμένη τιμή — ο φρουρός συγκρίνει με
/// αυτό, όχι με το ωμό κείμενο.
String effectiveBuildingCatalogText(String? stored) =>
    SettingsServiceCatalogs.effectiveBuildingCatalog(stored);

// --- Οι ίδιοι τρεις βοηθοί για τις ομάδες, ώστε η οθόνη διαχείρισης να
// --- δουλεύει και τους δύο καταλόγους από το ίδιο σχήμα.

Future<void> writeDepartmentGroupCatalog(
  List<String> groups, {
  required String? expected,
}) async {
  await SettingsService().catalogs.setDepartmentGroupCatalog(
    groups.join(', '),
    expected: expected,
  );
}

Future<String> readDepartmentGroupCatalogRaw() =>
    SettingsService().catalogs.getDepartmentGroupCatalogRaw();

String effectiveDepartmentGroupCatalogText(String? stored) =>
    SettingsServiceCatalogs.effectiveDepartmentGroupCatalog(stored);
