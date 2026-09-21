import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/audit_retention_class.dart';
import '../config/audit_retention_config.dart';
import '../database/audit_service.dart';
import '../database/database_helper.dart';
import 'audit_retention_plan.dart';
import 'settings_service.dart';

/// Εφαρμογή της πολιτικής εκκαθάρισης του Ιστορικού.
///
/// **Δύο βήματα, πάντα με αυτή τη σειρά:** πρώτα χτίζεται το σχέδιο
/// ([buildPlan]) και μετά εκτελείται ([executePlan]). Ο χειριστής βλέπει
/// **ακριβώς** το σχέδιο που θα εκτελεστεί, και δεν υπολογίζεται δεύτερη φορά
/// στο ενδιάμεσο — αλλιώς θα ενέκρινε ένα νούμερο και θα εκτελούνταν άλλο.
class AuditRetentionRunner {
  AuditRetentionRunner._();

  /// Εκτελεί εκκαθάριση όταν το ζητά το [AuditRetentionConfig.purgeOnAppStart].
  ///
  /// Επιστρέφει `true` μόνο όταν έγινε πράγματι δουλειά — η εκκίνηση
  /// ανακοινώνει μόνο τα βήματα που είχαν κάτι να κάνουν.
  static Future<bool> applyIfConfiguredOnStartup() async {
    final config = await SettingsService().catalogs.getAuditRetentionConfig();
    if (!config.purgeOnAppStart) return false;
    final outcome = await applyWithConfig(config);
    return outcome.deleted > 0 || outcome.compacted > 0;
  }

  /// Χτίζει το σχέδιο χωρίς να αγγίξει τίποτα.
  static Future<AuditRetentionPlan> buildPlan(
    AuditRetentionConfig config, {
    DateTime? now,
  }) async {
    if (!config.hasAnyPolicy) return AuditRetentionPlan.empty;

    final moment = now ?? DateTime.now();
    final db = await DatabaseHelper.instance.database;
    final svc = AuditService(db);

    final totals = await svc.countByRetentionClass();
    final totalBefore = totals.values.fold<int>(0, (a, b) => a + b);

    final plans = <AuditRetentionClassPlan>[];
    for (final value in AuditRetentionClass.values) {
      final days = config.maxAgeDaysFor(value);
      final total = totals[value] ?? 0;
      if (days == null || days <= 0) {
        plans.add(
          AuditRetentionClassPlan(
            retentionClass: value,
            totalRows: total,
            rowsToDelete: 0,
            cutoff: null,
          ),
        );
        continue;
      }
      final cutoff = moment.subtract(Duration(days: days));
      plans.add(
        AuditRetentionClassPlan(
          retentionClass: value,
          totalRows: total,
          rowsToDelete: await svc.countOlderThanInClass(value, cutoff),
          cutoff: cutoff,
        ),
      );
    }

    // Επίπεδο 1 — ανεξάρτητο από τις διαγραφές: αγγίζει και γραμμές που
    // παραμένουν, και γι' αυτό μετριέται χωριστά.
    var compactRows = 0;
    DateTime? compactCutoff;
    final compactDays = config.compactSearchTextAfterDays;
    if (compactDays != null && compactDays > 0) {
      compactCutoff = moment.subtract(Duration(days: compactDays));
      compactRows = await svc.countCompactableOlderThan(compactCutoff);
    }

    // Επίπεδο 3 — το πάτωμα κόβει τη διαγραφή, όχι τη συμπίεση: η συμπίεση δεν
    // χάνει τίποτα, οπότε δεν χρειάζεται προστασία.
    final plannedDeletes = plans.fold<int>(0, (sum, x) => sum + x.rowsToDelete);
    var trim = 0;
    final maxRows = config.maxRows;
    if (maxRows != null && maxRows > 0) {
      final erasableAfter =
          totalBefore -
          plannedDeletes -
          (totals[AuditRetentionClass.permanent] ?? 0);
      if (erasableAfter > maxRows) trim = erasableAfter - maxRows;
    }

    var reason = AuditRetentionLimitReason.none;
    final wouldRemain = totalBefore - plannedDeletes - trim;
    if (wouldRemain < config.minimumRowsFloor) {
      final allowed = totalBefore - config.minimumRowsFloor;
      final capped = allowed < 0 ? 0 : allowed;
      trim = 0;
      if (capped < plannedDeletes) {
        reason = AuditRetentionLimitReason.floorReached;
        return AuditRetentionPlan(
          classPlans: _capPlansTo(plans, capped),
          rowsToCompact: compactRows,
          compactCutoff: compactCutoff,
          totalRowsBefore: totalBefore,
          trimRows: 0,
          limitReason: reason,
        );
      }
      reason = AuditRetentionLimitReason.floorReached;
    }

    return AuditRetentionPlan(
      classPlans: plans,
      rowsToCompact: compactRows,
      compactCutoff: compactCutoff,
      totalRowsBefore: totalBefore,
      trimRows: trim,
      limitReason: reason,
    );
  }

