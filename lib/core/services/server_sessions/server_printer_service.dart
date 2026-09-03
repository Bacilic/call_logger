import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'printer_station_matching.dart';
import 'server_printer_models.dart';
import 'server_session_messages.dart';
import 'windows_printer_ffi.dart';
import 'windows_registry_printers_ffi.dart';
import 'windows_session_ffi.dart';

/// Εκτυπωτές, ουρές, υπηρεσία εκτυπώσεων και επανεκκίνηση διακομιστή.
///
/// Ακολουθεί το ίδιο αυστηρό μοτίβο με τις συνεδρίες: στοιχεία → άνοιγμα
/// συνεδρίας SMB → η δουλειά → **πάντα** κλείσιμο.
class ServerPrinterService {
  const ServerPrinterService();

  static const Duration defaultTimeout = Duration(seconds: 30);

  /// Η υπηρεσία ουράς εκτυπώσεων των Windows.
  static const String spoolerServiceName = 'Spooler';

  /// Οι εκτυπωτές του διακομιστή.
  Future<ServerPrintersResult> listPrinters({
    required String host,
    required String adminUser,
    required String adminPassword,
    Duration timeout = defaultTimeout,
  }) async {
    final guard = _guard(host, adminUser, adminPassword);
    if (guard != null) return ServerPrintersResult.failure(guard);

    final h = host.trim();
    final u = adminUser.trim();
    try {
      final raw = await Isolate.run(
        () => _listPrintersInIsolate(h, u, adminPassword),
      ).timeout(timeout);

      if (!raw.ok) {
        return ServerPrintersResult.failure(
          _message(
            connectFailed: raw.connectFailed,
            code: raw.code,
            host: h,
            user: u,
            what: 'ανάγνωσης εκτυπωτών',
          ),
        );
      }

      return ServerPrintersResult.success(
        [for (final p in raw.printers) _toPrinter(p)],
        source: raw.fromRegistry
            ? PrinterSource.registry
            : PrinterSource.spooler,
        fallbackCode: raw.fromRegistry ? raw.code : 0,
      );
    } on TimeoutException {
      return ServerPrintersResult.failure(_timeoutMessage(h, timeout));
    } catch (e) {
      return ServerPrintersResult.failure(
        'Απρόσμενο σφάλμα κατά την ανάγνωση εκτυπωτών του $h: $e',
      );
    }
  }

  /// Οι εργασίες στην ουρά ενός εκτυπωτή.
  Future<PrintQueueResult> listQueue({
    required String host,
    required String adminUser,
    required String adminPassword,
    required String printerFullName,
    Duration timeout = defaultTimeout,
  }) async {
    final guard = _guard(host, adminUser, adminPassword);
    if (guard != null) return PrintQueueResult.failure(guard);

    final h = host.trim();
    final u = adminUser.trim();
    final target = _remotePrinterPath(h, printerFullName);
    try {
      final raw = await Isolate.run(
        () => _listQueueInIsolate(h, u, adminPassword, target),
      ).timeout(timeout);

      if (!raw.ok) {
        return PrintQueueResult.failure(
          _message(
            connectFailed: raw.connectFailed,
            code: raw.code,
            host: h,
            user: u,
            what: 'ανάγνωσης ουράς',
          ),
        );
      }
      return PrintQueueResult.success([
        for (final j in raw.jobs)
          PrintJob(
            jobId: j.jobId,
            document: j.document,
            user: j.user,
            machine: j.machine,
            statusFlags: j.status,
            totalPages: j.totalPages,
            pagesPrinted: j.pagesPrinted,
          ),
      ]);
    } on TimeoutException {
      return PrintQueueResult.failure(_timeoutMessage(h, timeout));
    } catch (e) {
      return PrintQueueResult.failure(
        'Απρόσμενο σφάλμα κατά την ανάγνωση της ουράς στον $h: $e',
      );
    }
  }

