import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'server_session_messages.dart';
import 'server_session_models.dart';
import 'windows_session_ffi.dart';

/// Ερώτηση και τερματισμός συνεδριών σε διακομιστή, με όλους τους ελέγχους.
///
/// Κάθε κλήση ακολουθεί την ίδια αυστηρή σειρά:
/// 1. υπάρχουν στοιχεία διαχειριστή;
/// 2. ανοίγει συνεδρία SMB προς τον διακομιστή με αυτά;
/// 3. γίνεται η δουλειά (απαρίθμηση ή τερματισμός)·
/// 4. **πάντα** κλείνει η συνεδρία, ό,τι κι αν συνέβη.
///
/// Το βήμα 4 δεν είναι ευπρέπεια: μια ξεχασμένη ανοιχτή συνεδρία διαχειριστή
/// σε υπολογιστή γραφείου είναι διάπλατα ανοιχτή πόρτα προς τον διακομιστή.
class ServerSessionService {
  const ServerSessionService();

  /// Πόσο περιμένουμε τον διακομιστή πριν τα παρατήσουμε.
  ///
  /// Οι διακομιστές του 2003 απαντούν σε κλάσματα δευτερολέπτου όταν είναι
  /// υγιείς· όταν δεν είναι, το δίκτυο μπορεί να κρατήσει το αίτημα για λεπτά.
  static const Duration defaultTimeout = Duration(seconds: 25);

  /// Οι συνεδρίες του διακομιστή.
  Future<ServerSessionsResult> listSessions({
    required String host,
    required String adminUser,
    required String adminPassword,
    Duration timeout = defaultTimeout,
  }) async {
    final guard = _guardInputs(
      host: host,
      adminUser: adminUser,
      adminPassword: adminPassword,
    );
    if (guard != null) return ServerSessionsResult.failure(guard);

    final h = host.trim();
    final u = adminUser.trim();

    try {
      final raw = await Isolate.run(
        () => _enumerateInIsolate(h, u, adminPassword),
      ).timeout(timeout);

      if (!raw.ok) {
        return ServerSessionsResult.failure(
          raw.connectFailed
              ? ServerSessionMessages.forConnect(
                  code: raw.code,
                  host: h,
                  account: u,
                )
              : ServerSessionMessages.forEnumerate(
                  code: raw.code,
                  host: h,
                  adminUser: u,
                ),
        );
      }

      final sessions = raw.sessions
          .map(
            (s) => ServerSession(
              sessionId: s.sessionId,
              username: s.username,
              state: serverSessionStateFromWts(s.state),
              stationName: s.stationName,
              winStationName: s.winStationName,
            ),
          )
          .toList();
      return ServerSessionsResult.success(sessions);
    } on TimeoutException {
      return ServerSessionsResult.failure(
        'Ο διακομιστής $h δεν απάντησε μέσα σε ${timeout.inSeconds} '
        'δευτερόλεπτα.',
      );
    } catch (e) {
      return ServerSessionsResult.failure(
        'Απρόσμενο σφάλμα κατά την επικοινωνία με τον $h: $e',
      );
    }
  }

  /// Τερματίζει (logoff) μια συνεδρία.
  ///
  /// Μετά τον τερματισμό **ξαναρωτάει** τον διακομιστή: μόνο η εξαφάνιση της
  /// συνεδρίας από τη λίστα αποδεικνύει ότι έκλεισε. Το API επιστρέφει
  /// επιτυχία μόλις δεχτεί την εντολή, όχι μόλις ολοκληρωθεί.
  Future<SessionLogoffResult> logoff({
    required String host,
    required String adminUser,
    required String adminPassword,
    required int sessionId,
    Duration timeout = defaultTimeout,
  }) async {
    final guard = _guardInputs(
      host: host,
      adminUser: adminUser,
      adminPassword: adminPassword,
    );
    if (guard != null) return SessionLogoffResult.failure(guard);

    final h = host.trim();
    final u = adminUser.trim();

    try {
      final raw = await Isolate.run(
        () => _logoffInIsolate(h, u, adminPassword, sessionId),
      ).timeout(timeout);

      if (!raw.ok) {
        return SessionLogoffResult.failure(
          raw.connectFailed
              ? ServerSessionMessages.forConnect(
                  code: raw.code,
                  host: h,
                  account: u,
                )
              : ServerSessionMessages.forLogoff(
                  code: raw.code,
                  host: h,
                  adminUser: u,
                ),
        );
      }
      return const SessionLogoffResult.success();
    } on TimeoutException {
      return SessionLogoffResult.failure(
        'Ο διακομιστής $h δεν απάντησε μέσα σε ${timeout.inSeconds} '
        'δευτερόλεπτα. Η συνεδρία μπορεί να έκλεισε ή όχι — πάτα «Ανανέωση».',
      );
    } catch (e) {
      return SessionLogoffResult.failure(
        'Απρόσμενο σφάλμα κατά τον τερματισμό στον $h: $e',
      );
    }
  }

