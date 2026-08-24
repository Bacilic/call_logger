import '../../../core/database/audit_diff_helper.dart';
import '../../../core/database/audit_service.dart';
import '../../../core/database/calls_audit_line.dart';
import '../models/call_model.dart';

/// Η κλήση άλλαξε από άλλον, μετά την ανάγνωσή της.
///
/// Η επεξεργασία κλήσης γράφει **ολόκληρη** τη γραμμή από την εικόνα που είχε
/// φορτώσει ο διάλογος — μαζί με τα πεδία Lansweeper. Χωρίς αυτόν τον έλεγχο,
/// μια διόρθωση ορθογραφικού επανέφερε στην ουρά κλήση που ο συνάδελφος είχε
/// ήδη καταχωρήσει, και το επόμενο πέρασμα άνοιγε **δεύτερο αίτημα** στο
/// Lansweeper. Εκείνο δεν σβήνεται από την εφαρμογή.
class CallSaveConflict {
  const CallSaveConflict({
    required this.expected,
    required this.fresh,
    required this.attempted,
    this.changedBy,
    this.changedAt,
  });

  /// Η εικόνα που είχε φορτώσει ο διάλογος — η αφετηρία.
  final CallModel expected;

  /// Η κλήση όπως είναι **τώρα** στη βάση.
  final CallModel fresh;

  /// Η κλήση που πήγε να γραφτεί.
  final CallModel attempted;

  /// Ποιος έκανε την ξένη αλλαγή, από το Ιστορικό· `null` όταν δεν βρεθεί.
  final String? changedBy;

  /// Πότε έγινε η ξένη αλλαγή, από το Ιστορικό.
  final DateTime? changedAt;

  /// Οι τιμές που συγκρίνονται, με **όλα** τα πεδία παρόντα.
  ///
  /// Δεν χρησιμοποιείται το `toMap()`: εκείνο παραλείπει τα κενά πεδία, οπότε
  /// «είχε τιμή και σβήστηκε» θα περνούσε για «δεν άλλαξε τίποτα».
  static Map<String, Object?> comparableValues(CallModel call) {
    return <String, Object?>{
      'date': call.date,
      'time': call.time,
      'caller_id': call.callerId,
      'equipment_id': call.equipmentId,
      'caller_text': call.callerText,
      'phone_text': call.phoneText,
      'department_text': call.departmentText,
      'equipment_text': call.equipmentText,
      'issue': call.issue,
      'solution': call.solution,
      'category_text': call.category,
      'category_id': call.categoryId,
      'status': call.status,
      'duration': call.duration,
      'is_priority': call.isPriority,
      'lansweeper_state': call.lansweeperState,
      'lansweeper_main_ticket_id': call.lansweeperMainTicketId,
      'lansweeper_last_sync_at': call.lansweeperLastSyncAt,
      'is_deleted': call.isDeleted ? 1 : 0,
    };
  }

  /// Τι άγγιξε ο άλλος, με τις ετικέτες που ήδη χρησιμοποιεί το Ιστορικό.
  ///
  /// Δεύτερος κατάλογος ονομάτων εδώ θα απέκλινε σιωπηλά: η οθόνη θα έλεγε
  /// «κατάσταση Lansweeper» και ο διάλογος «lansweeper state».
  ///
  /// Συγκρίνεται η **αφετηρία** με τη βάση, όχι η πρόθεσή μου με τη βάση —
  /// αλλιώς οι δικές μου αλλαγές θα εμφανίζονταν ως ξένες.
  List<String> get changedFields {
    final before = comparableValues(expected);
    final after = comparableValues(fresh);
    final labels = <String>[];
    for (final field in kCallAuditFields) {
      if (!before.containsKey(field)) continue;
      if ('${before[field] ?? ''}' == '${after[field] ?? ''}') continue;
      final label = AuditDiffHelper.fieldTitleLabel(
        AuditEntityTypes.call,
        field,
      );
      if (!labels.contains(label)) labels.add(label);
    }
    return labels;
  }

  /// Άλλαξε κάτι που η αποθήκευσή μου θα έγραφε από πάνω;
  bool get hasChanges => changedFields.isNotEmpty;

  /// Ο συνάδελφος καταχώρησε την κλήση στο Lansweeper στο μεταξύ;
  ///
  /// Ξεχωρίζει επίτηδες από τις υπόλοιπες αλλαγές: το πέρασμα από πάνω εδώ δεν
  /// χάνει κείμενο — **ανοίγει δεύτερο αίτημα** σε σύστημα που η εφαρμογή δεν
  /// μπορεί να καθαρίσει.
  bool get otherRegisteredInLansweeper {
    final wasSent = (expected.lansweeperMainTicketId ?? '').trim();
    final isSent = (fresh.lansweeperMainTicketId ?? '').trim();
    return wasSent.isEmpty && isSent.isNotEmpty;
  }

  /// «Ο χρήστης «Βασίλης» άλλαξε αυτή την κλήση στις 13:10.»
  String headline({DateTime? now}) {
    final moment = now ?? DateTime.now();
    final who = (changedBy == null || changedBy!.trim().isEmpty)
        ? 'Κάποιος άλλος'
        : 'Ο χρήστης «${changedBy!.trim()}»';
    final when = changedAt == null ? '' : ' στις ${_stamp(changedAt!, moment)}';
    final verb = otherRegisteredInLansweeper
        ? 'καταχώρησε αυτή την κλήση στο Lansweeper'
        : 'άλλαξε αυτή την κλήση';
    return '$who $verb$when.';
  }

  /// Τι χάνεται αν κρατήσω τη δική μου εικόνα.
  String get overwriteWarning {
    if (otherRegisteredInLansweeper) {
      final ticket = (fresh.lansweeperMainTicketId ?? '').trim();
      return 'Αν κρατήσετε τη δική σας εικόνα, η κλήση θα ξαναγίνει '
          'ακαταχώρητη και θα χαθεί ο αριθμός αιτήματος $ticket — το επόμενο '
          'πέρασμα θα ανοίξει ΔΕΥΤΕΡΟ αίτημα στο Lansweeper, που δεν σβήνεται '
          'από την εφαρμογή.';
    }
    final fields = changedFields;
    if (fields.isEmpty) {
      return 'Αν κρατήσετε τη δική σας εικόνα, η ξένη αλλαγή θα αντικατασταθεί.';
    }
    return 'Αν κρατήσετε τη δική σας εικόνα, θα χαθεί ό,τι άλλαξε: '
        '${fields.join(', ')}.';
  }

  static String _stamp(DateTime moment, DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${two(moment.hour)}:${two(moment.minute)}';
    final sameDay =
        moment.year == now.year &&
        moment.month == now.month &&
        moment.day == now.day;
    return sameDay ? time : '${two(moment.day)}/${two(moment.month)} $time';
  }
}

/// Πετάγεται από το repository **πριν** γραφτεί τίποτα.
class CallStaleException implements Exception {
  const CallStaleException(this.conflict);

  final CallSaveConflict conflict;

  @override
  String toString() =>
      'Η κλήση άλλαξε από άλλον χρήστη μετά την ανάγνωσή της.';
}
