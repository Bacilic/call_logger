/// Πότε είδε τελευταία φορά τη βάση ένας χρήστης, από έναν συγκεκριμένο σταθμό.
///
/// **Δεν είναι βεβαιότητα, είναι ίχνος.** Το SQLite δεν κρατά λίστα συνδέσεων —
/// είναι αρχείο, όχι διακομιστής. Κάθε ανοιχτή εφαρμογή ανανεώνει το δικό της
/// ίχνος κάθε [heartbeatInterval]· «συνδεδεμένος» σημαίνει ίχνος νεότερο από
/// [onlineWindow]. Απότομο κλείσιμο ή πτώση δικτύου αφήνει το ίχνος να παλιώσει
/// μόνο του, οπότε για λίγα λεπτά κάποιος φαίνεται συνδεδεμένος ενώ δεν είναι.
/// Αυτό λέγεται ρητά στην οθόνη· δεν κρύβεται πίσω από πράσινη κουκκίδα.
class OperatorPresence {
  const OperatorPresence({
    required this.operatorId,
    required this.station,
    required this.lastSeenAt,
  });

  /// Κάθε πότε η ανοιχτή εφαρμογή ξαναγράφει το ίχνος της.
  ///
  /// Η βάση ζει σε δικτυακό φάκελο: αραιό αρκετά ώστε η κίνηση να είναι
  /// αμελητέα, πυκνό αρκετά ώστε η ένδειξη να μην είναι ψέμα.
  static const Duration heartbeatInterval = Duration(minutes: 1);

  /// Πόσο φρέσκο πρέπει να είναι το ίχνος για να λέγεται «συνδεδεμένος».
  ///
  /// Τριπλάσιο του [heartbeatInterval]: αντέχει ένα χαμένο χτύπο και μια
  /// στιγμιαία διακοπή δικτύου χωρίς να σβήνει κάποιον που δουλεύει κανονικά.
  static const Duration onlineWindow = Duration(minutes: 3);

  final int operatorId;

  /// Το όνομα του υπολογιστή, όπως το δίνει το σύστημα.
  final String station;

  final DateTime lastSeenAt;

  /// Θεωρείται συνδεδεμένος τη στιγμή [now];
  ///
  /// Το [now] δίνεται πάντα απ' έξω: μια εσωτερική `DateTime.now()` θα έκανε
  /// τον κανόνα αδύνατο να ελεγχθεί και θα έδινε δεύτερο ρολόι στην οθόνη.
  bool isOnlineAt(DateTime now) => now.difference(lastSeenAt) < onlineWindow;

  /// `null` όταν η γραμμή δεν διαβάζεται — χαλασμένη εγγραφή δεν ρίχνει οθόνη.
  static OperatorPresence? fromMap(Map<String, Object?> map) {
    final id = map['operator_id'];
    final station = (map['station'] as String?)?.trim() ?? '';
    final seen = DateTime.tryParse((map['last_seen_at'] as String?) ?? '');
    if (id is! int || station.isEmpty || seen == null) return null;
    return OperatorPresence(operatorId: id, station: station, lastSeenAt: seen);
  }
}