  /// Έλεγχοι που δεν χρειάζονται δίκτυο. Επιστρέφει μήνυμα ή `null` όταν όλα καλά.
  static String? _guardInputs({
    required String host,
    required String adminUser,
    required String adminPassword,
  }) {
    if (!Platform.isWindows) {
      return 'Η λειτουργία απαιτεί Windows.';
    }
    if (host.trim().isEmpty) {
      return 'Δεν έχει οριστεί διεύθυνση διακομιστή.';
    }
    if (adminUser.trim().isEmpty) {
      return 'Δεν έχει οριστεί λογαριασμός διαχειριστή για αυτόν τον '
          'διακομιστή. Συμπλήρωσέ τον στον Κατάλογο → Διάφορα → Διακομιστές.';
    }
    if (adminPassword.isEmpty) {
      return 'Δεν έχει αποθηκευτεί κωδικός για τον λογαριασμό '
          '«${adminUser.trim()}». Συμπλήρωσέ τον στον Κατάλογο → Διάφορα → '
          'Διακομιστές.';
    }
    return null;
  }
}

/// Ωμό αποτέλεσμα από το isolate.
///
/// Το [connectFailed] ξεχωρίζει «δεν μπήκαμε καν» από «μπήκαμε αλλά η ενέργεια
/// απέτυχε» — οι δύο περιπτώσεις θέλουν εντελώς διαφορετικό μήνυμα.
typedef _IsolateResult = ({
  bool ok,
  bool connectFailed,
  int code,
  List<RawServerSession> sessions,
});

_IsolateResult _enumerateInIsolate(String host, String user, String password) {
  final rc = WindowsSessionFfi.connectIpcShare(
    host: host,
    user: user,
    password: password,
  );
  if (rc != 0) {
    WindowsSessionFfi.disconnectShare(host);
    return (ok: false, connectFailed: true, code: rc, sessions: const []);
  }
  try {
    final result = WindowsSessionFfi.enumerateSessions(host);
    return (
      ok: result.ok,
      connectFailed: false,
      code: result.code,
      sessions: result.sessions,
    );
  } finally {
    WindowsSessionFfi.disconnectShare(host);
  }
}

_IsolateResult _logoffInIsolate(
  String host,
  String user,
  String password,
  int sessionId,
) {
  final rc = WindowsSessionFfi.connectIpcShare(
    host: host,
    user: user,
    password: password,
  );
  if (rc != 0) {
    WindowsSessionFfi.disconnectShare(host);
    return (ok: false, connectFailed: true, code: rc, sessions: const []);
  }
  try {
    final result = WindowsSessionFfi.logoffSession(
      host: host,
      sessionId: sessionId,
    );
    if (!result.ok) {
      return (
        ok: false,
        connectFailed: false,
        code: result.code,
        sessions: const [],
      );
    }

    // Επαλήθευση: η συνεδρία πρέπει να έχει φύγει από τη λίστα. Το
    // WTSLogoffSession επιστρέφει επιτυχία μόλις δεχτεί την εντολή.
    final after = WindowsSessionFfi.enumerateSessions(host);
    if (after.ok && after.sessions.any((s) => s.sessionId == sessionId)) {
      final still = after.sessions.firstWhere((s) => s.sessionId == sessionId);
      // Κατάσταση 4 = αποσυνδεδεμένη: το κλείσιμο ξεκίνησε αλλά δεν τελείωσε.
      if (still.state != 4) {
        return (
          ok: false,
          connectFailed: false,
          code: ServerSessionMessages.logoffNotVerified,
          sessions: const [],
        );
      }
    }
    return (ok: true, connectFailed: false, code: 0, sessions: const []);
  } finally {
    WindowsSessionFfi.disconnectShare(host);
  }
}
