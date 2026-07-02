import 'package:flutter/foundation.dart';

import 'database_integrity_finding.dart';

/// Ενέργεια επιδιόρθωσης που εκτελεί το backend.
enum IntegrityFixAction {
  deleteJunction,
  softDeletePhone,
  linkPhoneToDepartment,
  linkPhoneToUser,
  setFkNull,
  reassignFk,
  rebuildSearchIndex,
  fixDepartmentNameKey,
  syncTaskTimestamps,
  rebuildAuditSearchText,
  deleteCallExternalLink,
}

/// Τρόπος UI ανά τύπο ελέγχου.
enum IntegrityFixUiMode {
  /// Μόνο επιβεβαίωση — επιτρέπεται bulk fix.
  confirmOnly,

  /// Απαιτεί επιλογή χρήστη (αποσύνδεση / νέα τιμή).
  choiceRequired,

  /// Δεν επιτρέπεται inline fix (π.χ. PRAGMA corruption).
  blockout,
}

extension IntegrityCheckTypeFixUi on IntegrityCheckType {
  IntegrityFixUiMode get fixUiMode => switch (this) {
        IntegrityCheckType.pragmaQuickCheck => IntegrityFixUiMode.blockout,
        IntegrityCheckType.orphanPhone => IntegrityFixUiMode.choiceRequired,
        IntegrityCheckType.usersWithoutDepartment =>
          IntegrityFixUiMode.choiceRequired,
        IntegrityCheckType.usersInvalidDepartment =>
          IntegrityFixUiMode.choiceRequired,
        _ => IntegrityFixUiMode.confirmOnly,
      };

  bool get allowsBulkFix => fixUiMode == IntegrityFixUiMode.confirmOnly;

  /// Συγκεντρωτικό μήνυμα επιβεβαίωσης bulk (ελληνικά).
  String bulkConfirmMessage(int count) {
    assert(count > 0);
    return switch (this) {
      IntegrityCheckType.callsMissingSearchIndex =>
        'Θέλετε να αναδημιουργηθεί το ευρετήριο αναζήτησης για τις $count κλήσεις;',
      IntegrityCheckType.tasksMissingSearchIndex =>
        'Θέλετε να αναδημιουργηθεί το ευρετήριο αναζήτησης για τις $count εκκρεμότητες;',
      IntegrityCheckType.departmentsInvalidNameKey =>
        'Θέλετε να διορθωθεί το name_key για τα $count τμήματα;',
      IntegrityCheckType.orphanCallExternalLinks =>
        'Θέλετε να διαγραφούν οι $count ορφανοί εξωτερικοί σύνδεσμοι κλήσεων;',
      IntegrityCheckType.orphanUserPhones =>
        'Θέλετε να γίνει εκκαθάριση και των $count ορφανών συνδέσεων υπαλλήλου–τηλεφώνου;',
      IntegrityCheckType.orphanDepartmentPhones =>
        'Θέλετε να γίνει εκκαθάριση και των $count ορφανών συνδέσεων τμήματος–τηλεφώνου;',
      IntegrityCheckType.orphanUserEquipment =>
        'Θέλετε να γίνει εκκαθάριση και των $count ορφανών συνδέσεων εξοπλισμού–υπαλλήλου;',
      IntegrityCheckType.tasksTemporalInconsistency =>
        'Θέλετε να συγχρονιστούν οι ημερομηνίες για τις $count εκκρεμότητες;',
      IntegrityCheckType.auditMissingSearchText =>
        'Θέλετε να ανακατασκευαστεί το κείμενο αναζήτησης για τις $count εγγραφές audit;',
      IntegrityCheckType.tasksInvalidCall =>
        'Θέλετε να γίνει εκκαθάριση της κλήσης για τις $count εκκρεμότητες με άκυρη αναφορά;',
      IntegrityCheckType.callsDeletedLinkedEntities =>
        'Θέλετε να γίνει εκκαθάριση των $count ανύπαρκτων αναφορών στις κλήσεις; '
        'Το αποθηκευμένο κείμενο κάθε κλήσης διατηρείται.',
      IntegrityCheckType.tasksDeletedLinkedEntities =>
        'Θέλετε να γίνει εκκαθάριση των $count ανύπαρκτων αναφορών στις εκκρεμότητες; '
        'Το αποθηκευμένο κείμενο κάθε εκκρεμότητας διατηρείται.',
      IntegrityCheckType.phoneInvalidDepartment =>
        'Θέλετε να αποσυνδεθούν τα $count τηλέφωνα από ανύπαρκτα τμήματα;',
      IntegrityCheckType.equipmentInvalidDepartment =>
        'Θέλετε να αποσυνδεθούν οι $count εξοπλισμοί από ανύπαρκτα τμήματα;',
      IntegrityCheckType.departmentInvalidFloor =>
        'Θέλετε να καθαριστεί ο όροφος χάρτη για τα $count τμήματα;',
      _ => 'Θέλετε να επιδιορθωθούν τα $count ευρήματα;',
    };
  }

