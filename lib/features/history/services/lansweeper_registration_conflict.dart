import '../../../core/database/audit_diff_helper.dart';
import '../../../core/database/audit_service.dart';
import '../../../core/utils/conflict_actor_text.dart';
import '../../calls/models/call_model.dart';
import '../models/lansweeper_sync_state.dart';

/// Η κατάσταση Lansweeper μιας κλήσης **όπως τη διάβασε η οθόνη** — η αφετηρία.
///
/// Μόνο δύο πεδία, επίτηδες: οι σημάνσεις κατάστασης γράφουν αποκλειστικά αυτά,
/// οπότε μια αλλαγή κειμένου από συνάδελφο δεν είναι διένεξη για εμάς. Ο κανόνας
/// είναι ο ίδιος με τις υπόλοιπες οντότητες — ό,τι δεν άλλαξε δεν είναι διένεξη.
class LansweeperRegistrationBaseline {
  const LansweeperRegistrationBaseline({this.state, this.ticketId});

  /// Η αφετηρία από την κλήση που κρατά η οθόνη (ουρά Αναφοράς, γραμμή Ιστορικού).
  factory LansweeperRegistrationBaseline.ofCall(CallModel call) =>
      LansweeperRegistrationBaseline(
        state: call.lansweeperState,
        ticketId: call.lansweeperMainTicketId,
      );

  final String? state;
  final String? ticketId;

  String get normalizedState => LansweeperSyncState.normalize(state);
  String get normalizedTicketId => (ticketId ?? '').trim();
}

/// Τι πάει να γράψει η ενέργειά μου, όπως το περιγράφει το ίδιο το payload.
class LansweeperRegistrationAttempt {
  const LansweeperRegistrationAttempt({
    required this.state,
    required this.touchesTicketId,
    this.ticketId,
  });

  final String state;

  /// `false` = η εγγραφή αφήνει τον αριθμό αιτήματος όπως τον βρει.
  ///
  /// Χωρίς αυτή τη διάκριση, η «Εξαίρεση» —που δεν αγγίζει αριθμό— θα φαινόταν
  /// να τον σβήνει, και θα ρωτούσε για ζημιά που δεν πρόκειται να κάνει.
  final bool touchesTicketId;

  /// Κενό ή `null` με [touchesTicketId] `true` σημαίνει «καθάρισε τον αριθμό».
  final String? ticketId;

  String get normalizedState => LansweeperSyncState.normalize(state);
  String get normalizedTicketId => (ticketId ?? '').trim();
}

/// Κάποιος άλλος άλλαξε την κατάσταση Lansweeper μετά την ανάγνωσή μου.
///
/// Η ζημιά δεν είναι χαμένο κείμενο: το «κύριο» αίτημα της κλήσης αντικαθίσταται
/// από το δικό μου, και το αίτημα του συναδέλφου μένει ορφανό στο Lansweeper —
/// σύστημα που η εφαρμογή δεν μπορεί να καθαρίσει. Το ιστορικό εξωτερικών
/// συνδέσμων κρατά και τα δύο, αλλά κανείς δεν ειδοποιείται ότι χρειάζεται.
class LansweeperRegistrationConflict {
  const LansweeperRegistrationConflict({
    required this.expected,
    required this.fresh,
    required this.attempted,
    this.changedBy,
    this.changedAt,
  });

  /// Η εικόνα που είχε η οθόνη μου — η αφετηρία.
  final LansweeperRegistrationBaseline expected;

  /// Η κλήση όπως είναι **τώρα** στη βάση.
  final LansweeperRegistrationBaseline fresh;

  /// Τι πήγε να γραφτεί.
  final LansweeperRegistrationAttempt attempted;

  /// Ποιος έκανε την ξένη αλλαγή, από το Ιστορικό· `null` όταν δεν βρεθεί.
  final String? changedBy;

  /// Πότε έγινε η ξένη αλλαγή, από το Ιστορικό.
  final DateTime? changedAt;

  /// Η ίδια διένεξη, ντυμένη με το «ποιος και πότε».
  ///
  /// Η ταυτότητα ζητείται μόνο αφού διαπιστωθεί διένεξη, ώστε η κανονική
  /// σήμανση —η συντριπτική πλειοψηφία— να μην πληρώνει ούτε ένα ερώτημα.
  LansweeperRegistrationConflict describedBy({String? who, DateTime? at}) =>
      LansweeperRegistrationConflict(
        expected: expected,
        fresh: fresh,
        attempted: attempted,
        changedBy: who,
        changedAt: at,
      );

  String get freshState => fresh.normalizedState;
  String get freshTicketId => fresh.normalizedTicketId;
  String get attemptedTicketId => attempted.normalizedTicketId;

