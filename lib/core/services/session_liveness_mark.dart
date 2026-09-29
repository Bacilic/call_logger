import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Το ίχνος «τρέχω τώρα» μιας εκτέλεσης της εφαρμογής.
///
/// Γράφεται στην εκκίνηση, ανανεώνεται όσο η εφαρμογή ζει, και σβήνεται στο
/// ομαλό κλείσιμο. Αν βρεθεί στην **επόμενη** εκκίνηση, σημαίνει ότι η
/// προηγούμενη εκτέλεση δεν έκλεισε ποτέ — και τότε τα περιεχόμενά του είναι
/// όλη η διάγνωση που υπάρχει: ποια έκδοση, από ποιον σταθμό, πότε ξεκίνησε
/// και μέχρι πότε ζούσε.
///
/// **Ένα ίχνος ανά σταθμό.** Ο φάκελος ζει δίπλα στη βάση, και η βάση είναι
/// συχνά κοινόχρηστη: ένα κοινό ίχνος θα σήμαινε ότι ο κάθε σταθμός βλέπει το
/// ίχνος των άλλων ως δική του κατάρρευση, και ότι το άνοιγμα του ενός σβήνει
/// το ίχνος του άλλου. Ο σταθμός μπαίνει στο **όνομα** του αρχείου, και
/// επαναλαμβάνεται **μέσα** του γιατί το μήνυμα καταλήγει στο κοινό ημερολόγιο
/// σφαλμάτων, όπου ανακατεύονται οι γραμμές όλων.
class SessionLivenessMark {
  const SessionLivenessMark({
    required this.station,
    required this.version,
    required this.startedAt,
    required this.lastSeen,
    this.database,
    this.instance,
    this.listensForShutdownRequests = false,
  });

  final String station;
  final String version;
  final DateTime startedAt;

  /// Πότε η εκτέλεση έδωσε τελευταία σημάδι ζωής.
  final DateTime lastSeen;

  /// **Το όνομα αρχείου** της βάσης που κρατά η εκτέλεση — όχι η διαδρομή.
  ///
  /// Η διαδρομή θα ήταν λάθος ταυτότητα: ο ένας σταθμός βλέπει την ίδια βάση
  /// ως `\\POPINIO\CallLogger\…` και ο άλλος ως `D:\CallLogger\…`, οπότε δύο
  /// συνάδελφοι στο ίδιο αρχείο θα φαίνονταν σε διαφορετικά. Το ίχνος όμως ζει
  /// **μέσα** στον φάκελο της βάσης: όποιος γράφει εκεί βλέπει ήδη τον ίδιο
  /// φάκελο, άρα το μόνο που τους ξεχωρίζει είναι το όνομα του αρχείου.
  ///
  /// `null` σε ίχνος παλαιότερης έκδοσης, που δεν το κρατούσε.
  final String? database;

  /// Ποιο **ανοιχτό αντίγραφο** έγραψε το ίχνος.
  ///
  /// Δύο εφαρμογές στον ίδιο υπολογιστή (η κανονική και η δοκιμαστική) είναι
  /// δύο διαφορετικές εκτελέσεις πάνω στο ίδιο αρχείο βάσης, και καμία δεν
  /// επιτρέπεται να περάσει το ίχνος της άλλης για δικό της.
  ///
  /// `null` σε ίχνος παλαιότερης έκδοσης· τότε η μόνη ταυτότητα είναι ο
  /// σταθμός, όπως ήταν.
  final String? instance;

  /// Κοιτάζει αυτή η εκτέλεση για αιτήματα κλεισίματος;
  ///
  /// **Η δήλωση δεν είναι διακοσμητική.** Ο αιτών υπολογίζει από το [lastSeen]
  /// πότε ο παραλήπτης θα δει το σημείωμά του, και του το δείχνει ως αντίστροφη
  /// μέτρηση. Για εκτέλεση που δεν ακούει, εκείνη η μέτρηση θα ήταν ψέμα του
  /// χειρότερου είδους: θα τον κρατούσε να περιμένει μήνυμα που δεν πρόκειται
  /// να φτάσει. Εκδόσεις παλαιότερες από τη λειτουργία δεν γράφουν το πεδίο,
  /// οπότε το `false` λέει ακριβώς την αλήθεια γι' αυτές — θέλουν τηλέφωνο.
  final bool listensForShutdownRequests;