  /// Αδειάζει την ουρά ενός εκτυπωτή.
  Future<ServerActionResult> purgeQueue({
    required String host,
    required String adminUser,
    required String adminPassword,
    required String printerFullName,
    Duration timeout = defaultTimeout,
  }) async {
    final guard = _guard(host, adminUser, adminPassword);
    if (guard != null) return ServerActionResult.failure(guard);

    final h = host.trim();
    final u = adminUser.trim();
    final target = _remotePrinterPath(h, printerFullName);
    try {
      final raw = await Isolate.run(
        () => _purgeQueueInIsolate(h, u, adminPassword, target),
      ).timeout(timeout);

      if (!raw.ok) {
        return ServerActionResult.failure(
          _message(
            connectFailed: raw.connectFailed,
            code: raw.code,
            host: h,
            user: u,
            what: 'εκκαθάρισης ουράς',
          ),
        );
      }
      return ServerActionResult.success(affected: raw.affected);
    } on TimeoutException {
      return ServerActionResult.failure(_timeoutMessage(h, timeout));
    } catch (e) {
      return ServerActionResult.failure(
        'Απρόσμενο σφάλμα κατά την εκκαθάριση στον $h: $e',
      );
    }
  }

  /// Αφαιρεί έναν εκτυπωτή από τον διακομιστή (για ορφανούς).
  Future<ServerActionResult> removePrinter({
    required String host,
    required String adminUser,
    required String adminPassword,
    required String printerFullName,
    Duration timeout = defaultTimeout,
  }) async {
    final guard = _guard(host, adminUser, adminPassword);
    if (guard != null) return ServerActionResult.failure(guard);

    final h = host.trim();
    final u = adminUser.trim();
    final target = _remotePrinterPath(h, printerFullName);
    try {
      final raw = await Isolate.run(
        () => _removePrinterInIsolate(h, u, adminPassword, target),
      ).timeout(timeout);

      if (!raw.ok) {
        return ServerActionResult.failure(
          _message(
            connectFailed: raw.connectFailed,
            code: raw.code,
            host: h,
            user: u,
            what: 'αφαίρεσης εκτυπωτή',
          ),
        );
      }
      return const ServerActionResult.success(affected: 1);
    } on TimeoutException {
      return ServerActionResult.failure(_timeoutMessage(h, timeout));
    } catch (e) {
      return ServerActionResult.failure(
        'Απρόσμενο σφάλμα κατά την αφαίρεση εκτυπωτή στον $h: $e',
      );
    }
  }

  /// Ξεπαγώνει εκτυπωτή που βρίσκεται σε παύση.
  ///
  /// Το φθηνότερο σκαλί επαναφοράς: καμία συνεδρία δεν πειράζεται, καμία
  /// εκτύπωση δεν κόβεται.
  Future<ServerActionResult> resumePrinter({
    required String host,
    required String adminUser,
    required String adminPassword,
    required String printerFullName,
    Duration timeout = defaultTimeout,
  }) async {
    final guard = _guard(host, adminUser, adminPassword);
    if (guard != null) return ServerActionResult.failure(guard);

    final h = host.trim();
    final u = adminUser.trim();
    final target = _remotePrinterPath(h, printerFullName);
    try {
      final raw = await Isolate.run(
        () => _resumePrinterInIsolate(h, u, adminPassword, target),
      ).timeout(timeout);

      if (!raw.ok) {
        return ServerActionResult.failure(
          _message(
            connectFailed: raw.connectFailed,
            code: raw.code,
            host: h,
            user: u,
            what: 'ξεπαγώματος εκτυπωτή',
          ),
        );
      }
      return const ServerActionResult.success(affected: 1);
    } on TimeoutException {
      return ServerActionResult.failure(_timeoutMessage(h, timeout));
    } catch (e) {
      return ServerActionResult.failure(
        'Απρόσμενο σφάλμα κατά το ξεπάγωμα εκτυπωτή στον $h: $e',
      );
    }
  }

