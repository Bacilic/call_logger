import '../../../core/models/operator_presence.dart';
import '../../../core/services/session_liveness_mark.dart';

/// Ένα ίχνος παρουσίας μαζί με το όνομα του ανθρώπου, όπως έρχεται από τη βάση.
typedef PresenceWithName = ({OperatorPresence presence, String? operatorName});

/// Μία ανοιχτή εφαρμογή που κρατά αυτή τη στιγμή τη βάση.
///
/// **Συνεδρία, όχι πρόσωπο και όχι μηχάνημα.** Ο ίδιος άνθρωπος μπορεί να
/// δουλεύει από δύο θέσεις, και ο ίδιος υπολογιστής μπορεί να έχει δύο
/// εφαρμογές ανοιχτές (την κανονική και τη δοκιμαστική). Καθεμιά κρατά το
/// αρχείο ξεχωριστά, οπότε καθεμιά μετράει ξεχωριστά.
class ActiveSession {
  const ActiveSession({
    required this.station,
    required this.lastSeenAt,
    required this.isMine,
    this.operatorName,
    this.appVersion,
  });

  /// Το όνομα του υπολογιστή.
  final String station;

  /// Ποιος είναι συνδεδεμένος· `null` όταν το προφίλ διαγράφηκε στο μεταξύ.
  final String? operatorName;

  final DateTime lastSeenAt;

  /// Ποια έκδοση τρέχει· `null` για ίχνη γραμμένα πριν από την v60.
  final String? appVersion;

  /// Είναι αυτό το ίδιο αντίγραφο της εφαρμογής που ρωτά.
  final bool isMine;
}

/// Οι συνεδρίες που κρατούν τη βάση τη στιγμή [now].
///
/// **Ο κανόνας ζει εδώ, σε καθαρή συνάρτηση:** ένα ίχνος μετράει μόνο αν είναι
/// φρέσκο **και** το κρατά ακόμη ανοιχτό αντίγραφο ([OperatorPresence.isOnlineAt]).
/// Η οθόνη δεν ξαναγράφει τον κανόνα και δεν αποκτά δεύτερο ρολόι.
///
/// Σειρά: **η δική μου πρώτη** — ο άνθρωπος βρίσκει αμέσως τον εαυτό του και
/// καταλαβαίνει ότι η λίστα τον περιλαμβάνει — και μετά νεότερη πρώτη.
List<ActiveSession> activeSessions({
  required List<PresenceWithName> marks,
  required DateTime now,
  required String myInstance,
}) {
  final holder = myInstance.trim();
  final out = <ActiveSession>[];
  for (final mark in marks) {
    final p = mark.presence;
    if (!p.isOnlineAt(now)) continue;
    out.add(
      ActiveSession(
        station: p.station,
        operatorName: mark.operatorName,
        lastSeenAt: p.lastSeenAt,
        appVersion: p.appVersion,
        isMine: holder.isNotEmpty && p.instance == holder,
      ),
    );
  }
  return _sortedMineFirst(out);
}

/// Οι συνεδρίες όπως τις λένε τα ίχνη «τρέχω τώρα» του φακέλου logs — η πηγή
/// όταν η βάση **δεν** είναι ανοιχτή (π.χ. αναβάθμιση σχήματος στην εκκίνηση).
///
/// Φτωχότερη από τη βάση, αλλά αρκετή για τον φρουρό: σταθμός, έκδοση, πόσο
/// πρόσφατα. Δεν ξέρει **ποιος** κάθεται στον σταθμό, και δεν ξεχωρίζει δύο
/// εφαρμογές στον ίδιο υπολογιστή (το ίχνος είναι ένα ανά σταθμό) — γι' αυτό
/// «δικό μου» είναι ό,τι γράφτηκε από τον δικό μου σταθμό.
///
/// Φρεσκάδα: ο **ίδιος** κανόνας με την παρουσία στη βάση
/// ([OperatorPresence.onlineWindow]). Ίχνος που έπαψε να ανανεώνεται είναι
/// κατάρρευση, όχι συνάδελφος.
List<ActiveSession> activeSessionsFromLivenessMarks({
  required List<SessionLivenessMark> marks,
  required DateTime now,
  required String myStation,
}) {
  final me = myStation.trim().toLowerCase();
  final out = <ActiveSession>[];
  for (final mark in marks) {
    if (now.difference(mark.lastSeen) >= OperatorPresence.onlineWindow) {
      continue;
    }
    final station = mark.station.trim();
    final version = mark.version.trim();
    out.add(
      ActiveSession(
        station: station.isEmpty ? 'άγνωστος σταθμός' : station,
        lastSeenAt: mark.lastSeen,
        appVersion: version.isEmpty ? null : version,
        isMine: me.isNotEmpty && station.toLowerCase() == me,
      ),
    );
  }
  return _sortedMineFirst(out);
}

