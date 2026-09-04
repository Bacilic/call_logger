import 'server_session_messages.dart';

/// Κατάσταση συνεδρίας στον διακομιστή, όπως τη δίνει το API των Windows.
enum ServerSessionState {
  /// Κάποιος δουλεύει τώρα.
  active,

  /// Η συνεδρία ζει, αλλά κανείς δεν βλέπει την οθόνη της.
  disconnected,

  /// Κάθε άλλη κατάσταση (ακρόαση, αρχικοποίηση, τερματισμός…).
  other,
}

extension ServerSessionStateLabel on ServerSessionState {
  String get label => switch (this) {
    ServerSessionState.active => 'Ενεργός',
    ServerSessionState.disconnected => 'Σε αναμονή',
    ServerSessionState.other => 'Άλλη κατάσταση',
  };
}

/// Οι τιμές του `WTS_CONNECTSTATE_CLASS`.
///
/// Μας ενδιαφέρουν μόνο δύο: ενεργή (0) και αποσυνδεδεμένη (4). Οτιδήποτε
/// άλλο είναι συνεδρία υπηρεσίας ή μεταβατική κατάσταση — δεν την προσφέρουμε
/// για τερματισμό.
ServerSessionState serverSessionStateFromWts(int raw) => switch (raw) {
  0 => ServerSessionState.active,
  4 => ServerSessionState.disconnected,
  _ => ServerSessionState.other,
};

/// Μία συνεδρία χρήστη πάνω στον διακομιστή.
class ServerSession {
  const ServerSession({
    required this.sessionId,
    required this.username,
    required this.state,
    this.stationName = '',
    this.winStationName = '',
  });

  final int sessionId;

  /// Ο λογαριασμός που έχει ανοίξει τη συνεδρία (π.χ. `nslpathall`).
  final String username;

  final ServerSessionState state;

  /// Το όνομα του υπολογιστή από τον οποίο άνοιξε η συνεδρία (π.χ. `PC3414`).
  ///
  /// Κενό όταν ο διακομιστής δεν το δίνει — τότε απλώς δεν ξέρουμε, και δεν
  /// προτείνουμε τίποτα με βάση αυτό.
  final String stationName;

  /// Το κανάλι (π.χ. `RDP-Tcp#641`) — μόνο για εμφάνιση.
  final String winStationName;

  /// Συνεδρίες που έχει νόημα να τερματιστούν.
  bool get isLogoffCandidate =>
      state != ServerSessionState.other && username.trim().isNotEmpty;
}

/// Το αποτέλεσμα μιας ερώτησης προς τον διακομιστή.
///
/// Ένα από τα δύο: είτε [ok] με [sessions], είτε [error] με ελληνικό μήνυμα.
/// Ποτέ και τα δύο — ένα μισοσυμπληρωμένο αποτέλεσμα θα έδειχνε άδεια λίστα
/// σαν να μην υπάρχουν συνεδρίες.
class ServerSessionsResult {
  const ServerSessionsResult._({
    required this.ok,
    required this.sessions,
    required this.error,
  });

  const ServerSessionsResult.success(List<ServerSession> sessions)
    : this._(ok: true, sessions: sessions, error: null);

  const ServerSessionsResult.failure(String error)
    : this._(ok: false, sessions: const [], error: error);

  final bool ok;
  final List<ServerSession> sessions;
  final String? error;
}

/// Το αποτέλεσμα ενός τερματισμού ή μιας αποσύνδεσης οθόνης.
class SessionLogoffResult {
  const SessionLogoffResult._({
    required this.ok,
    required this.error,
    this.code = 0,
  });

  const SessionLogoffResult.success() : this._(ok: true, error: null);
  const SessionLogoffResult.failure(String error, {int code = 0})
    : this._(ok: false, error: error, code: code);

  final bool ok;
  final String? error;

  /// Ο κωδικός των Windows· 0 όταν πέτυχε ή όταν δεν προήλθε από το σύστημα.
  final int code;

  /// Ο διακομιστής μας δέχτηκε, αλλά αρνήθηκε την ενέργεια.
  ///
  /// Δεν είναι παροδικό: αφορά τα δικαιώματα του λογαριασμού σε **αυτόν** τον
  /// διακομιστή, οπότε η ίδια ενέργεια θα ξανααποτύχει σε κάθε συνεδρία του.
  /// Γι' αυτό η οθόνη σταματά να την προσφέρει, αντί να αφήνει τον χειριστή να
  /// τη δοκιμάζει ξανά και ξανά νομίζοντας ότι φταίει η συνεδρία.
  bool get isAccessDenied =>
      !ok && code == ServerSessionMessages.errorAccessDenied;
}

/// Κατάσταση του «SMB 1.0/CIFS Client» σε **αυτόν** τον υπολογιστή.
enum Smb1ClientStatus {
  /// Εγκατεστημένο και σε λειτουργία.
  running,

  /// Εγκατεστημένο αλλά σταματημένο.
  installedNotRunning,

  /// Δεν υπάρχει καθόλου.
  missing,

  /// Δεν μπορέσαμε να το διαπιστώσουμε.
  unknown,
}

extension Smb1ClientStatusText on Smb1ClientStatus {
  String get label => switch (this) {
    Smb1ClientStatus.running =>
      'SMB 1.0/CIFS Client: ενεργοποιημένο και σε λειτουργία.',
    Smb1ClientStatus.installedNotRunning =>
      'SMB 1.0/CIFS Client: εγκατεστημένο αλλά δεν εκτελείται — αν οι '
          'διακομιστές δεν απαντούν, χρειάζεται επανεκκίνηση του υπολογιστή.',
    Smb1ClientStatus.missing =>
      'SMB 1.0/CIFS Client: ΔΕΝ είναι ενεργοποιημένο. Οι παλιοί διακομιστές '
          '(Windows Server 2003) δεν θα απαντούν. Άνοιξε τις δυνατότητες των '
          'Windows, τσέκαρε ΜΟΝΟ το «Πελάτης SMB 1.0/CIFS» και κάνε '
          'επανεκκίνηση.',
    Smb1ClientStatus.unknown =>
      'SMB 1.0/CIFS Client: δεν ήταν δυνατός ο έλεγχος σε αυτόν τον υπολογιστή.',
  };

  bool get isProblem =>
      this == Smb1ClientStatus.missing ||
      this == Smb1ClientStatus.installedNotRunning;
}