  /// Επανεκκινεί την υπηρεσία ουράς εκτυπώσεων.
  ///
  /// Πιο μακρύ όριο χρόνου: η υπηρεσία σταματά, επαληθεύεται ότι σταμάτησε,
  /// ξεκινά και επαληθεύεται ότι τρέχει.
  Future<ServerActionResult> restartSpooler({
    required String host,
    required String adminUser,
    required String adminPassword,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final guard = _guard(host, adminUser, adminPassword);
    if (guard != null) return ServerActionResult.failure(guard);

    final h = host.trim();
    final u = adminUser.trim();
    try {
      final raw = await Isolate.run(
        () => _restartSpoolerInIsolate(h, u, adminPassword),
      ).timeout(timeout);

      if (!raw.ok) {
        return ServerActionResult.failure(
          _serviceMessage(code: raw.code, host: h, adminUser: u),
        );
      }
      return const ServerActionResult.success();
    } on TimeoutException {
      return ServerActionResult.failure(
        'Ο $h δεν ολοκλήρωσε την επανεκκίνηση της ουράς μέσα σε '
        '${timeout.inSeconds} δευτερόλεπτα. Έλεγξε την κατάσταση πριν '
        'ξαναδοκιμάσεις — η υπηρεσία μπορεί να έμεινε σταματημένη.',
      );
    } catch (e) {
      return ServerActionResult.failure(
        'Απρόσμενο σφάλμα κατά την επανεκκίνηση της ουράς στον $h: $e',
      );
    }
  }

  /// Ξεκινά επανεκκίνηση του διακομιστή με προειδοποίηση προς τους χρήστες.
  Future<ServerActionResult> initiateRestart({
    required String host,
    required String adminUser,
    required String adminPassword,
    required String message,
    required int graceSeconds,
    Duration timeout = defaultTimeout,
  }) async {
    final guard = _guard(host, adminUser, adminPassword);
    if (guard != null) return ServerActionResult.failure(guard);

    final h = host.trim();
    final u = adminUser.trim();
    try {
      final raw = await Isolate.run(
        () => _initiateRestartInIsolate(
          h,
          u,
          adminPassword,
          message,
          graceSeconds,
        ),
      ).timeout(timeout);

      if (!raw.ok) {
        return ServerActionResult.failure(
          _restartMessage(code: raw.code, host: h, adminUser: u),
        );
      }
      return const ServerActionResult.success();
    } on TimeoutException {
      return ServerActionResult.failure(_timeoutMessage(h, timeout));
    } catch (e) {
      return ServerActionResult.failure(
        'Απρόσμενο σφάλμα κατά την επανεκκίνηση του $h: $e',
      );
    }
  }

  /// Ακυρώνει επανεκκίνηση που μετράει αντίστροφα.
  Future<ServerActionResult> abortRestart({
    required String host,
    required String adminUser,
    required String adminPassword,
    Duration timeout = defaultTimeout,
  }) async {
    final guard = _guard(host, adminUser, adminPassword);
    if (guard != null) return ServerActionResult.failure(guard);

    final h = host.trim();
    final u = adminUser.trim();
    try {
      final raw = await Isolate.run(
        () => _abortRestartInIsolate(h, u, adminPassword),
      ).timeout(timeout);

      if (!raw.ok) {
        return ServerActionResult.failure(
          _restartMessage(code: raw.code, host: h, adminUser: u),
        );
      }
      return const ServerActionResult.success();
    } on TimeoutException {
      return ServerActionResult.failure(_timeoutMessage(h, timeout));
    } catch (e) {
      return ServerActionResult.failure(
        'Απρόσμενο σφάλμα κατά την ακύρωση στον $h: $e',
      );
    }
  }

  // --- Βοηθητικά -----------------------------------------------------------

  /// Το ωμό όνομα κρατιέται αυτούσιο (κάθε ενέργεια το χρειάζεται έτσι), ενώ
  /// σταθμός και συνεδρία βγαίνουν από τον **έναν** κανόνα ανάλυσης.
  static ServerPrinter _toPrinter(RawPrinter p) {
    final parsed = PrinterStationMatching.parseName(p.name);
    return ServerPrinter(
      fullName: p.name,
      displayName: parsed.displayName,
      stationName: parsed.station,
      sessionId: parsed.session,
      driverName: p.driverName,
      statusFlags: p.status,
      jobCount: p.jobCount,
    );
  }

  /// `\\<διακομιστής>\<εκτυπωτής>` — η μορφή που δέχεται το `OpenPrinter`.
  static String _remotePrinterPath(String host, String printerName) {
    final n = printerName.trim();
    if (n.startsWith(r'\\')) return n;
    return '\\\\$host\\$n';
  }

  static String? _guard(String host, String adminUser, String adminPassword) {
    if (!Platform.isWindows) return 'Η λειτουργία απαιτεί Windows.';
    if (host.trim().isEmpty) return 'Δεν έχει οριστεί διεύθυνση διακομιστή.';
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

  static String _timeoutMessage(String host, Duration timeout) =>
      'Ο διακομιστής $host δεν απάντησε μέσα σε ${timeout.inSeconds} '
      'δευτερόλεπτα.';

  /// Δύο εντελώς διαφορετικές αιτίες, δύο διαφορετικά μηνύματα: «δεν μπήκαμε
  /// καν στον διακομιστή» έναντι «μπήκαμε αλλά η ενέργεια απέτυχε».
  static String _message({
    required bool connectFailed,
    required int code,
    required String host,
    required String user,
    required String what,
  }) {
    if (connectFailed) {
      return ServerSessionMessages.forConnect(
        code: code,
        host: host,
        account: user,
      );
    }
    return _printerMessage(code: code, host: host, user: user, what: what);
  }

  static String _printerMessage({
    required int code,
    required String host,
    required String user,
    required String what,
  }) => switch (code) {
    ServerSessionMessages.errorAccessDenied =>
      ServerSessionMessages.accessDenied(
        what: 'διαχείρισης εκτυπωτών',
        host: host,
        account: user,
        // Μόνο εδώ: η ρύθμιση RPC αφορά αποκλειστικά τους εκτυπωτές, και χωρίς
        // αυτήν η κλήση ταξιδεύει με την ταυτότητα του συνδεδεμένου χρήστη των
        // Windows αντί για τον λογαριασμό που άνοιξε η εφαρμογή.
        includePrinterRpcHint: true,
      ),
    ServerSessionMessages.rpcServerUnavailable =>
      'Ο διακομιστής $host δεν αποκρίνεται. Αν μόλις έγινε επανεκκίνηση της '
          'ουράς, δώσ\' του λίγα δευτερόλεπτα και πάτα «Ανανέωση».',
    1801 =>
      'Ο εκτυπωτής δεν υπάρχει πια στον $host — πάτα «Ανανέωση» για την '
          'τρέχουσα εικόνα.',
    _ => 'Αποτυχία $what στον $host (κωδικός σφάλματος $code).',
  };

  static String _serviceMessage({
    required int code,
    required String host,
    required String adminUser,
  }) => switch (code) {
    ServerSessionMessages.errorAccessDenied =>
      ServerSessionMessages.accessDenied(
        what: 'διαχείρισης της ουράς εκτυπώσεων',
        host: host,
        account: adminUser,
      ),
    kServiceStopTimedOut =>
      'Η ουρά εκτυπώσεων του $host δεν σταμάτησε εγκαίρως. Συνήθως φταίει '
          'κολλημένη εργασία ή οδηγός εκτυπωτή — δοκίμασε ξανά σε λίγο.',
    kServiceStartTimedOut =>
      'Η ουρά εκτυπώσεων του $host σταμάτησε αλλά ΔΕΝ ξαναξεκίνησε. Χρειάζεται '
          'άμεσος έλεγχος: όσο είναι σταματημένη, κανείς δεν τυπώνει.',
    1060 => 'Δεν βρέθηκε υπηρεσία ουράς εκτυπώσεων στον $host.',
    1722 => 'Ο διακομιστής $host δεν αποκρίνεται.',
    _ =>
      'Αποτυχία επανεκκίνησης της ουράς εκτυπώσεων στον $host '
          '(κωδικός σφάλματος $code).',
  };

  static String _restartMessage({
    required int code,
    required String host,
    required String adminUser,
  }) => switch (code) {
    ServerSessionMessages.errorAccessDenied =>
      ServerSessionMessages.accessDenied(
        what: 'επανεκκίνησης του διακομιστή',
        host: host,
        account: adminUser,
      ),
    1115 => 'Ο $host βρίσκεται ήδη σε διαδικασία τερματισμού.',
    1116 =>
      'Δεν υπάρχει επανεκκίνηση σε εξέλιξη στον $host — δεν υπήρχε τίποτα '
          'να ακυρωθεί.',
    1722 => 'Ο διακομιστής $host δεν αποκρίνεται.',
    _ =>
      'Αποτυχία ενέργειας επανεκκίνησης στον $host (κωδικός σφάλματος $code).',
  };
}

typedef _PrinterIsolateResult = ({
  bool ok,
  bool connectFailed,
  int code,
  List<RawPrinter> printers,
  bool fromRegistry,
});

typedef _QueueIsolateResult = ({
  bool ok,
  bool connectFailed,
  int code,
  List<RawPrintJob> jobs,
});

typedef _ActionIsolateResult = ({
  bool ok,
  bool connectFailed,
  int code,
  int affected,
});

/// Ανοίγει τη συνεδρία, τρέχει το [body], και κλείνει **πάντα**.
T _withAdminShare<T>(
  String host,
  String user,
  String password,
  T Function() body,
  T Function(int code) onConnectFailure,
) {
  final rc = WindowsSessionFfi.connectIpcShare(
    host: host,
    user: user,
    password: password,
  );
  if (rc != 0) {
    WindowsSessionFfi.disconnectShare(host);
    return onConnectFailure(rc);
  }
  try {
    return body();
  } finally {
    WindowsSessionFfi.disconnectShare(host);
  }
}

/// Κωδικοί που σημαίνουν «η υπηρεσία ουράς δεν μιλά μαζί μας σε αυτό το
/// κανάλι» — όχι «δεν υπάρχουν εκτυπωτές».
///
/// 1753: ο διακομιστής δεν έχει καταχωρημένο σημείο επικοινωνίας για την
/// υπηρεσία εκτυπώσεων πάνω από RPC/TCP — το μιλά μόνο σε named pipe.
/// 1801 / 1802: το όνομα του διακομιστή δεν γίνεται δεκτό ως print server.
/// 124: το επίπεδο πληροφορίας δεν υποστηρίζεται από παλιό διακομιστή.
const Set<int> _spoolerUnreachableCodes = {1753, 1801, 1802, 124, 1723, 1722};

_PrinterIsolateResult _listPrintersInIsolate(
  String host,
  String user,
  String password,
) {
  return _withAdminShare<_PrinterIsolateResult>(
    host,
    user,
    password,
    () {
      final r = WindowsPrinterFfi.enumeratePrinters(host);
      if (r.ok) {
        return (
          ok: true,
          connectFailed: false,
          code: 0,
          printers: r.printers,
          fromRegistry: false,
        );
      }

      // Η υπηρεσία δεν απαντά σε αυτό το κανάλι. Δεν το αναγγέλλουμε ως
      // αποτυχία: το μητρώο του διακομιστή δίνει τα ίδια ονόματα πάνω από τη
      // σύνδεση που ήδη έχουμε ανοιχτή. Χάνουμε τις ουρές, όχι τη λίστα.
      if (!_spoolerUnreachableCodes.contains(r.code)) {
        return (
          ok: false,
          connectFailed: false,
          code: r.code,
          printers: const <RawPrinter>[],
          fromRegistry: false,
        );
      }

      final reg = WindowsRegistryPrintersFfi.enumeratePrinters(host);
      if (!reg.ok) {
        // Αναφέρεται το ΑΡΧΙΚΟ σφάλμα: η εφεδρεία απέτυχε επίσης, και το
        // σφάλμα του μητρώου θα έστελνε τον χειριστή σε λάθος κατεύθυνση.
        return (
          ok: false,
          connectFailed: false,
          code: r.code,
          printers: const <RawPrinter>[],
          fromRegistry: false,
        );
      }

      return (
        ok: true,
        connectFailed: false,
        // Ο κωδικός της ΑΠΟΤΥΧΗΜΕΝΗΣ ερώτησης στην ουρά, όχι της εφεδρείας
        // που πέτυχε: αυτός εξηγεί γιατί βλέπουμε μισή εικόνα.
        code: r.code,
        printers: [
          for (final p in reg.printers)
            (name: p.name, driverName: p.driverName, status: 0, jobCount: 0),
        ],
        fromRegistry: true,
      );
    },
    (code) => (
      ok: false,
      connectFailed: true,
      code: code,
      printers: const <RawPrinter>[],
      fromRegistry: false,
    ),
  );
}

_QueueIsolateResult _listQueueInIsolate(
  String host,
  String user,
  String password,
  String printerPath,
) {
  return _withAdminShare<_QueueIsolateResult>(host, user, password, () {
    final r = WindowsPrinterFfi.enumerateJobs(printerPath);
    return (ok: r.ok, connectFailed: false, code: r.code, jobs: r.jobs);
  }, (code) => (ok: false, connectFailed: true, code: code, jobs: const []));
}

_ActionIsolateResult _purgeQueueInIsolate(
  String host,
  String user,
  String password,
  String printerPath,
) {
  return _withAdminShare<_ActionIsolateResult>(host, user, password, () {
    final r = WindowsPrinterFfi.purgeQueue(printerPath);
    return (ok: r.ok, connectFailed: false, code: r.code, affected: r.deleted);
  }, (code) => (ok: false, connectFailed: true, code: code, affected: 0));
}

_ActionIsolateResult _removePrinterInIsolate(
  String host,
  String user,
  String password,
  String printerPath,
) {
  return _withAdminShare<_ActionIsolateResult>(host, user, password, () {
    final r = WindowsPrinterFfi.deletePrinter(printerPath);
    return (ok: r.ok, connectFailed: false, code: r.code, affected: 1);
  }, (code) => (ok: false, connectFailed: true, code: code, affected: 0));
}

_ActionIsolateResult _restartSpoolerInIsolate(
  String host,
  String user,
  String password,
) {
  return _withAdminShare<_ActionIsolateResult>(host, user, password, () {
    final r = WindowsPrinterFfi.restartService(
      host: host,
      serviceName: ServerPrinterService.spoolerServiceName,
    );
    return (ok: r.ok, connectFailed: false, code: r.code, affected: 0);
  }, (code) => (ok: false, connectFailed: true, code: code, affected: 0));
}

_ActionIsolateResult _initiateRestartInIsolate(
  String host,
  String user,
  String password,
  String message,
  int graceSeconds,
) {
  return _withAdminShare<_ActionIsolateResult>(host, user, password, () {
    final r = WindowsPrinterFfi.initiateRestart(
      host: host,
      message: message,
      graceSeconds: graceSeconds,
    );
    return (ok: r.ok, connectFailed: false, code: r.code, affected: 0);
  }, (code) => (ok: false, connectFailed: true, code: code, affected: 0));
}

_ActionIsolateResult _abortRestartInIsolate(
  String host,
  String user,
  String password,
) {
  return _withAdminShare<_ActionIsolateResult>(host, user, password, () {
    final r = WindowsPrinterFfi.abortRestart(host);
    return (ok: r.ok, connectFailed: false, code: r.code, affected: 0);
  }, (code) => (ok: false, connectFailed: true, code: code, affected: 0));
}

_ActionIsolateResult _resumePrinterInIsolate(
  String host,
  String user,
  String password,
  String printerPath,
) {
  return _withAdminShare<_ActionIsolateResult>(host, user, password, () {
    final r = WindowsPrinterFfi.resumePrinter(printerPath);
    return (ok: r.ok, connectFailed: false, code: r.code, affected: 1);
  }, (code) => (ok: false, connectFailed: true, code: code, affected: 0));
}
