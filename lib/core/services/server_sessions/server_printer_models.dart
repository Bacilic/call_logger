/// Υγεία εκτυπωτή, όπως τη δηλώνει ο διακομιστής.
enum PrinterHealth {
  /// Καμία σημαία προβλήματος.
  ready,

  /// Σφάλμα, χαρτί, μπλοκάρισμα — κάτι θέλει άνθρωπο.
  error,

  /// Σε παύση από χειριστή.
  paused,

  /// Ο εκτυπωτής δεν απαντά.
  offline,
}

extension PrinterHealthLabel on PrinterHealth {
  String get label => switch (this) {
    PrinterHealth.ready => 'Έτοιμος',
    PrinterHealth.error => 'Σφάλμα',
    PrinterHealth.paused => 'Σε παύση',
    PrinterHealth.offline => 'Εκτός σύνδεσης',
  };

  bool get needsAttention => this != PrinterHealth.ready;
}

/// Σημαίες κατάστασης εκτυπωτή (`PRINTER_STATUS_*`).
abstract final class PrinterStatusFlags {
  PrinterStatusFlags._();

  static const int paused = 0x00000001;
  static const int error = 0x00000002;
  static const int paperJam = 0x00000008;
  static const int paperOut = 0x00000010;
  static const int offline = 0x00000080;
  static const int outOfMemory = 0x00000200;
  static const int doorOpen = 0x00400000;
  static const int notAvailable = 0x00001000;
}

/// Μετάφραση των ωμών σημαιών σε μία κατάσταση.
///
/// Η σειρά είναι σκόπιμη: το σφάλμα υπερισχύει της παύσης, γιατί ένας
/// εκτυπωτής σε παύση **και** με μπλοκαρισμένο χαρτί θέλει χέρι, όχι κλικ.
PrinterHealth printerHealthFromFlags(int flags) {
  const problems =
      PrinterStatusFlags.error |
      PrinterStatusFlags.paperJam |
      PrinterStatusFlags.paperOut |
      PrinterStatusFlags.outOfMemory |
      PrinterStatusFlags.doorOpen;
  if (flags & problems != 0) return PrinterHealth.error;
  if (flags & (PrinterStatusFlags.offline | PrinterStatusFlags.notAvailable) !=
      0) {
    return PrinterHealth.offline;
  }
  if (flags & PrinterStatusFlags.paused != 0) return PrinterHealth.paused;
  return PrinterHealth.ready;
}

/// Σημαίες κατάστασης εργασίας εκτύπωσης (`JOB_STATUS_*`).
abstract final class PrintJobStatusFlags {
  PrintJobStatusFlags._();

  static const int paused = 0x00000001;
  static const int error = 0x00000002;
  static const int deleting = 0x00000004;
  static const int spooling = 0x00000008;
  static const int printing = 0x00000010;
  static const int offline = 0x00000020;
  static const int paperOut = 0x00000040;
  static const int printed = 0x00000080;
  static const int deleted = 0x00000100;
  static const int blockedDevQ = 0x00000200;
  static const int complete = 0x00001000;
}

/// Μία εργασία στην ουρά ενός εκτυπωτή.
class PrintJob {
  const PrintJob({
    required this.jobId,
    required this.document,
    required this.user,
    required this.machine,
    required this.statusFlags,
    required this.totalPages,
    required this.pagesPrinted,
  });

  final int jobId;
  final String document;
  final String user;
  final String machine;
  final int statusFlags;
  final int totalPages;
  final int pagesPrinted;

  /// Τυπώνεται **αυτή τη στιγμή** — η μόνη περίπτωση που μια επανεκκίνηση
  /// ουράς κοστίζει χαρτί.
  bool get isActive =>
      statusFlags &
          (PrintJobStatusFlags.printing | PrintJobStatusFlags.spooling) !=
      0;

  /// Κολλημένη: ούτε προχωρά ούτε φεύγει, και κρατά πίσω όσες ακολουθούν.
  bool get isStuck =>
      statusFlags &
          (PrintJobStatusFlags.error |
              PrintJobStatusFlags.deleting |
              PrintJobStatusFlags.blockedDevQ |
              PrintJobStatusFlags.offline |
              PrintJobStatusFlags.paperOut) !=
      0;

  String get statusLabel {
    if (statusFlags & PrintJobStatusFlags.error != 0) return 'σφάλμα';
    if (statusFlags & PrintJobStatusFlags.deleting != 0) return 'διαγράφεται';
    if (statusFlags & PrintJobStatusFlags.blockedDevQ != 0) return 'μπλοκαρισμένη';
    if (statusFlags & PrintJobStatusFlags.paperOut != 0) return 'χωρίς χαρτί';
    if (statusFlags & PrintJobStatusFlags.offline != 0) return 'εκτός σύνδεσης';
    if (statusFlags & PrintJobStatusFlags.printing != 0) return 'τυπώνεται';
    if (statusFlags & PrintJobStatusFlags.spooling != 0) return 'προετοιμάζεται';
    if (statusFlags & PrintJobStatusFlags.paused != 0) return 'σε παύση';
    if (statusFlags & PrintJobStatusFlags.printed != 0) return 'τυπώθηκε';
    return 'αναμονή';
  }
}

