/// Μπορεί να δημιουργηθεί φάκελος αντιγράφων σε αυτή τη διαδρομή **τώρα**;
///
/// **Ένας κριτής για μία ερώτηση.** Ως τώρα την απαντούσαν δύο: ένας σύγχρονος
/// που κοίταζε μόνο γράμματα δίσκου, και ο έλεγχος ρυθμισμένων διαδρομών που
/// κοίταζε και το δίκτυο. Οι διάλογοι ρωτούσαν τον πρώτο, οπότε σε δικτυακή
/// διαδρομή εκτός δικτύου πρόσφεραν «Δημιουργία εδώ» — μια ενέργεια που η
/// εφαρμογή ήδη ήξερε ότι θα αποτύχει.
///
/// Ο έλεγχος είναι **ασύγχρονος με όριο χρόνου**: σε άφταστο δικτυακό τόμο τα
/// Windows απαντούν μετά από δευτερόλεπτα, και ένας σύγχρονος έλεγχος θα
/// πάγωνε τη διεπαφή για όλο αυτό το διάστημα.
library;

import 'dart:io';

import 'backup_location_hints.dart';

/// Μέγιστη αναμονή για την απάντηση του δικτύου.
///
/// Ίδιο μέγεθος με τον έλεγχο ρυθμισμένων διαδρομών: ο χρήστης περιμένει τον
/// διάλογο, και τρία δευτερόλεπτα είναι το όριο πέρα από το οποίο η σιωπή
/// μοιάζει με κόλλημα.
const Duration kBackupDestinationProbeTimeout = Duration(seconds: 3);

/// Γιατί δεν μπορεί (ή μπορεί) να δημιουργηθεί ο φάκελος εκεί.
enum BackupDestinationReachability {
  /// Η διαδρομή είναι προσβάσιμη — η δημιουργία έχει νόημα να προταθεί.
  creatable,

  /// Γράμμα δίσκου που δεν υπάρχει ή δεν είναι συνδεδεμένο.
  volumeMissing,

  /// Δικτυακή διαδρομή που δεν απαντά: κομμένο δίκτυο, σβηστός διακομιστής,
  /// ή κοινόχρηστος φάκελος που δεν υπάρχει πια.
  networkUnreachable;

  /// Μόνο η [creatable] επιτρέπει να προσφερθεί δημιουργία φακέλου.
  bool get canCreateFolder => this == BackupDestinationReachability.creatable;
}

/// Η ρίζα ενός δικτυακού κοινόχρηστου, δηλαδή `\\διακομιστής\κοινόχρηστο`.
///
/// Επιστρέφει `null` όταν η διαδρομή δεν είναι δικτυακή. Ο έλεγχος γίνεται
/// στη **ρίζα** και όχι σε ολόκληρη τη διαδρομή, γιατί οι ενδιάμεσοι φάκελοι
/// μπορεί όντως να λείπουν και να είναι δημιουργήσιμοι· εκείνο που δεν
/// δημιουργείται ποτέ από εμάς είναι ο ίδιος ο κοινόχρηστος.
String? uncShareRoot(String path) {
  final normalized = path.trim().replaceAll('/', r'\');
  if (!normalized.startsWith(r'\\')) return null;
  final parts = normalized
      .substring(2)
      .split(r'\')
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length < 2) return null;
  return r'\\' '${parts[0]}' r'\' '${parts[1]}';
}

/// Ο έλεγχος. Το [probeDirectoryExists] υπάρχει για τα τεστ — αλλιώς ρωτιέται
/// το πραγματικό σύστημα αρχείων.
Future<BackupDestinationReachability> probeBackupDestinationReachability(
  String path, {
  Duration timeout = kBackupDestinationProbeTimeout,
  Future<bool> Function(String path)? probeDirectoryExists,
}) async {
  final trimmed = path.trim();
  // Κενή διαδρομή: δεν υπάρχει τίποτα να αποκλειστεί — ο καλών έχει άλλο
  // μήνυμα γι' αυτήν («δεν έχει οριστεί φάκελος»).
  if (trimmed.isEmpty) return BackupDestinationReachability.creatable;

  final share = uncShareRoot(trimmed);
  if (share != null) {
    final probe = probeDirectoryExists ?? _directoryExists;
    try {
      final reachable = await probe(share).timeout(timeout);
      return reachable
          ? BackupDestinationReachability.creatable
          : BackupDestinationReachability.networkUnreachable;
    } catch (_) {
      // Εξαίρεση ή λήξη χρόνου: για το «τώρα, σε αυτό το μηχάνημα» ο
      // κοινόχρηστος δεν είναι προσβάσιμος.
      return BackupDestinationReachability.networkUnreachable;
    }
  }

  // Τοπική διαδρομή: το γράμμα του δίσκου απαντά αμέσως, χωρίς δίκτυο.
  return BackupLocationHints.volumeOfPathExists(trimmed)
      ? BackupDestinationReachability.creatable
      : BackupDestinationReachability.volumeMissing;
}

Future<bool> _directoryExists(String path) => Directory(path).exists();