  /// Μειώνει τις προγραμματισμένες διαγραφές ώστε να μη σπάσει το πάτωμα.
  ///
  /// Θυσιάζεται πρώτα η πιο αναλώσιμη κλάση — αν πρέπει να κρατηθεί κάτι, ας
  /// είναι η ημερήσια κίνηση και όχι η διαδρομή μιας καρτέλας.
  static List<AuditRetentionClassPlan> _capPlansTo(
    List<AuditRetentionClassPlan> plans,
    int allowedTotal,
  ) {
    var budget = allowedTotal;
    final order = [
      AuditRetentionClass.volatile,
      AuditRetentionClass.operational,
      AuditRetentionClass.permanent,
    ];
    final byClass = {for (final x in plans) x.retentionClass: x};
    final out = <AuditRetentionClassPlan>[];
    for (final value in order) {
      final source = byClass[value]!;
      final take = source.rowsToDelete <= budget ? source.rowsToDelete : budget;
      budget -= take;
      out.add(
        AuditRetentionClassPlan(
          retentionClass: value,
          totalRows: source.totalRows,
          rowsToDelete: take,
          cutoff: source.cutoff,
        ),
      );
    }
    return out;
  }

  /// Εκτελεί ένα σχέδιο που έχει ήδη εγκριθεί.
  ///
  /// Η σειρά είναι δεσμευτική: **εξαγωγή → διαγραφή → συμπίεση**. Η εξαγωγή
  /// προηγείται γιατί μετά τη διαγραφή δεν υπάρχει τι να εξαχθεί, και η
  /// συμπίεση έπεται γιατί δεν έχει νόημα να πετάξει κείμενο από γραμμές που
  /// σβήνονται ούτως ή άλλως.
  static Future<({int deleted, int compacted, String? exportPath})> executePlan(
    AuditRetentionPlan plan,
    AuditRetentionConfig config, {
    String? exportDirectory,
  }) async {
    if (plan.isNoOp) return (deleted: 0, compacted: 0, exportPath: null);

    final db = await DatabaseHelper.instance.database;
    final svc = AuditService(db);

    String? exportPath;
    if (config.exportBeforePurge && plan.totalRowsToDelete > 0) {
      exportPath = await _exportDoomedRows(
        svc,
        plan,
        exportDirectory ?? p.dirname(db.path),
      );
    }

    var deleted = 0;
    for (final classPlan in plan.classPlans) {
      final cutoff = classPlan.cutoff;
      if (cutoff == null || classPlan.rowsToDelete <= 0) continue;
      deleted += await svc.deleteOlderThanInClass(
        classPlan.retentionClass,
        cutoff,
      );
    }

    if (plan.trimRows > 0) {
      final target = plan.totalRowsBefore - deleted - plan.trimRows;
      deleted += await svc.trimToMaxRows(target < 0 ? 0 : target);
    }

    var compacted = 0;
    final compactCutoff = plan.compactCutoff;
    if (compactCutoff != null) {
      compacted = await svc.compactSearchTextOlderThan(compactCutoff);
    }

    return (deleted: deleted, compacted: compacted, exportPath: exportPath);
  }

  /// Χτίζει και εκτελεί σε μία κίνηση — για την εκκίνηση, όπου δεν υπάρχει
  /// κανείς να εγκρίνει.
  static Future<({int deleted, int compacted, String? exportPath})>
  applyWithConfig(AuditRetentionConfig config, {DateTime? now}) async {
    final plan = await buildPlan(config, now: now);
    return executePlan(plan, config);
  }

  /// Γράφει σε αρχείο ό,τι πρόκειται να σβηστεί.
  ///
  /// Δίπλα στη βάση και όχι στον φάκελο αντιγράφων: το αρχείο αφορά **αυτή**
  /// τη βάση, και ο φάκελος αντιγράφων μπορεί να μην είναι καν προσβάσιμος τη
  /// στιγμή της εκκαθάρισης.
  ///
  /// Αποτυχία εδώ **σταματά** την εκκαθάριση: αν δεν μπορεί να κρατηθεί
  /// αντίγραφο, δεν σβήνεται τίποτα.
  static Future<String> _exportDoomedRows(
    AuditService svc,
    AuditRetentionPlan plan,
    String directory,
  ) async {
    final rows = <Map<String, Object?>>[];
    for (final classPlan in plan.classPlans) {
      final cutoff = classPlan.cutoff;
      if (cutoff == null || classPlan.rowsToDelete <= 0) continue;
      rows.addAll(
        await svc.rowsOlderThanInClass(classPlan.retentionClass, cutoff),
      );
    }

    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final path = p.join(directory, 'ιστορικό_πριν_εκκαθάριση_$stamp.json');
    await File(path).writeAsString(
      const JsonEncoder.withIndent('  ').convert(rows),
      flush: true,
    );
    return path;
  }
}
