import 'dart:io';

import 'settings_service.dart';

/// Υπηρεσία εκκίνησης AnyDesk και VNC Viewer χωρίς παραμέτρους (κενή εφαρμογή).
/// Διαβάζει διαδρομές από [SettingsService], ελέγχει ύπαρξη εκτελέσιμου και τρέχει Process με κενή λίστα ορισμάτων.
class RemoteLauncherService {
  RemoteLauncherService(this._settings);

  final SettingsService _settings;

  /// Αποτέλεσμα ελέγχου διαδρομής: έγκυρη διαδρομή ή ακριβές μήνυμα σφάλματος.
  static const String errorPathNotSet = 'Η διαδρομή δεν ορίζεται.';
  static const String errorPathOrFileInvalid = 'Η διαδρομή είναι λάθος ή το αρχείο δεν βρέθηκε.';
  static const String errorAccessDenied = 'Δεν επιτρέπεται η πρόσβαση ή χρειάζονται δικαιώματα.';

  /// Επιστρέφει τη διαδρομή AnyDesk αν το αρχείο υπάρχει, αλλιώς null.
  Future<String?> getValidAnydeskPath() async {
    final status = await getAnydeskStatus();
    return status.path;
  }

  /// Επιστρέφει (διαδρομή, μήνυμα σφάλματος) για AnyDesk. Αν path != null το κουμπί είναι ενεργό.
  Future<({String? path, String? errorReason})> getAnydeskStatus() async {
    final path = await _settings.getAnydeskPath();
    final trimmed = path.trim();
    if (trimmed.isEmpty) return (path: null, errorReason: errorPathNotSet);
    try {
      if (File(trimmed).existsSync()) return (path: trimmed, errorReason: null);
      return (path: null, errorReason: errorPathOrFileInvalid);
    } catch (_) {
      return (path: null, errorReason: errorAccessDenied);
    }
  }

  /// Επιστρέφει τη διαδρομή VNC αν το αρχείο υπάρχει, αλλιώς null.
  Future<String?> getValidVncPath() async {
    final status = await getVncStatus();
    return status.path;
  }

  /// Επιστρέφει (διαδρομή, μήνυμα σφάλματος) για VNC. Αν path != null το κουμπί είναι ενεργό.
  Future<({String? path, String? errorReason})> getVncStatus() async {
    final path = await _settings.getVncPath();
    final trimmed = path.trim();
    if (trimmed.isEmpty) return (path: null, errorReason: errorPathNotSet);
    try {
      if (File(trimmed).existsSync()) return (path: trimmed, errorReason: null);
      return (path: null, errorReason: errorPathOrFileInvalid);
    } catch (_) {
      return (path: null, errorReason: errorAccessDenied);
    }
  }

  /// Εκκινεί το AnyDesk χωρίς παραμέτρους (κενή εφαρμογή).
  /// Πετάει [Exception] αν η διαδρομή δεν υπάρχει ή το αρχείο δεν βρέθηκε.
  Future<void> launchAnydeskEmpty() async {
    final path = await getValidAnydeskPath();
    if (path == null) {
      throw Exception('Δεν βρέθηκε εγκατάσταση AnyDesk. Ελέγξτε τις ρυθμίσεις.');
    }
    await Process.start(path, [], mode: ProcessStartMode.detached);
  }

  /// Εκκινεί το VNC Viewer χωρίς παραμέτρους (κενή εφαρμογή).
  /// Πετάει [Exception] αν η διαδρομή δεν υπάρχει ή το αρχείο δεν βρέθηκε.
  Future<void> launchVncEmpty() async {
    final path = await getValidVncPath();
    if (path == null) {
      throw Exception('Δεν βρέθηκε εγκατάσταση VNC. Ελέγξτε τις ρυθμίσεις.');
    }
    await Process.start(path, [], mode: ProcessStartMode.detached);
  }
}