List<ActiveSession> _sortedMineFirst(List<ActiveSession> sessions) {
  sessions.sort((a, b) {
    if (a.isMine != b.isMine) return a.isMine ? -1 : 1;
    return b.lastSeenAt.compareTo(a.lastSeenAt);
  });
  return sessions;
}

/// Μόνο οι **άλλοι** — αυτό ρωτά ο φρουρός πριν από επικίνδυνη συντήρηση.
List<ActiveSession> otherSessions(List<ActiveSession> sessions) => [
  for (final s in sessions)
    if (!s.isMine) s,
];

/// Από πόσους **διαφορετικούς υπολογιστές** είναι ανοιχτή η βάση τώρα.
///
/// Δύο προφίλ στον ίδιο υπολογιστή μετρούν ως ένας: η περίληψη απαντά «σε πόσα
/// μηχανήματα», ενώ η λίστα από κάτω δείχνει τις συνεδρίες μία-μία.
int distinctStationCount(List<ActiveSession> sessions) =>
    {for (final s in sessions) s.station.toLowerCase()}.length;

/// Η έκδοση που τρέχει το **δικό μας** αντίγραφο, όπως τη λέει η ίδια η λίστα.
///
/// Διαβάζεται από τη δική μας συνεδρία αντί να ζητηθεί ξανά από το σύστημα: η
/// σύγκριση «ίδια ή διαφορετική;» πρέπει να γίνεται ανάμεσα σε δύο τιμές που
/// ήρθαν από την ίδια πηγή, αλλιώς μια διαφορά μορφής θα φαινόταν διαφορά
/// έκδοσης.
String? myAppVersion(List<ActiveSession> sessions) {
  for (final s in sessions) {
    if (s.isMine) return s.appVersion;
  }
  return null;
}

/// «3 υπολογιστές» / «1 υπολογιστής» — η περίληψη πάνω από τη λίστα.
String describeStationCount(int count) =>
    count == 1 ? '1 υπολογιστής' : '$count υπολογιστές';

/// Μία γραμμή της λίστας: «TEP-02 · Βαρβάρα · πριν από 2΄ · έκδοση 57».
///
/// Η **έκδοση γράφεται μόνο όταν διαφέρει** από τη δική μας: όταν όλοι τρέχουν
/// το ίδιο, η στήλη δεν πληροφορεί — γεμίζει τη γραμμή και κρύβει το όνομα.
/// Η διαφορά, αντίθετα, είναι ακριβώς αυτό που θέλει να δει κανείς πριν από
/// αναβάθμιση σχήματος.
String describeActiveSession(
  ActiveSession session, {
  required DateTime now,
  String? myAppVersion,
}) {
  final parts = <String>[session.station];

  final name = session.operatorName?.trim();
  if (name != null && name.isNotEmpty) parts.add(name);

  parts.add(session.isMine ? 'εσείς' : _describeSince(now, session.lastSeenAt));

  final version = session.appVersion?.trim();
  final mine = myAppVersion?.trim();
  if (version != null &&
      version.isNotEmpty &&
      !session.isMine &&
      (mine == null || mine.isEmpty || mine != version)) {
    parts.add('έκδοση $version');
  }

  return parts.join(' · ');
}

/// Πόσο πριν γράφτηκε το ίχνος, σε λέξεις.
///
/// Το εύρος είναι μικρό εξ ορισμού — πέρα από το παράθυρο φρεσκάδας η συνεδρία
/// δεν είναι πια στη λίστα — οπότε δεν χρειάζονται ώρες και ημέρες.
String _describeSince(DateTime now, DateTime lastSeenAt) {
  final elapsed = now.difference(lastSeenAt);
  if (elapsed.inSeconds < 90) return 'μόλις τώρα';
  return 'πριν από ${elapsed.inMinutes}΄';
}