/// Ένας εκτυπωτής όπως τον βλέπει ο διακομιστής.
class ServerPrinter {
  const ServerPrinter({
    required this.fullName,
    required this.displayName,
    required this.stationName,
    required this.sessionId,
    required this.driverName,
    required this.statusFlags,
    required this.jobCount,
  });

  /// Το όνομα ακριβώς όπως το δίνει ο διακομιστής — αυτό χρειάζεται κάθε
  /// ενέργεια πάνω του, και δεν πρέπει ποτέ να «ομορφύνει».
  final String fullName;

  /// Το όνομα χωρίς το «(from PCxxxx) in session N» — για εμφάνιση.
  final String displayName;

  /// Ο σταθμός που τον έφερε· κενό όταν είναι εκτυπωτής του ίδιου του
  /// διακομιστή ή όταν το όνομα δεν το λέει.
  final String stationName;

  /// Η συνεδρία που τον έφερε· `null` για μη ανακατευθυνόμενους.
  final int? sessionId;

  final String driverName;
  final int statusFlags;
  final int jobCount;

  /// Ήρθε από συνεδρία χρήστη, δεν ανήκει στον ίδιο τον διακομιστή.
  bool get isRedirected => sessionId != null;

  PrinterHealth get health => printerHealthFromFlags(statusFlags);
}

/// Ένας εκτυπωτής μαζί με την κρίση μας γι' αυτόν.
class StationPrinter {
  const StationPrinter({required this.printer, required this.isOrphan});

  final ServerPrinter printer;

  /// Η συνεδρία του δεν υπάρχει πια στον διακομιστή.
  ///
  /// **Γεγονός, όχι εκτίμηση:** προκύπτει από σύγκριση με τη ζωντανή λίστα
  /// συνεδριών. Γι' αυτό η αφαίρεσή του είναι ασφαλής.
  final bool isOrphan;
}

/// Από πού ήρθε η λίστα εκτυπωτών — και άρα τι μπορεί να γίνει μαζί της.
enum PrinterSource {
  /// Από την υπηρεσία ουράς εκτυπώσεων: πλήρης εικόνα και πλήρεις ενέργειες.
  spooler,

  /// Από το μητρώο του διακομιστή: ονόματα ναι, ουρές και ενέργειες όχι.
  ///
  /// Η εφεδρεία όταν η υπηρεσία δεν απαντά σε αυτόν τον υπολογιστή.
  registry,
}

/// Αποτέλεσμα ερώτησης για εκτυπωτές.
class ServerPrintersResult {
  const ServerPrintersResult._({
    required this.ok,
    required this.printers,
    required this.error,
    required this.source,
  });

  const ServerPrintersResult.success(
    List<ServerPrinter> printers, {
    PrinterSource source = PrinterSource.spooler,
  }) : this._(ok: true, printers: printers, error: null, source: source);

  const ServerPrintersResult.failure(String error)
    : this._(
        ok: false,
        printers: const [],
        error: error,
        source: PrinterSource.spooler,
      );

  final bool ok;
  final List<ServerPrinter> printers;
  final String? error;

  /// Πληροφορία που ΠΡΕΠΕΙ να φτάσει στην οθόνη: με εφεδρική πηγή, οι ουρές
  /// δείχνουν μηδέν επειδή δεν τις ξέρουμε — όχι επειδή είναι άδειες.
  final PrinterSource source;

  bool get isLimited => source == PrinterSource.registry;
}

/// Αποτέλεσμα ερώτησης για την ουρά ενός εκτυπωτή.
class PrintQueueResult {
  const PrintQueueResult._({
    required this.ok,
    required this.jobs,
    required this.error,
  });

  const PrintQueueResult.success(List<PrintJob> jobs)
    : this._(ok: true, jobs: jobs, error: null);

  const PrintQueueResult.failure(String error)
    : this._(ok: false, jobs: const [], error: error);

  final bool ok;
  final List<PrintJob> jobs;
  final String? error;
}

/// Γενικό αποτέλεσμα ενέργειας (εκκαθάριση, αφαίρεση, επανεκκίνηση).
class ServerActionResult {
  const ServerActionResult._({
    required this.ok,
    required this.error,
    required this.affected,
  });

  const ServerActionResult.success({int affected = 0})
    : this._(ok: true, error: null, affected: affected);

  const ServerActionResult.failure(String error)
    : this._(ok: false, error: error, affected: 0);

  final bool ok;
  final String? error;

  /// Πόσα στοιχεία επηρεάστηκαν (π.χ. εργασίες που σβήστηκαν).
  final int affected;
}
