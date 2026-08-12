import '../database/database_helper.dart';
import '../config/audit_retention_config.dart';
import '../database/audit_service.dart';
import 'settings_service.dart';

/// Εφαρμογή πολιτικής retention για `audit_log` (εκκίνηση ή χειροκίνητα).
class AuditRetentionRunner {
  AuditRetentionRunner._();

  /// Αν [config.purgeOnAppStart] και [config.enabled], εκτελεί εκκαθάριση.
  /// Επιστρέφει `true` μόνο όταν διαγράφηκε πράγματι κάτι — η εκκίνηση
  /// ανακοινώνει μόνο τα βήματα που είχαν δουλειά.
  static Future<bool> applyIfConfiguredOnStartup() async {
    final config = await SettingsService().catalogs.getAuditRetentionConfig();
    if (!config.enabled || !config.purgeOnAppStart) return false;
    final removed = await applyWithConfig(config);
    return removed.byAge > 0 || removed.byTrim > 0;
  }

  /// Εκτέλεση με συγκεκριμένη πολιτική (π.χ. από UI «Εκκαθάριση τώρα»).
  ///
  /// Αν [ignoreEnabledGate] είναι true, εκτελεί διαγραφές όταν υπάρχει
  /// `maxAgeDays` ή `maxRows`, ακόμη κι αν `enabled` είναι false (χειροκίνητη εκκαθάριση).
  static Future<({int byAge, int byTrim})> applyWithConfig(
    AuditRetentionConfig config, {
    bool ignoreEnabledGate = false,
  }) async {
    final hasPolicy = config.maxAgeDays != null || config.maxRows != null;
    if (!ignoreEnabledGate) {
      if (!config.enabled && !hasPolicy) {
        return (byAge: 0, byTrim: 0);
      }
    } else if (!hasPolicy) {
      return (byAge: 0, byTrim: 0);
    }
    final db = await DatabaseHelper.instance.database;
    final svc = AuditService(db);
    var byAge = 0;
    var byTrim = 0;
    final days = config.maxAgeDays;
    if (days != null && days > 0) {
      final cutoff = DateTime.now().subtract(Duration(days: days));
      byAge = await svc.deleteOlderThan(cutoff);
    }
    final maxRows = config.maxRows;
    if (maxRows != null && maxRows > 0) {
      byTrim = await svc.trimToMaxRows(maxRows);
    }
    return (byAge: byAge, byTrim: byTrim);
  }
}