  SessionLivenessMark seenAt(DateTime now) => SessionLivenessMark(
    station: station,
    version: version,
    startedAt: startedAt,
    lastSeen: now,
    database: database,
    instance: instance,
    listensForShutdownRequests: listensForShutdownRequests,
  );

  String encode() => jsonEncode({
    'station': station,
    'version': version,
    'startedAt': startedAt.toIso8601String(),
    'lastSeen': lastSeen.toIso8601String(),
    if (database != null) 'database': database,
    if (instance != null) 'instance': instance,
    if (listensForShutdownRequests) 'listensForShutdownRequests': true,
  });

  /// Διαβάζει ίχνος. `null` όταν λείπει, είναι αλλοιωμένο, ή γράφτηκε από
  /// παλαιότερη έκδοση που δεν κρατούσε τίποτα (το αρχείο ήταν ο χαρακτήρας
  /// «1»). Τότε ο καλών λέει ό,τι ξέρει: ότι κάτι χάθηκε, χωρίς λεπτομέρειες.
  static SessionLivenessMark? decode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, Object?>) return null;
      final startedAt = DateTime.tryParse(
        decoded['startedAt']?.toString() ?? '',
      );
      if (startedAt == null) return null;
      final lastSeen =
          DateTime.tryParse(decoded['lastSeen']?.toString() ?? '') ?? startedAt;
      return SessionLivenessMark(
        station: decoded['station']?.toString() ?? '',
        version: decoded['version']?.toString() ?? '',
        startedAt: startedAt,
        lastSeen: lastSeen,
        database: _nonEmpty(decoded['database']),
        instance: _nonEmpty(decoded['instance']),
        listensForShutdownRequests:
            decoded['listensForShutdownRequests'] == true,
      );
    } on FormatException {
      return null;
    }
  }

  /// Κρατά αυτό το ίχνος τη βάση με το όνομα [databaseFileName];
  ///
  /// Σύγκριση χωρίς πεζά/κεφαλαία: τα Windows δεν ξεχωρίζουν το «Hospital.db»
  /// από το «hospital.db», και δύο ίχνη με άλλη γραφή είναι ο ίδιος άνθρωπος.
  ///
  /// **Η άγνοια απαντά «ναι».** Όταν λείπει το όνομα — από τη δική μας πλευρά ή
  /// από το ίχνος, που μπορεί να γράφτηκε από παλαιότερη έκδοση — δεν έχουμε
  /// λόγο να αποκλείσουμε κανέναν. Ένα «όχι» εδώ θα έκανε αόρατο ακριβώς τον
  /// συνάδελφο που κάθε φρουρός ψάχνει.
  bool holdsDatabase(String? databaseFileName) {
    final mine = databaseFileName?.trim().toLowerCase() ?? '';
    final theirs = database?.trim().toLowerCase() ?? '';
    if (mine.isEmpty || theirs.isEmpty) return true;
    return mine == theirs;
  }

  /// Είναι αυτό το ίχνος της **δικής μας** εκτέλεσης;
  ///
  /// Όταν και οι δύο πλευρές δηλώνουν εκτέλεση, εκείνη αποφασίζει: δύο
  /// αντίγραφα στον ίδιο υπολογιστή είναι δύο διαφορετικοί κάτοχοι του αρχείου,
  /// και κανένα δεν επιτρέπεται να περάσει το ίχνος του άλλου για δικό του.
  /// Χωρίς δηλωμένη εκτέλεση (ίχνος παλαιότερης έκδοσης) η μόνη ταυτότητα που
  /// υπάρχει είναι ο σταθμός, όπως ήταν.
  bool isSameRunAs({required String station, String? instance}) {
    final myRun = instance?.trim() ?? '';
    final theirRun = this.instance?.trim() ?? '';
    if (myRun.isNotEmpty && theirRun.isNotEmpty) return myRun == theirRun;
    final me = station.trim().toLowerCase();
    return me.isNotEmpty && this.station.trim().toLowerCase() == me;
  }

  /// Κενό και «λείπει» είναι το ίδιο πράγμα: ένα πεδίο που γράφτηκε άδειο δεν
  /// ταυτοποιεί τίποτα, και η διάκριση θα γεννούσε δύο δρόμους για την ίδια
  /// άγνοια.
  static String? _nonEmpty(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  /// Το μήνυμα που διαβάζει ο χρήστης στο ημερολόγιο σφαλμάτων.
  String describeLostRun() {
    final identity = [
      if (version.isNotEmpty) 'έκδοση $version',
      if (station.isNotEmpty) 'σταθμός $station',
    ].join(', ');
    final who = identity.isEmpty ? '' : ' ($identity)';
    return 'Η προηγούμενη εκτέλεση δεν τερμάτισε ομαλά$who: '
        'ξεκίνησε ${formatMoment(startedAt)}, '
        'τελευταίο σημάδι ζωής ${formatMoment(lastSeen)} — '
        'έζησε ${formatLifetime(lastSeen.difference(startedAt))}.';
  }

  /// «04/09/2026 18:39».
  static String formatMoment(DateTime moment) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(moment.day)}/${two(moment.month)}/${moment.year} '
        '${two(moment.hour)}:${two(moment.minute)}';
  }

  /// «6 ώρες και 41 λεπτά», «27 λεπτά», «λιγότερο από ένα λεπτό».
  ///
  /// Η ακρίβεια σταματά στο λεπτό επίτηδες: το σημάδι ζωής ανανεώνεται κάθε
  /// λεπτό, οπότε δευτερόλεπτα θα ήταν ακρίβεια που δεν υπάρχει.
  static String formatLifetime(Duration lifetime) {
    if (lifetime.inMinutes < 1) return 'λιγότερο από ένα λεπτό';
    final hours = lifetime.inHours;
    final minutes = lifetime.inMinutes % 60;
    if (hours == 0) return _plural(minutes, 'λεπτό', 'λεπτά');
    final hoursPart = _plural(hours, 'ώρα', 'ώρες');
    if (minutes == 0) return hoursPart;
    return '$hoursPart και ${_plural(minutes, 'λεπτό', 'λεπτά')}';
  }

  static String _plural(int count, String singular, String plural) {
    return count == 1 ? '1 $singular' : '$count $plural';
  }
}