  /// Κουνήθηκε η κλήση από τότε που τη διάβασε η οθόνη μου;
  bool get someoneElseMoved =>
      expected.normalizedState != fresh.normalizedState ||
      expected.normalizedTicketId != fresh.normalizedTicketId;

  /// Θα άλλαζε η εγγραφή μου κάτι απ' όσα βρίσκει τώρα στη βάση;
  ///
  /// Όταν δύο άνθρωποι γράφουν **το ίδιο** (ίδιος αριθμός αιτήματος, ίδια
  /// κατάσταση) δεν υπάρχει τίποτα να αποφασίσει κανείς — και ένας διάλογος
  /// εκεί θα ήταν σκέτος θόρυβος πάνω στην καθημερινή ρουτίνα των 13:00.
  bool get wouldChangeStored {
    if (attempted.normalizedState != fresh.normalizedState) return true;
    if (!attempted.touchesTicketId) return false;
    return attempted.normalizedTicketId != fresh.normalizedTicketId;
  }

  /// Άξιζει να σταματήσει η εγγραφή και να ρωτηθεί ο άνθρωπος;
  bool get isConflict => someoneElseMoved && wouldChangeStored;

  /// Ο συνάδελφος καταχώρησε την κλήση στο Lansweeper στο μεταξύ;
  bool get otherRegistered =>
      expected.normalizedTicketId.isEmpty &&
      fresh.normalizedTicketId.isNotEmpty;

  /// Η εγγραφή μου θα αφήσει ορφανό το αίτημα του συναδέλφου;
  bool get losesForeignTicket =>
      fresh.normalizedTicketId.isNotEmpty &&
      attempted.touchesTicketId &&
      attempted.normalizedTicketId != fresh.normalizedTicketId;

  /// Τι άγγιξε ο άλλος, με τις ετικέτες που ήδη χρησιμοποιεί το Ιστορικό.
  ///
  /// Δεύτερος κατάλογος ονομάτων εδώ θα απέκλινε σιωπηλά: η οθόνη θα έλεγε
  /// «κατάσταση Lansweeper» και ο διάλογος «lansweeper state».
  List<String> get changedFields {
    final labels = <String>[];
    if (expected.normalizedState != fresh.normalizedState) {
      labels.add(
        AuditDiffHelper.fieldTitleLabel(
          AuditEntityTypes.call,
          'lansweeper_state',
        ),
      );
    }
    if (expected.normalizedTicketId != fresh.normalizedTicketId) {
      labels.add(
        AuditDiffHelper.fieldTitleLabel(
          AuditEntityTypes.call,
          'lansweeper_main_ticket_id',
        ),
      );
    }
    return labels;
  }

  /// «Ο χρήστης «Βασίλης» καταχώρησε αυτή την κλήση στο Lansweeper στις 13:10.»
  String headline({DateTime? now}) {
    final moment = now ?? DateTime.now();
    final verb = otherRegistered
        ? 'καταχώρησε αυτή την κλήση στο Lansweeper'
        : 'άλλαξε την κατάσταση Lansweeper αυτής της κλήσης';
    return '${conflictActorName(changedBy)} $verb'
        '${conflictMomentSuffix(changedAt, now: moment)}.';
  }

  /// Τι χάνεται αν επιμείνω στη δική μου εικόνα.
  String get overwriteWarning {
    if (losesForeignTicket) {
      final ticket = fresh.normalizedTicketId;
      final mine = attempted.normalizedTicketId;
      final fate = mine.isEmpty
          ? 'θα σβηστεί ο αριθμός αιτήματος $ticket'
          : 'ο αριθμός αιτήματος $ticket θα αντικατασταθεί από τον $mine';
      return 'Αν συνεχίσετε, $fate — το αίτημα $ticket θα μείνει ορφανό στο '
          'Lansweeper και δεν σβήνεται από την εφαρμογή.';
    }
    final fields = changedFields;
    if (fields.isEmpty) {
      return 'Αν συνεχίσετε, η ξένη αλλαγή θα αντικατασταθεί.';
    }
    return 'Αν συνεχίσετε, θα χαθεί ό,τι άλλαξε: ${fields.join(', ')}.';
  }
}

/// Πετάγεται από το repository **πριν** γραφτεί τίποτα.
class LansweeperRegistrationStaleException implements Exception {
  const LansweeperRegistrationStaleException(this.conflict);

  final LansweeperRegistrationConflict conflict;

  @override
  String toString() =>
      'Η κατάσταση Lansweeper της κλήσης άλλαξε από άλλον χρήστη.';
}
