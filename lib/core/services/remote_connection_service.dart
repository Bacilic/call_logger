import 'dart:io';

import 'settings_service.dart';

/// Υπηρεσία υποστήριξης απομακρυσμένων συνδέσεων (VNC, AnyDesk).
/// Διαχειρίζεται την εύρεση έγκυρων διαδρομών, έλεγχο δικτύου (VNC port) και εκκίνηση διεργασιών.
class RemoteConnectionService {
  RemoteConnectionService(this._settings);

  final SettingsService _settings;

  /// Επιστρέφει τη ρυθμισμένη διαδρομή VNC αν υπάρχει στο δίσκο.
  /// Επιστρέφει null αν η διαδρομή είναι κενή ή το αρχείο δεν υπάρχει.
  Future<String?> getValidVncPath() async {
    final p = await _settings.getVncPath();
    final trimmed = p.trim();
    if (trimmed.isEmpty) return null;
    if (File(trimmed).existsSync()) return trimmed;
    return null;
  }

  /// Επιστρέφει τη διαδρομή AnyDesk αν το αρχείο υπάρχει στο δίσκο.
  /// Διαβάζει το [anydeskPath] από τις ρυθμίσεις και ελέγχει με [File.existsSync].
  /// Επιστρέφει το path αν υπάρχει, αλλιώς null.
  /// Χρήσιμο πριν την εκκίνηση του AnyDesk ώστε να επιβεβαιώνεται η ύπαρξη του εκτελέσιμου.
  Future<String?> getValidAnydeskPath() async {
    final path = await _settings.getAnydeskPath();
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;
    if (File(trimmed).existsSync()) return trimmed;
    return null;
  }

  /// Ελέγχει αν το VNC port (5900) είναι ανοιχτό στο [host].
  /// Προσπαθεί σύνδεση με timeout 1,5 s· σε οποιοδήποτε σφάλμα επιστρέφει false.
  Future<bool> _isVncPortOpen(String host) async {
    try {
      final socket = await Socket.connect(
        host,
        5900,
        timeout: const Duration(milliseconds: 1500),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Εκκινεί το TightVNC Viewer για σύνδεση στο [target] (hostname ή IP).
  /// Ελέγχει ύπαρξη executable, ανοιχτό port 5900 και κατόπιν ξεκινά τη διεργασία (detached).
  /// Πετάει [Exception] αν δεν βρεθεί VNC ή ο στόχος δεν απαντά.
  Future<void> launchVnc(String target) async {
    final path = await getValidVncPath();
    if (path == null) {
      throw Exception('Δεν βρέθηκε εγκατάσταση TightVNC στις ρυθμισμένες διαδρομές.');
    }

    final portOpen = await _isVncPortOpen(target);
    if (!portOpen) {
      throw Exception('Ο υπολογιστής $target δεν απαντά ή το VNC δεν τρέχει (Port 5900).');
    }

    final password = await _settings.getVncPassword();
    final List<String> arguments = password.trim().isEmpty
        ? [target]
        : [target, '-password=$password'];

    await Process.start(path, arguments, mode: ProcessStartMode.detached);
  }

  /// Εκκινεί το AnyDesk για σύνδεση με το [targetId] (AnyDesk ID).
  /// Πετάει [Exception] αν δεν βρεθεί εγκατάσταση AnyDesk.
  Future<void> launchAnydesk(String targetId) async {
    final path = await getValidAnydeskPath();
    if (path == null) {
      throw Exception('Δεν βρέθηκε εγκατάσταση AnyDesk. Ελέγξτε τις ρυθμίσεις.');
    }

    await Process.start(path, [targetId], mode: ProcessStartMode.detached);
  }
}
