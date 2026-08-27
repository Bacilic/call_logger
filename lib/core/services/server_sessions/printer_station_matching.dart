import 'server_printer_models.dart';
import 'server_session_models.dart';

/// Τα στοιχεία που κρύβει το όνομα ενός ανακατευθυνόμενου εκτυπωτή.
typedef ParsedPrinterName = ({String displayName, String station, int? session});

/// Ανάλυση ονόματος εκτυπωτή και ταίριασμα με σταθμό — καθαρές συναρτήσεις.
///
/// Όταν ένας χρήστης συνδέεται απομακρυσμένα, ο διακομιστής δημιουργεί
/// αντίγραφα των εκτυπωτών του και τα ονομάζει έτσι ώστε το όνομα να λέει από
/// πού ήρθαν. **Αυτό το όνομα είναι η μόνη γέφυρα** ανάμεσα σε έναν εκτυπωτή
/// και τον υπολογιστή του χρήστη: το API των Windows δεν επιστρέφει χωριστό
/// πεδίο με τη συνεδρία.
///
/// Δύο μορφές αναγνωρίζονται:
/// * `EPSON WF-M5399 (from PC2129) in session 11` — Windows Server 2003, αυτή
///   που παράγουν οι διακομιστές μας σήμερα.
/// * `EPSON WF-M5399 (redirected 11)` — νεότερες εκδόσεις, χωρίς όνομα σταθμού.
///
/// Αν κάποτε αλλάξει η μορφή, το ταίριασμα **σταματά ορατά** (άδεια λίστα) και
/// δεν γίνεται σιωπηλά λανθασμένο: καμία σύγκριση δεν πέφτει πίσω σε «περίπου».
abstract final class PrinterStationMatching {
  PrinterStationMatching._();

  /// `<όνομα> (from <σταθμός>) in session <N>`
  static final RegExp _fromStationPattern = RegExp(
    r'^(.*?)\s*\(\s*from\s+([^)]+?)\s*\)\s*in\s+session\s+(\d+)\s*$',
    caseSensitive: false,
  );

  /// `<όνομα> (redirected <N>)`
  static final RegExp _redirectedPattern = RegExp(
    r'^(.*?)\s*\(\s*redirected\s+(\d+)\s*\)\s*$',
    caseSensitive: false,
  );

  /// Πρόθεμα διαδρομής δικτύου, όπως `\\192.168.13.82\`.
  ///
  /// Η απομακρυσμένη απαρίθμηση επιστρέφει τα ονόματα με τον διακομιστή
  /// μπροστά — επιβεβαιωμένο ζωντανά. Φεύγει **μόνο** από το κείμενο που
  /// βλέπει ο χειριστής: το πλήρες όνομα μένει ανέπαφο, γιατί κάθε ενέργεια
  /// πάνω στον εκτυπωτή το χρειάζεται ακριβώς έτσι.
  static final RegExp _networkPrefix = RegExp(r'^\\\\[^\\]+\\');

  /// Σπάει το όνομα στα μέρη του. Για μη ανακατευθυνόμενο εκτυπωτή επιστρέφει
  /// το όνομα ως έχει, χωρίς σταθμό και χωρίς συνεδρία.
  static ParsedPrinterName parseName(String rawName) {
    final name = rawName.trim().replaceFirst(_networkPrefix, '');

    final withStation = _fromStationPattern.firstMatch(name);
    if (withStation != null) {
      return (
        displayName: withStation.group(1)!.trim(),
        station: withStation.group(2)!.trim(),
        session: int.tryParse(withStation.group(3)!),
      );
    }

    final redirected = _redirectedPattern.firstMatch(name);
    if (redirected != null) {
      return (
        displayName: redirected.group(1)!.trim(),
        station: '',
        session: int.tryParse(redirected.group(2)!),
      );
    }

    return (displayName: name, station: '', session: null);
  }

