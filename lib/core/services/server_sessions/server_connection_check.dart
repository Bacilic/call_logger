/// Ο «Έλεγχος σύνδεσης» της φόρμας διακομιστή, ως ξεχωριστή δουλειά.
///
/// **Γιατί υπάρχει αυτό το αρχείο:** ο έλεγχος ρωτούσε μόνο τις συνεδρίες και
/// έβγαζε μία ετυμηγορία. Στον 192.168.13.83 απαντούσε «ο διακομιστής
/// απάντησε — 13 συνεδρίες» την ίδια στιγμή που οι εκτυπωτές του ήταν νεκροί:
/// πράσινο τικ για μισό διακομιστή. Τώρα δοκιμάζονται και οι τρεις ικανότητες
/// που ζητά η εφαρμογή, και η καθεμιά απαντά χωριστά.
///
/// **Κανένας από τους τρεις ελέγχους δεν αλλάζει τίποτα** — τρέχουν σε
/// ζωντανούς διακομιστές νοσοκομείου. Ο τρίτος ζητά την υπηρεσία εκτυπώσεων
/// με δικαίωμα διακοπής και σταματά εκεί: το αν μας το δώσουν είναι η
/// απάντηση, χωρίς να σταματήσει καμία ουρά.
library;

import 'server_printer_models.dart';
import 'server_printer_service.dart';
import 'server_session_models.dart';
import 'server_session_service.dart';

/// Τι δοκιμάζεται — μία γραμμή ανά ικανότητα που χρησιμοποιεί η εφαρμογή.
enum ServerCapability { sessions, printers, serviceControl }

/// Η έκβαση μιας γραμμής.
enum ServerCheckState {
  /// Δεν έχει τρέξει ακόμη.
  pending,

  /// Τρέχει τώρα.
  running,

  /// Δουλεύει.
  passed,

  /// Δουλεύει μισό — η διάκριση υπάρχει επειδή ακριβώς αυτή έλειπε.
  partial,

  /// Δεν δουλεύει.
  failed,
}

/// Μία γραμμή του αποτελέσματος.
class ServerCheckLine {
  const ServerCheckLine({
    required this.capability,
    required this.state,
    this.detail,
  });

  const ServerCheckLine.pending(this.capability)
    : state = ServerCheckState.pending,
      detail = null;

  final ServerCapability capability;
  final ServerCheckState state;

  /// Τι είδαμε — αριθμοί όταν πέτυχε, η αιτία όταν απέτυχε.
  final String? detail;

  String get title => switch (capability) {
    ServerCapability.sessions => 'Συνεδρίες χρηστών',
    ServerCapability.printers => 'Εκτυπωτές και ουρές',
    ServerCapability.serviceControl => 'Διαχείριση υπηρεσιών',
  };

  ServerCheckLine get asRunning =>
      ServerCheckLine(capability: capability, state: ServerCheckState.running);
}

/// Τρέχει τους τρεις ελέγχους και δίνει το αποτέλεσμα **όσο έρχεται**.
///
/// Η προοδευτική έξοδος δεν είναι καλλωπισμός: σε διακομιστή που δεν
/// αποκρίνεται, κάθε έλεγχος περιμένει ως το όριό του. Χωρίς αυτήν, ο
/// χειριστής θα κοίταζε άδεια οθόνη για δεκάδες δευτερόλεπτα.
class ServerConnectionChecker {
  const ServerConnectionChecker({
    required this.sessions,
    required this.printers,
  });

  final ServerSessionService sessions;
  final ServerPrinterService printers;

  /// Η σειρά είναι σκόπιμη: πρώτα το φθηνότερο που αποδεικνύει ότι μπήκαμε
  /// καθόλου, τελευταίο το δικαίωμα διαχείρισης.
  static const List<ServerCapability> order = [
    ServerCapability.sessions,
    ServerCapability.printers,
    ServerCapability.serviceControl,
  ];

  Stream<List<ServerCheckLine>> run({
    required String host,
    required String adminUser,
    required String adminPassword,
  }) async* {
    final lines = [for (final c in order) ServerCheckLine.pending(c)];

    for (var i = 0; i < order.length; i++) {
      lines[i] = lines[i].asRunning;
      yield List.of(lines);

      lines[i] = switch (order[i]) {
        ServerCapability.sessions => lineForSessions(
          await sessions.listSessions(
            host: host,
            adminUser: adminUser,
            adminPassword: adminPassword,
          ),
        ),
        ServerCapability.printers => lineForPrinters(
          await printers.listPrinters(
            host: host,
            adminUser: adminUser,
            adminPassword: adminPassword,
          ),
        ),
        ServerCapability.serviceControl => lineForServiceControl(
          await printers.canManageSpooler(
            host: host,
            adminUser: adminUser,
            adminPassword: adminPassword,
          ),
        ),
      };
      yield List.of(lines);
    }
  }

  /// **Η ανάγνωση της λίστας, όχι οι ενέργειες πάνω της.** Η αποσύνδεση οθόνης
  /// και ο τερματισμός δεν δοκιμάζονται: ο μόνος τρόπος να μάθεις αν
  /// επιτρέπονται είναι να τα κάνεις σε κάποιον. Γι' αυτό η λεπτομέρεια λέει
  /// «η λίστα διαβάζεται» και όχι «όλα καλά».
  static ServerCheckLine lineForSessions(ServerSessionsResult result) {
    return ServerCheckLine(
      capability: ServerCapability.sessions,
      state: result.ok ? ServerCheckState.passed : ServerCheckState.failed,
      detail: result.ok
          ? '${result.sessions.length} ανοιχτές · η λίστα διαβάζεται'
          : result.error,
    );
  }

  /// Η περιορισμένη προβολή είναι **μισή επιτυχία και δηλώνεται ως τέτοια**:
  /// τα ονόματα ήρθαν από τις ρυθμίσεις του διακομιστή, οι ουρές όχι. Ένα
  /// πράσινο τικ εδώ θα ήταν ακριβώς το ψέμα που ήρθε να λύσει ο έλεγχος.
  static ServerCheckLine lineForPrinters(ServerPrintersResult result) {
    if (!result.ok) {
      return ServerCheckLine(
        capability: ServerCapability.printers,
        state: ServerCheckState.failed,
        detail: result.error,
      );
    }
    if (result.isLimited) {
      final code = result.fallbackCode == 0
          ? ''
          : ' · κωδικός ${result.fallbackCode}';
      return ServerCheckLine(
        capability: ServerCapability.printers,
        state: ServerCheckState.partial,
        detail:
            '${result.printers.length} εκτυπωτές · περιορισμένη προβολή: '
            'ονόματα ναι, ουρές όχι$code',
      );
    }
    return ServerCheckLine(
      capability: ServerCapability.printers,
      state: ServerCheckState.passed,
      detail: '${result.printers.length} εκτυπωτές · πλήρης προβολή',
    );
  }

  static ServerCheckLine lineForServiceControl(ServerActionResult result) {
    return ServerCheckLine(
      capability: ServerCapability.serviceControl,
      state: result.ok ? ServerCheckState.passed : ServerCheckState.failed,
      detail: result.ok
          ? 'Επιτρέπεται · η ουρά μπορεί να επανεκκινηθεί'
          : result.error,
    );
  }
}