/// Διαβάζει τα ίχνη «τρέχω τώρα» **όλων** των σταθμών από τον φάκελο logs
/// δίπλα στη βάση.
///
/// Είναι η μόνη γνώση για το «ποιος άλλος κρατά τη βάση» που υπάρχει **χωρίς**
/// ανοιχτή βάση — γράφεται από κάθε εφαρμογή πριν καν ανοίξει τη βάση της.
/// Περιλαμβάνει και το κοινό `session.lock` της παλιάς εποχής: το γράφει
/// ακριβώς ο συνάδελφος με την παλιότερη εφαρμογή.
///
/// Δεν κρίνει φρεσκάδα — επιστρέφει ό,τι βρει. Φάκελος που δεν απαντά ή δεν
/// υπάρχει δίνει κενή λίστα, ποτέ σφάλμα και ποτέ κρέμασμα: σε κοινόχρηστο
/// φάκελο που χάθηκε, ο καλών ρωτά ακριβώς τη στιγμή που ο χρήστης προσπαθεί
/// να διορθώσει κάτι.
Future<List<SessionLivenessMark>> readSessionLivenessMarks(
  String logsDirectory, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final marks = <SessionLivenessMark>[];
  try {
    await () async {
      final entries = await Directory(logsDirectory).list().toList();
      for (final entry in entries) {
        if (entry is! File ||
            !_isLivenessMarkFileName(p.basename(entry.path))) {
          continue;
        }
        try {
          final mark = SessionLivenessMark.decode(await entry.readAsString());
          if (mark != null) marks.add(mark);
        } catch (_) {
          // Ένα ίχνος που δεν διαβάζεται δεν κρύβει τα υπόλοιπα.
        }
      }
    }().timeout(timeout);
  } catch (_) {
    // Φάκελος που δεν υπάρχει ή δεν απαντά: ό,τι μαζεύτηκε ως εκεί.
  }
  return marks;
}

/// `session_<σταθμός>.lock` ή το παλιό κοινό `session.lock` — όχι τα
/// ημερήσια `session_<ημερομηνία>.log`.
bool _isLivenessMarkFileName(String name) {
  final lower = name.toLowerCase();
  if (lower == 'session.lock') return true;
  return lower.startsWith('session_') && lower.endsWith('.lock');
}