  /// Μήνυμα επιβεβαίωσης για μεμονωμένο εύρημα confirm-only.
  String singleConfirmMessage(DatabaseIntegrityFinding finding) {
    return switch (this) {
      IntegrityCheckType.callsMissingSearchIndex =>
        'Θέλετε να αναδημιουργηθεί το ευρετήριο αναζήτησης για αυτή την κλήση;',
      IntegrityCheckType.tasksMissingSearchIndex =>
        'Θέλετε να αναδημιουργηθεί το ευρετήριο αναζήτησης για αυτή την εκκρεμότητα;',
      IntegrityCheckType.departmentsInvalidNameKey =>
        'Θέλετε να διορθωθεί το name_key αυτού του τμήματος;',
      IntegrityCheckType.orphanCallExternalLinks =>
        'Θέλετε να διαγραφεί αυτός ο ορφανός εξωτερικός σύνδεσμος κλήσης;',
      IntegrityCheckType.orphanUserPhones =>
        'Θέλετε να γίνει εκκαθάριση αυτής της ορφανής σύνδεσης υπαλλήλου–τηλεφώνου;',
      IntegrityCheckType.orphanDepartmentPhones =>
        'Θέλετε να γίνει εκκαθάριση αυτής της ορφανής σύνδεσης τμήματος–τηλεφώνου;',
      IntegrityCheckType.orphanUserEquipment =>
        'Θέλετε να γίνει εκκαθάριση αυτής της ορφανής σύνδεσης εξοπλισμού–υπαλλήλου;',
      IntegrityCheckType.tasksTemporalInconsistency =>
        'Θέλετε να συγχρονιστούν οι ημερομηνίες αυτής της εκκρεμότητας (updated_at = created_at);',
      IntegrityCheckType.auditMissingSearchText =>
        'Θέλετε να ανακατασκευαστεί το κείμενο αναζήτησης αυτής της εγγραφής audit;',
      IntegrityCheckType.tasksInvalidCall =>
        '${finding.description} Θα γίνει εκκαθάριση της κλήσης.',
      IntegrityCheckType.callsDeletedLinkedEntities ||
      IntegrityCheckType.tasksDeletedLinkedEntities =>
        '${finding.description} Θα γίνει εκκαθάριση της αναφοράς· '
        'το αποθηκευμένο κείμενο (snapshot) διατηρείται.',
      IntegrityCheckType.phoneInvalidDepartment =>
        '${finding.description} Θα γίνει αποσύνδεση από το ανύπαρκτο τμήμα.',
      IntegrityCheckType.equipmentInvalidDepartment =>
        '${finding.description} Θα γίνει αποσύνδεση από το ανύπαρκτο τμήμα.',
      IntegrityCheckType.departmentInvalidFloor =>
        '${finding.description} Θα καθαριστεί η θέση στον χάρτη.',
      _ => finding.description,
    };
  }
}

/// Απόφαση χρήστη μετά το dialog — καθορίζει την ενέργεια επιδιόρθωσης.
sealed class IntegrityFixDecision {
  const IntegrityFixDecision();
}

/// Απλή επιβεβαίωση (confirm-only τύποι).
final class IntegrityFixConfirm extends IntegrityFixDecision {
  const IntegrityFixConfirm();
}

/// Σύνδεση ορφανού τηλεφώνου με τμήμα.
final class IntegrityFixLinkPhoneToDepartment extends IntegrityFixDecision {
  const IntegrityFixLinkPhoneToDepartment(this.departmentId);

  final int departmentId;
}

/// Σύνδεση ορφανού τηλεφώνου με χρήστη.
final class IntegrityFixLinkPhoneToUser extends IntegrityFixDecision {
  const IntegrityFixLinkPhoneToUser(this.userId);

  final int userId;
}

/// Ανάθεση τμήματος σε χρήστη χωρίς τμήμα.
final class IntegrityFixAssignDepartment extends IntegrityFixDecision {
  const IntegrityFixAssignDepartment(this.departmentId);

  final int departmentId;
}

/// Διαγραφή ορφανού τηλεφώνου (soft delete).
final class IntegrityFixSoftDeletePhone extends IntegrityFixDecision {
  const IntegrityFixSoftDeletePhone();
}

/// Διαγραφή υπαλλήλου χωρίς τμήμα (soft delete).
final class IntegrityFixSoftDeleteUser extends IntegrityFixDecision {
  const IntegrityFixSoftDeleteUser();
}

/// Αποτέλεσμα μίας επιδιόρθωσης.
sealed class IntegrityFixResult {
  const IntegrityFixResult();

  bool get success => this is IntegrityFixSuccess;
}

final class IntegrityFixSuccess extends IntegrityFixResult {
  const IntegrityFixSuccess({this.message});

  final String? message;
}

final class IntegrityFixFailure extends IntegrityFixResult {
  const IntegrityFixFailure(this.message);

  final String message;
}

/// Κλείδωμα βάσης (SQLITE_BUSY) — το UI εμφανίζει retry dialog.
final class IntegrityFixLockFailure extends IntegrityFixResult {
  const IntegrityFixLockFailure({
    required this.dbPath,
    required this.message,
    this.findingKey,
  });

  final String dbPath;
  final String message;
  final String? findingKey;
}

/// Αποτέλεσμα μαζικής επιδιόρθωσης.
@immutable
class IntegrityBulkFixResult {
  const IntegrityBulkFixResult({
    required this.results,
    required this.findings,
  });

  final List<IntegrityFixResult> results;
  final List<DatabaseIntegrityFinding> findings;

  int get successCount => results.whereType<IntegrityFixSuccess>().length;

  int get failureCount => results.whereType<IntegrityFixFailure>().length;

  int get lockFailureCount => results.whereType<IntegrityFixLockFailure>().length;

  bool get anySuccess => successCount > 0;

  bool get hasLockFailures => lockFailureCount > 0;

  List<DatabaseIntegrityFinding> get lockFailureFindings {
    final out = <DatabaseIntegrityFinding>[];
    for (var i = 0; i < results.length; i++) {
      if (results[i] is IntegrityFixLockFailure) {
        out.add(findings[i]);
      }
    }
    return out;
  }
}
