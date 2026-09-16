import 'dart:convert';

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
  });

  final String station;
  final String version;
  final DateTime startedAt;

  /// Πότε η εκτέλεση έδωσε τελευταία σημάδι ζωής.
  final DateTime lastSeen;

  SessionLivenessMark seenAt(DateTime now) => SessionLivenessMark(
    station: station,
    version: version,
    startedAt: startedAt,
    lastSeen: now,
  );

  String encode() => jsonEncode({
    'station': station,
    'version': version,
    'startedAt': startedAt.toIso8601String(),
    'lastSeen': lastSeen.toIso8601String(),
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
      );
    } on FormatException {
      return null;
    }
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