  /// Οι εκτυπωτές που ανήκουν σε αυτόν τον σταθμό.
  ///
  /// Ταιριάζει με **δύο** κριτήρια, όχι με ένα: το όνομα του σταθμού και οι
  /// αριθμοί των συνεδριών του. Αρκεί να ισχύει το ένα — αλλά όταν το όνομα
  /// λείπει (νεότερη μορφή) σώζει η συνεδρία, και όταν η συνεδρία έχει
  /// αλλάξει σώζει το όνομα. Χωρίς αυτό, ένας εκτυπωτής άλλου ανθρώπου θα
  /// μπορούσε να εμφανιστεί στην κάρτα λάθος εξοπλισμού.
  ///
  /// [stationName] έρχεται έτοιμο από τον καλούντα (π.χ. `PC5068`), με τον
  /// ίδιο κανόνα που χρησιμοποιεί το VNC — ένας ορισμός του «ποιο PC είναι ο
  /// εξοπλισμός 5068», όχι δύο.
  static List<StationPrinter> printersForStation({
    required List<ServerPrinter> printers,
    required String stationName,
    required Set<int> stationSessionIds,
    required Set<int> liveSessionIds,
  }) {
    final station = stationName.trim().toLowerCase();
    final out = <StationPrinter>[];

    for (final p in printers) {
      if (!p.isRedirected) continue;

      final byName =
          station.isNotEmpty && p.stationName.trim().toLowerCase() == station;
      final bySession =
          p.sessionId != null && stationSessionIds.contains(p.sessionId);
      if (!byName && !bySession) continue;

      out.add(
        StationPrinter(
          printer: p,
          isOrphan: _isOrphan(p, liveSessionIds),
        ),
      );
    }

    out.sort(_compare);
    return out;
  }

  /// Όλοι οι ορφανοί του διακομιστή — ό,τι έμεινε από συνεδρίες που έκλεισαν.
  ///
  /// Αυτή είναι η πραγματική συντήρηση: κάθε τέτοιος εκτυπωτής φορτώνει την
  /// ουρά εκτυπώσεων για πάντα, χωρίς να εξυπηρετεί κανέναν.
  static List<ServerPrinter> orphans({
    required List<ServerPrinter> printers,
    required Set<int> liveSessionIds,
  }) {
    final out = printers
        .where((p) => p.isRedirected && _isOrphan(p, liveSessionIds))
        .toList();
    out.sort((a, b) => (a.sessionId ?? 0).compareTo(b.sessionId ?? 0));
    return out;
  }

  /// Ορφανός = ανακατευθυνόμενος με συνεδρία που **δεν υπάρχει** στη ζωντανή
  /// λίστα.
  ///
  /// Ο φρουρός `liveSessionIds.isEmpty` είναι κρίσιμος: αν η ερώτηση για τις
  /// συνεδρίες απέτυχε και γυρίσει άδεια λίστα, τότε «κανένας δεν είναι
  /// ζωντανός» και **όλοι** οι εκτυπωτές θα χαρακτηρίζονταν ορφανοί. Άγνοια
  /// δεν σημαίνει απουσία.
  static bool _isOrphan(ServerPrinter p, Set<int> liveSessionIds) {
    if (liveSessionIds.isEmpty) return false;
    final id = p.sessionId;
    if (id == null) return false;
    return !liveSessionIds.contains(id);
  }

  /// Πρώτα όσοι θέλουν προσοχή, μετά όσοι έχουν ουρά, μετά αλφαβητικά.
  static int _compare(StationPrinter a, StationPrinter b) {
    if (a.isOrphan != b.isOrphan) return a.isOrphan ? 1 : -1;
    final aBad = a.printer.health.needsAttention;
    final bBad = b.printer.health.needsAttention;
    if (aBad != bBad) return aBad ? -1 : 1;
    final aJobs = a.printer.jobCount > 0;
    final bJobs = b.printer.jobCount > 0;
    if (aJobs != bJobs) return aJobs ? -1 : 1;
    return a.printer.displayName.toLowerCase().compareTo(
      b.printer.displayName.toLowerCase(),
    );
  }

  /// Οι αριθμοί συνεδριών που ανήκουν σε έναν σταθμό, από τη ζωντανή λίστα.
  static Set<int> sessionIdsForStation({
    required List<ServerSession> sessions,
    required String stationName,
  }) {
    final station = stationName.trim().toLowerCase();
    if (station.isEmpty) return const {};
    return {
      for (final s in sessions)
        if (s.stationName.trim().toLowerCase() == station) s.sessionId,
    };
  }

  static Set<int> liveSessionIds(List<ServerSession> sessions) => {
    for (final s in sessions) s.sessionId,
  };
}
