import 'dart:io';

import '../database/database_init_result.dart';
import '../services/startup_asset_integrity_service.dart';

/// Δομικός έλεγχος αρχείων της εφαρμογής, πριν από κάθε έλεγχο βάσης.
///
/// Το συμβόλαιο: **κάθε δομικός έλεγχος αρχείων της εφαρμογής προηγείται κάθε
/// ελέγχου βάσης· μοιραία έλλειψη τερματίζει τη διάγνωση, μη μοιραία δεν την
/// τερματίζει αλλά προηγείται στην αναφορά.**
///
/// Η μοιραία περίπτωση (λείπει ο φάκελος `data`, το `icudtl.dat`, το
/// `flutter_assets` ή ο κώδικας) κόβεται πριν από τη μηχανή Flutter, στο
/// `wWinMain` — δεν φτάνει ποτέ εδώ. Εδώ κρίνεται μόνο η **μερική** ζημιά:
/// η εφαρμογή λειτουργεί, αλλά ο χρήστης πρέπει να μάθει γιατί βλέπει κουτάκια
/// αντί για εικονίδια — και να το μάθει **πριν** από οποιοδήποτε μήνυμα βάσης.

/// Τα ελλείποντα κρίσιμα αρχεία, ή κενή λίστα όταν δεν τρέχουμε από εγκατάσταση.
///
/// Αν λείπει ολόκληρη η ρίζα `flutter_assets`, δεν βρισκόμαστε σε πραγματική
/// εγκατάσταση (τεστ, εργαλεία): σε εγκατάσταση η εφαρμογή δεν θα είχε καν
/// ξεκινήσει. Τότε δεν έχουμε τίποτα αξιόπιστο να αναφέρουμε.
List<String> detectMissingApplicationFiles([
  StartupAssetIntegrityService? assetIntegrity,
]) {
  final service = assetIntegrity ?? StartupAssetIntegrityService();
  if (!Directory(service.flutterAssetsDirectory).existsSync()) {
    return const <String>[];
  }
  return service.findMissingCriticalAssets();
}

/// Ανεβάζει τα ελλείποντα αρχεία εφαρμογής **πάνω** από το σφάλμα βάσης.
///
/// Σε επιτυχή βάση το αποτέλεσμα μένει ανέπαφο: η μερική ζημιά δεν εμποδίζει
/// την εκκίνηση και ανακοινώνεται με τη λωρίδα ειδοποίησης του κελύφους.
DatabaseInitResult withMissingApplicationFilesFirst(
  DatabaseInitResult base,
  List<String> missingApplicationFiles,
) {
  if (missingApplicationFiles.isEmpty) return base;
  if (base.isSuccess) return base;

  final filesLine =
      'Λείπουν ή έχουν αλλοιωθεί αρχεία της εφαρμογής: '
      '${missingApplicationFiles.join(', ')}. '
      'Συνιστάται επανεγκατάσταση.';
  final databaseLine = base.message?.trim() ?? '';
  if (databaseLine.isEmpty) return base.copyWith(message: filesLine);

  return base.copyWith(message: '1) $filesLine\n2) $databaseLine');
}
