import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';
import '../database/database_v1_schema.dart';
import '../services/app_instance_registry.dart';
import '../services/settings_service.dart';

/// Κατάσταση αντιγράφων της εφαρμογής, έτοιμη για προβολή.
class AppInstancesStatus {
  const AppInstancesStatus({
    required this.all,
    required this.currentExecutablePath,
    required this.shouldNotify,
  });

  static const empty = AppInstancesStatus(
    all: <AppInstanceRecord>[],
    currentExecutablePath: '',
    shouldNotify: false,
  );

  /// Όλα τα αντίγραφα που έχουν τρέξει, νεότερο πρώτο.
  final List<AppInstanceRecord> all;

  final String currentExecutablePath;

  /// True όταν υπάρχουν άλλα αντίγραφα ΚΑΙ ο χρήστης δεν έχει ήδη κλείσει τη
  /// λωρίδα για αυτό ακριβώς το σύνολο διαδρομών.
  final bool shouldNotify;

  List<AppInstanceRecord> get others =>
      AppInstanceRegistry.others(all, currentExecutablePath);

  bool get isSharedWithOthers => others.isNotEmpty;

  bool isCurrent(AppInstanceRecord record) =>
      record.executablePath.trim().toLowerCase() ==
      currentExecutablePath.trim().toLowerCase();
}

/// Καταγράφει το τρέχον αντίγραφο και επιστρέφει την κατάσταση του μητρώου.
///
/// Τρέχει μία φορά ανά εκκίνηση. Σε υπολογιστή με μία εγκατάσταση το μητρώο
/// μένει μονοστοιχείο και το [AppInstancesStatus.shouldNotify] ποτέ αληθές.
final appInstancesProvider = FutureProvider<AppInstancesStatus>((ref) async {
  final settings = SettingsService();

  String executablePath;
  try {
    executablePath = Platform.resolvedExecutable;
  } catch (_) {
    return AppInstancesStatus.empty;
  }
  if (executablePath.trim().isEmpty) return AppInstancesStatus.empty;

  var version = '';
  try {
    version = (await PackageInfo.fromPlatform()).version;
  } catch (_) {
    // Η έκδοση είναι συμπληρωματική πληροφορία — η καταγραφή προχωρά χωρίς αυτήν.
  }

  final updated = AppInstanceRegistry.touch(
    known: await settings.getKnownAppInstances(),
    executablePath: executablePath,
    version: version,
    now: DateTime.now(),
    // Η έκδοση σχήματος που ΞΕΡΕΙ αυτό το εκτελέσιμο: με αυτήν, όταν άλλο
    // (παλαιότερο) αντίγραφο βρει βάση νεότερης έκδοσης, μπορεί να υποδείξει
    // με βεβαιότητα ποιο εκτελέσιμο τη διαβάζει.
    schemaVersion: databaseSchemaVersionV1,
  );
  await settings.setKnownAppInstances(updated);

  final others = AppInstanceRegistry.others(updated, executablePath);
  final dismissed = await settings.getDismissedAppInstancesSignature();
  final signature = AppInstanceRegistry.signature(updated);

  return AppInstancesStatus(
    all: updated,
    currentExecutablePath: executablePath,
    shouldNotify: others.isNotEmpty && dismissed != signature,
  );
});

/// Κλείνει τη λωρίδα για το τρέχον σύνολο διαδρομών (ξαναχτυπά σε νέο αντίγραφο).
Future<void> dismissAppInstancesNotice(WidgetRef ref) async {
  final status = ref.read(appInstancesProvider).value;
  if (status == null) return;
  await SettingsService().setDismissedAppInstancesSignature(
    AppInstanceRegistry.signature(status.all),
  );
  ref.invalidate(appInstancesProvider);
}

/// Εξηγεί **γιατί** τα αντίγραφα της λίστας μοιράζονται δεδομένα, και τι θα
/// τα χώριζε.
///
/// Το μητρώο αντιγράφων αποθηκεύεται με πρόθεμα προφίλ
/// (`profile_<όνομα>_known_app_instances`), οπότε κάθε προφίλ βλέπει **μόνο**
/// τις δικές του εκτελέσεις. Δεν χρειάζεται λοιπόν ένδειξη προφίλ ανά γραμμή:
/// όλες οι γραμμές έχουν εξ ορισμού το ίδιο προφίλ με την τρέχουσα εκτέλεση.
/// Αυτό όμως πρέπει να το πει το κείμενο — αλλιώς ο χρήστης δεν έχει τρόπο να
/// ξέρει ότι λείπουν αντίγραφα άλλων προφίλ.
///
/// Το [activeProfile] είναι `null` (ή κενό) όταν η εκτέλεση γίνεται χωρίς
/// `--profile`, δηλαδή στα κοινά δεδομένα.
String appInstancesSharedScopeText(String? activeProfile) {
  final name = activeProfile?.trim() ?? '';
  if (name.isEmpty) {
    return 'Αυτά τα εκτελέσιμα μοιράζονται τις ίδιες ρυθμίσεις και την ίδια '
        'επιλογή βάσης, επειδή κανένα δεν τρέχει με προφίλ. Για ανεξάρτητη '
        'λειτουργία, εκτελέστε με --profile <όνομα>.';
  }
  return 'Αυτά τα εκτελέσιμα μοιράζονται τις ίδιες ρυθμίσεις και την ίδια '
      'επιλογή βάσης, επειδή τρέχουν όλα με το προφίλ «$name». Εκτελέσεις με '
      'άλλο προφίλ — ή χωρίς προφίλ — είναι ανεξάρτητες και δεν εμφανίζονται '
      'εδώ.';
}

/// Το ίδιο κείμενο για το τρέχον προφίλ της εκτέλεσης.
String currentAppInstancesSharedScopeText() =>
    appInstancesSharedScopeText(AppConfig.activeProfile);
