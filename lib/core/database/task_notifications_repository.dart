import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/tasks/models/task_notification.dart';
import 'database_helper.dart';

/// Η ουρά «τι περιμένει να δει ο καθένας» για τις εκκρεμότητές του.
///
/// **Ουρά, όχι ιστορικό.** Η γραμμή υπάρχει όσο δεν έχει ιδωθεί και σβήνεται
/// μόλις ο άνθρωπος τη δει. Το μόνιμο «ποιος τι έκανε και πότε» ζει στο
/// `audit_log` και δεν διπλογράφεται εδώ — αλλιώς θα υπήρχαν δύο αλήθειες που
/// θα απέκλιναν.
class TaskNotificationsRepository {
  Future<Database> get _db async => DatabaseHelper.instance.database;

  /// Αφήνει μία ειδοποίηση, **μέσα στη συναλλαγή της ίδιας της πράξης**.
  ///
  /// Γι' αυτό δέχεται [executor] και δεν ανοίγει δική της: ή γράφονται και τα
  /// δύο ή κανένα. Μια ανάθεση χωρίς ειδοποίηση θα ήταν αόρατη για πάντα, και
  /// μια ειδοποίηση για ανάθεση που δεν έγινε θα έστελνε κάποιον να ψάξει
  /// εκκρεμότητα που δεν του ανήκει.
  ///
  /// **Κανείς δεν ειδοποιεί τον εαυτό του**: ο έλεγχος μπαίνει εδώ και όχι
  /// στους καλούντες, ώστε μια νέα πύλη να μην μπορεί να τον ξεχάσει.
  static Future<void> record(
    DatabaseExecutor executor, {
    required int? recipientOperatorId,
    required int taskId,
    required TaskNotificationKind kind,
    required int? actorOperatorId,
  }) async {
    if (recipientOperatorId == null) return;
    if (recipientOperatorId == actorOperatorId) return;
    await executor.insert('task_notifications', {
      'recipient_operator_id': recipientOperatorId,
      'task_id': taskId,
      'kind': kind.dbValue,
      'actor_operator_id': actorOperatorId,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Τι περιμένει αυτόν τον άνθρωπο, νεότερο πρώτα.
  ///
  /// Η ένωση με τα `tasks` δίνει τον **τωρινό** τίτλο και ταυτόχρονα φιλτράρει:
  /// εκκρεμότητα που διαγράφηκε ή χάθηκε δεν έχει τίποτα να αναγγείλει, και η
  /// ειδοποίησή της απλώς δεν εμφανίζεται.
  Future<List<TaskNotification>> unseenFor(int recipientOperatorId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT n.id, n.task_id, n.kind, n.actor_operator_id, n.created_at, '
      't.title '
      'FROM task_notifications n '
      'JOIN tasks t ON t.id = n.task_id '
      'WHERE n.recipient_operator_id = ? '
      'AND COALESCE(t.is_deleted, 0) = 0 '
      'ORDER BY n.id DESC',
      [recipientOperatorId],
    );
    return [for (final row in rows) ?TaskNotification.fromMap(row)];
  }

  /// Σβήνει **ό,τι περιμένει** αυτόν τον άνθρωπο — και όσα δεν χώρεσαν στην
  /// οθόνη.
  ///
  /// Το «Εντάξει» σημαίνει «τα είδα όλα». Μια μερική διαγραφή θα άφηνε τον
  /// διάλογο να ξαναεμφανίζεται με τα υπόλοιπα, σαν να μην τον έκλεισε ποτέ.
  /// Καθαρίζει και όσες κρέμονται από εκκρεμότητα που έχει πια χαθεί: δεν
  /// εμφανίζονται ποτέ, οπότε τίποτα άλλο δεν θα τις σβήσει.
  Future<void> clearFor(int recipientOperatorId) async {
    final db = await _db;
    await db.delete(
      'task_notifications',
      where: 'recipient_operator_id = ?',
      whereArgs: [recipientOperatorId],
    );
  }
}
