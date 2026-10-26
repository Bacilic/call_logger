import 'dart:convert';

/// Τι γράφει ένα αίτημα Lansweeper στον τίτλο και στην περιγραφή του — όσο το
/// ξέρει η εφαρμογή, δηλαδή όπως το έστειλε η ίδια την τελευταία φορά.
///
/// Χρησιμεύει ως μέτρο για το «άλλαξε κάτι;» σε αίτημα που υπάρχει ήδη: ο
/// τίτλος και το πρόβλημα ξαναστέλνονται μόνο όταν η φόρμα διαφέρει από αυτό.
/// Το μέτρο **δεν** είναι τα κείμενα της κλήσης: το «Αποθήκευση στην κλήση» και
/// η καρτέλα Επεξεργασίας τα αλλάζουν χωρίς να στείλουν τίποτα, οπότε μια
/// διόρθωση εκεί δεν θα έφτανε ποτέ στο αίτημα.
class LansweeperTicketTexts {
  const LansweeperTicketTexts({required this.subject, required this.problem});

  /// Το `Subject` του αιτήματος.
  final String subject;

  /// Το πρόβλημα όπως γράφτηκε στο `Description`, πριν τη μορφοποίηση HTML.
  final String problem;

  static const String _subjectKey = 'ticketSubject';
  static const String _problemKey = 'ticketProblem';

  /// Τα πεδία που μπαίνουν στα μεταδεδομένα του συνδέσμου κλήσης–αιτήματος.
  Map<String, String> toMetadata() => <String, String>{
    _subjectKey: subject,
    _problemKey: problem,
  };

  /// Τα τελευταία γνωστά κείμενα του αιτήματος [ticketId], από το ιστορικό
  /// συνδέσμων μιας κλήσης (νεότερος πρώτος, όπως το επιστρέφει το
  /// repository). `null` όταν κανένας σύνδεσμος δεν τα κατέγραψε.
  static LansweeperTicketTexts? latestFromLinks(
    List<Map<String, Object?>> links,
    String ticketId,
  ) {
    final wanted = ticketId.trim();
    for (final link in links) {
      if ('${link['external_id'] ?? ''}'.trim() != wanted) continue;
      final metadata = _decodeMetadata(link['metadata']);
      if (metadata == null) continue;
      final subject = metadata[_subjectKey];
      final problem = metadata[_problemKey];
      if (subject is String && problem is String) {
        return LansweeperTicketTexts(subject: subject, problem: problem);
      }
    }
    return null;
  }

  /// Η στήλη `metadata` είναι κείμενο JSON· χαλασμένο ή κενό = «δεν ξέρουμε».
  static Map<Object?, Object?>? _decodeMetadata(Object? raw) {
    if (raw is Map) return raw;
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
