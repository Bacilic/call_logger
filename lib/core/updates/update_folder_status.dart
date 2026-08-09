import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/greek_date_format.dart';
import 'update_manifest.dart';

/// Κατάσταση ενός φακέλου ενημερώσεων ως προς το τι μπορούν να κάνουν οι
/// συνάδελφοι με αυτόν.
enum UpdateFolderState {
  /// Ο φάκελος δεν υπάρχει ή δεν είναι προσβάσιμος.
  unavailable,

  /// Υπάρχει, αλλά δεν έχει δημοσιευτεί ποτέ έκδοση (λείπει το `version.json`).
  noRelease,

  /// Υπάρχει `version.json`, αλλά είναι κατεστραμμένο ή ελλιπές.
  brokenManifest,

  /// Το manifest είναι έγκυρο, αλλά λείπουν αρχεία που το συνοδεύουν.
  incomplete,

  /// Όλα στη θέση τους: εγκατάσταση και ενημέρωση δουλεύουν.
  ready,
}

/// Τι βρέθηκε στον φάκελο ενημερώσεων — και τι λείπει.
///
/// Χωρίς αυτόν τον έλεγχο, ένας φάκελος που χάθηκε ή άδειασε φαίνεται μια χαρά
/// στην κάρτα Δημοσίευσης (υπάρχει και είναι εγγράψιμος), ενώ στην πραγματικότητα
/// **κανείς δεν μπορεί να εγκαταστήσει ή να ενημερωθεί από αυτόν**.
class UpdateFolderStatus {
  const UpdateFolderStatus({
    required this.state,
    this.manifest,
    this.missingParts = const <String>[],
  });

  final UpdateFolderState state;

  /// Το `current/version.json` όταν διαβάστηκε επιτυχώς.
  final UpdateManifest? manifest;

  /// Ονόματα των μερών που λείπουν, σε γλώσσα χρήστη.
  final List<String> missingParts;

  bool get isReady => state == UpdateFolderState.ready;

  /// Μήνυμα μιας πρότασης για το UI. Λέει **τι σημαίνει** η κατάσταση για τους
  /// συναδέλφους, όχι μόνο τι βρέθηκε στον δίσκο.
  String describe() {
    switch (state) {
      case UpdateFolderState.unavailable:
        return 'Ο φάκελος δεν είναι προσβάσιμος.';
      case UpdateFolderState.noRelease:
        return 'Ο φάκελος δεν περιέχει δημοσιευμένη έκδοση — κανείς δεν '
            'μπορεί να εγκαταστήσει ή να ενημερωθεί από εδώ.';
      case UpdateFolderState.brokenManifest:
        return 'Το αρχείο έκδοσης (current/version.json) είναι κατεστραμμένο '
            'ή ελλιπές — η ενημέρωση δεν θα προσφερθεί σε κανέναν.';
      case UpdateFolderState.incomplete:
        final version = manifest?.version ?? '';
        return 'Η δημοσιευμένη έκδοση $version είναι ελλιπής — λείπει '
            '${_joinGreek(missingParts)}.';
      case UpdateFolderState.ready:
        final m = manifest!;
        return 'Δημοσιευμένη έκδοση ${m.version}+${m.build} '
            '(${formatGreekShortDateFromIso(m.released)}).';
    }
  }

  static String _joinGreek(List<String> parts) {
    if (parts.isEmpty) return 'κάποιο αρχείο';
    if (parts.length == 1) return parts.first;
    return '${parts.sublist(0, parts.length - 1).join(', ')} και ${parts.last}';
  }

}

/// Ελέγχει τι περιέχει ο [folderPath] ως φάκελος ενημερώσεων.
///
/// Ελέγχονται και τα τέσσερα συστατικά που χρειάζονται στην πράξη: το manifest,
/// το πακέτο `.zip` που αυτό δηλώνει, τα αρχεία `current/app` (από εκεί
/// αντιγράφει ο εγκαταστάτης) και ο ίδιος ο `install_call_logger.bat` (χωρίς
/// αυτόν δεν γίνεται η πρώτη εγκατάσταση).
///
/// Κάθε σφάλμα ανάγνωσης καταλήγει σε [UpdateFolderState.unavailable] — ο
/// έλεγχος είναι ενημερωτικός και δεν πρέπει ποτέ να ρίξει εξαίρεση στο UI.
///
/// Το I/O γίνεται με **σύγχρονες** κλήσεις (όπως και ο έλεγχος εγκυρότητας
/// φακέλου): οι ασύγχρονες παραλλαγές κρεμούν τα `testWidgets` με εικονικό
/// χρόνο. Πρόκειται για λίγα stat και μία μικρή ανάγνωση.
Future<UpdateFolderStatus> inspectUpdateFolder(String folderPath) async {
  try {
    final folder = folderPath.trim();
    if (folder.isEmpty || !Directory(folder).existsSync()) {
      return const UpdateFolderStatus(state: UpdateFolderState.unavailable);
    }

    final manifestFile = File(p.join(folder, 'current', 'version.json'));
    if (!manifestFile.existsSync()) {
      return const UpdateFolderStatus(state: UpdateFolderState.noRelease);
    }

    UpdateManifest? manifest;
    try {
      manifest = UpdateManifest.fromJson(
        jsonDecode(manifestFile.readAsStringSync()),
      );
    } catch (_) {
      manifest = null;
    }
    if (manifest == null) {
      return const UpdateFolderStatus(state: UpdateFolderState.brokenManifest);
    }

    final missing = <String>[];
    final zip = File(p.join(folder, 'current', manifest.zipFile));
    if (!zip.existsSync()) {
      missing.add('το πακέτο ενημέρωσης (${manifest.zipFile})');
    }
    final appExe = File(p.join(folder, 'current', 'app', 'call_logger.exe'));
    if (!appExe.existsSync()) {
      missing.add('τα αρχεία εγκατάστασης (current/app)');
    }
    final installer = File(p.join(folder, 'install_call_logger.bat'));
    if (!installer.existsSync()) {
      missing.add('ο εγκαταστάτης (install_call_logger.bat)');
    }

    return UpdateFolderStatus(
      state: missing.isEmpty
          ? UpdateFolderState.ready
          : UpdateFolderState.incomplete,
      manifest: manifest,
      missingParts: missing,
    );
  } catch (_) {
    return const UpdateFolderStatus(state: UpdateFolderState.unavailable);
  }
}
