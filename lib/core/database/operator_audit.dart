import 'package:sqflite_common/sqlite_api.dart';

import '../models/app_permission.dart';
import '../models/operator.dart';
import 'audit_service.dart';

/// Τι αφήνει πίσω του στο Ιστορικό ένα προφίλ χειριστή.
///
/// Ζει χωριστά από τους κανόνες της διαχείρισης: εκείνοι αποφασίζουν **αν**
/// επιτρέπεται μια αλλαγή, εδώ γράφεται **τι** έγινε. Ο διαχωρισμός επιτρέπει
/// να ελεγχθεί το περιεχόμενο της εγγραφής χωρίς να στηθεί οθόνη.
///
/// **Γιατί υπάρχει καν.** Ως τη Φάση 4 καμία αλλαγή προφίλ δεν άφηνε ίχνος:
/// ποιος έγινε διαχειριστής, ποιος πήρε ή έχασε δικαίωμα, πότε απενεργοποιήθηκε
/// κάποιος — τίποτα. Είναι ακριβώς η πληροφορία που ζητά κανείς όταν κάτι πάει
/// στραβά, και ήταν η μόνη που δεν καταγραφόταν πουθενά.
abstract final class OperatorAudit {
  /// Νέο προφίλ. Καταγράφονται τα στοιχεία του και **μόνο** τα δικαιώματα που
  /// ορίστηκαν ρητά — τα υπόλοιπα είναι προεπιλογές, και μια λίστα «Ναι» που
  /// δεν αποφάσισε κανείς θα έπνιγε τα δύο που όντως αποφασίστηκαν.
  static Future<void> logCreated(DatabaseExecutor db, Operator created) async {
    await AuditService.log(
      db,
      action: AuditActions.createOperator,
      userPerforming: await AuditService.performingUser(db),
      entityType: AuditEntityTypes.operatorProfile,
      entityId: created.id,
      entityName: created.displayName,
      details: 'Δημιουργία χρήστη «${created.displayName}»',
      newValues: <String, dynamic>{
        ..._identityValues(created),
        for (final entry in created.permissionOverrides.entries)
          if (AppPermission.byKey(entry.key) != null)
            'permission_${entry.key}': entry.value,
      },
    );
  }

  /// Αλλαγή προφίλ. Γράφονται και οι δύο πλευρές κάθε πεδίου, ώστε το «Τι
  /// άλλαξε» να διαβάζεται ως «από τι σε τι» — και ό,τι έμεινε ίδιο να πέφτει
  /// έξω μόνο του.
  ///
  /// Τα δικαιώματα συγκρίνονται στην **ισχύουσα** τιμή τους, όχι στην
  /// αποθηκευμένη παράκαμψη: όταν κάποιος αφαιρεί μια παράκαμψη που έτυχε να
  /// συμφωνεί με την προεπιλογή, τίποτα δεν άλλαξε στην πράξη και δεν έχει
  /// θέση στο Ιστορικό.
  ///
  /// Όταν κανένα πεδίο δεν άλλαξε, δεν γράφεται τίποτα: μια εγγραφή που λέει
  /// «άλλαξε ο Χ» χωρίς να λέει τι, είναι θόρυβος που θάβει τις αληθινές.
  static Future<void> logUpdated(
    DatabaseExecutor db, {
    required Operator before,
    required Operator after,
  }) async {
    final oldValues = auditValues(before);
    final newValues = auditValues(after);

    final changed = <String>{
      ...oldValues.keys,
      ...newValues.keys,
    }.where((key) => !AuditService.valuesEqual(oldValues[key], newValues[key]));
    if (changed.isEmpty) return;

    await AuditService.log(
      db,
      action: AuditActions.modifyOperator,
      userPerforming: await AuditService.performingUser(db),
      entityType: AuditEntityTypes.operatorProfile,
      entityId: after.id ?? before.id,
      entityName: after.displayName,
      details: 'Τροποποίηση χρήστη «${after.displayName}»',
      oldValues: <String, dynamic>{
        for (final key in changed) key: oldValues[key],
      },
      newValues: <String, dynamic>{
        for (final key in changed) key: newValues[key],
      },
    );
  }

  /// Το προφίλ όπως το διαβάζει το Ιστορικό: ταυτότητα + κάθε δικαίωμα στην
  /// τιμή που **ισχύει** σήμερα γι' αυτόν τον χρήστη.
  static Map<String, dynamic> auditValues(Operator operator) {
    return <String, dynamic>{
      ..._identityValues(operator),
      for (final permission in AppPermission.values)
        'permission_${permission.key}': effectivePermission(
          operator,
          permission,
        ),
    };
  }

  /// Αν το δικαίωμα ισχύει για το προφίλ: η ρητή παράκαμψη αν υπάρχει, αλλιώς
  /// η προεπιλογή του καταλόγου.
  static bool effectivePermission(Operator operator, AppPermission permission) {
    return operator.permissionOverrides[permission.key] ??
        permission.allowedByDefault;
  }

  /// Ποιος άγγιξε τελευταίος αυτό το προφίλ, και πότε.
  ///
  /// Η γραμμή `operators` δεν κρατά «ποιος με άλλαξε» — το κρατά μόνο το
  /// Ιστορικό. Χρησιμοποιείται όταν έχει διαπιστωθεί διένεξη, ώστε ο διάλογος να
  /// λέει «ο Βασίλης» και όχι «κάποιος». Πατά στο υπάρχον ευρετήριο
  /// `(entity_type, entity_id)`.
  ///
  /// **Η αποτυχία είναι σιωπή:** η ταυτότητα είναι συμπληρωματική, και μια
  /// διένεξη πρέπει να αναφέρεται ακόμη κι όταν το Ιστορικό δεν απαντά.
  static Future<({String? who, DateTime? at})> lastActorFor(
    DatabaseExecutor db,
    int operatorId,
  ) async {
    try {
      final rows = await db.query(
        'audit_log',
        columns: ['user_performing', 'timestamp'],
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [AuditEntityTypes.operatorProfile, operatorId],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (rows.isEmpty) return (who: null, at: null);
      final who = (rows.first['user_performing'] as String?)?.trim();
      final at = DateTime.tryParse((rows.first['timestamp'] as String?) ?? '');
      return (who: (who == null || who.isEmpty) ? null : who, at: at);
    } catch (_) {
      return (who: null, at: null);
    }
  }

  static Map<String, dynamic> _identityValues(Operator operator) {
    return <String, dynamic>{
      'display_name': operator.displayName,
      'windows_account': operator.windowsAccount,
      'is_admin': operator.isAdmin,
      'is_active': operator.isActive,
    };
  }
}
