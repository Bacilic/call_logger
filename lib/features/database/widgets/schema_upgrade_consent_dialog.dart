import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/database_file_classifier.dart';
import '../../../core/database/database_init_result.dart';
import '../../../core/database/database_path_pick_flow.dart';
import '../../../core/database/database_schema_migrations.dart';
import '../../../core/database/database_state_notice.dart';
import '../../../core/services/settings_service.dart';
import '../services/database_upgrade_copy_service.dart';

/// Επιλογή χρήστη στον διάλογο συγκατάθεσης αναβάθμισης σχήματος.
enum SchemaUpgradeConsentChoice {
  /// Αναβάθμιση αντιγράφου (προτείνεται) — το πρωτότυπο μένει άθικτο.
  upgradeCopy,

  /// Αναβάθμιση του πρωτοτύπου — μη αναστρέψιμη.
  upgradeOriginal,

  /// Ακύρωση.
  cancel,
}

/// Εμφανίζει διάλογο συγκατάθεσης πριν από μόνιμη αναβάθμιση σχήματος.
///
/// Δέχεται την **πλήρη διαδρομή** και όχι μόνο το όνομα: χρειάζεται για να
/// δείξει εκ των προτέρων το όνομα του αντιγράφου που θα δημιουργηθεί
/// ([upgradeCopyFileName]), ώστε ο χρήστης να ξέρει τι θα προκύψει.
Future<SchemaUpgradeConsentChoice> showSchemaUpgradeConsentDialog({
  required BuildContext context,
  required String dbPath,
  required int fileSchemaVersion,
  required int appSchemaVersion,
}) async {
  final fileName = p.basename(dbPath);
  final copyName = upgradeCopyFileName(dbPath);
  final choice = await showDialog<SchemaUpgradeConsentChoice>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        title: const Text('Μόνιμη αναβάθμιση σχήματος'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Το αρχείο «$fileName» έχει σχήμα έκδοσης '
                '$fileSchemaVersion.\n'
                'Η εφαρμογή χρησιμοποιεί την έκδοση $appSchemaVersion.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Το άνοιγμα θα αναβαθμίσει το αρχείο ΜΟΝΙΜΑ, χωρίς '
                'δυνατότητα επιστροφής σε προηγούμενη έκδοση.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          _ConsentActionTooltip(
            message:
                'Δεν γίνεται καμία αλλαγή στο αρχείο. Η βάση δεν ανοίγει και '
                'μπορείτε να επιλέξετε άλλη διαδρομή.',
            child: TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(SchemaUpgradeConsentChoice.cancel),
              child: const Text('Άκυρο'),
            ),
          ),
          _ConsentActionTooltip(
            message:
                'Η αναβάθμιση θα οριστικοποιηθεί πάνω στο «$fileName» και '
                'είναι μη αναστρέψιμη: το αρχείο δεν θα ανοίγει πλέον από '
                'παλαιότερη έκδοση της εφαρμογής.',
            child: TextButton(
              onPressed: () => Navigator.of(
                ctx,
              ).pop(SchemaUpgradeConsentChoice.upgradeOriginal),
              child: Text(
                'Αναβάθμιση του πρωτοτύπου (μη αναστρέψιμη)',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ),
          _ConsentActionTooltip(
            message:
                'Δημιουργείται αντίγραφο «$copyName» και αναβαθμίζεται εκείνο. '
                'Το πρωτότυπο «$fileName» μένει άθικτο.',
            child: FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(SchemaUpgradeConsentChoice.upgradeCopy),
              child: const Text('Αναβάθμιση αντιγράφου (προτείνεται)'),
            ),
          ),
        ],
      );
    },
  );
  return choice ?? SchemaUpgradeConsentChoice.cancel;
}

/// Κοινή ροή συγκατάθεσης (εκκίνηση / Ρυθμίσεις).
/// Επιστρέφει true αν ολοκληρώθηκε επιτυχής ανάκαμψη.
Future<bool> runSchemaUpgradeConsentRecovery({
  required BuildContext context,
  required DatabaseInitResult result,
  required Future<void> Function() onSuccess,
}) async {
  final path = (result.path ?? '').trim();
  if (path.isEmpty) return false;

  final versions = _parseSchemaVersions(result);
  final choice = await showSchemaUpgradeConsentDialog(
    context: context,
    dbPath: path,
    fileSchemaVersion: versions.fileVersion,
    appSchemaVersion: versions.appVersion,
  );
  if (!context.mounted) return false;

  switch (choice) {
    case SchemaUpgradeConsentChoice.cancel:
      return false;
    case SchemaUpgradeConsentChoice.upgradeCopy:
      final copyResult = await createUpgradeCopy(path);
      if (!context.mounted) return false;
      if (!copyResult.isSuccess) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Αποτυχία αντιγράφου'),
            content: Text(
              copyResult.errorMessage ?? 'Δεν δημιουργήθηκε αντίγραφο.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Εντάξει'),
              ),
            ],
          ),
        );
        return false;
      }
      final outcome = await setAndVerifyDatabasePath(copyResult.copyPath!);
      if (!context.mounted) return false;
      if (!outcome.ok) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Αποτυχία ανοίγματος αντιγράφου'),
            content: Text(
              outcome.runner.result.message ??
                  'Το αντίγραφο δεν άνοιξε επιτυχώς.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Εντάξει'),
              ),
            ],
          ),
        );
        return false;
      }
      await onSuccess();
      return true;
    case SchemaUpgradeConsentChoice.upgradeOriginal:
      final identity = await schemaUpgradeConsentIdentityForPath(path);
      await SettingsService().setSchemaUpgradeConsentIdentity(identity);
      final outcome = await setAndVerifyDatabasePath(path);
      if (!context.mounted) return false;
      if (!outcome.ok) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Αποτυχία αναβάθμισης'),
            content: Text(
              outcome.runner.result.message ??
                  'Η αναβάθμιση του πρωτοτύπου δεν ολοκληρώθηκε.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Εντάξει'),
              ),
            ],
          ),
        );
        return false;
      }
      await onSuccess();
      return true;
  }
}

({int fileVersion, int appVersion}) _parseSchemaVersions(
  DatabaseInitResult result,
) {
  var fileVersion = 0;
  var appVersion = kDatabaseSchemaVersion;
  final code = result.technicalCode?.trim() ?? '';
  final arrow = RegExp(r'^(\d+)\s*→\s*(\d+)$').firstMatch(code);
  if (arrow != null) {
    fileVersion = int.tryParse(arrow.group(1)!) ?? 0;
    appVersion = int.tryParse(arrow.group(2)!) ?? kDatabaseSchemaVersion;
    return (fileVersion: fileVersion, appVersion: appVersion);
  }
  final details = result.details ?? '';
  final fileMatch = RegExp(r'Έκδοση αρχείου:\s*(\d+)').firstMatch(details);
  final appMatch = RegExp(r'Έκδοση εφαρμογής:\s*(\d+)').firstMatch(details);
  if (fileMatch != null) {
    fileVersion = int.tryParse(fileMatch.group(1)!) ?? 0;
  }
  if (appMatch != null) {
    appVersion = int.tryParse(appMatch.group(1)!) ?? kDatabaseSchemaVersion;
  }
  return (fileVersion: fileVersion, appVersion: appVersion);
}

/// Ταυτότητα περιεχομένου για την οποία καταγράφεται η συγκατάθεση αναβάθμισης.
///
/// Δημόσια επίτηδες: η ροή «αναβάθμιση αντιγράφου» πρέπει να καταγράψει την
/// ίδια ταυτότητα για το ΑΝΤΙΓΡΑΦΟ, ώστε το αντίγραφο να ανοίγει χωρίς δεύτερη
/// ερώτηση συγκατάθεσης. Ο υπολογισμός είναι ο ίδιος με αυτόν που κάνει ο
/// έλεγχος εκκίνησης πριν ζητήσει συγκατάθεση.
Future<String> schemaUpgradeConsentIdentityForPath(String dbPath) async {
  var modifiedMs = 0;
  try {
    modifiedMs = File(dbPath).lastModifiedSync().millisecondsSinceEpoch;
  } catch (_) {}
  final profile = await profileDatabaseFile(dbPath);
  return databaseContentIdentity(
    dbPath: dbPath,
    latestCallDate: profile.latestCallDate,
    callCount: profile.callCount,
    fileModifiedMs: modifiedMs,
  );
}

/// Επεξήγηση κουμπιού με περιορισμένο πλάτος.
///
/// Ίδιο μοτίβο με το `InfoHintIcon` του πυρήνα: τα μηνύματα εδώ είναι μεγάλα
/// (ονόματα αρχείων) και ένα σκέτο `message` θα γινόταν μια ατέλειωτη γραμμή.
class _ConsentActionTooltip extends StatelessWidget {
  const _ConsentActionTooltip({required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxWidth = (MediaQuery.sizeOf(context).width / 3).clamp(260.0, 440.0);
    return Tooltip(
      waitDuration: const Duration(milliseconds: 300),
      showDuration: const Duration(seconds: 8),
      richMessage: WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onInverseSurface,
            ),
          ),
        ),
      ),
      child: child,
    );
  }
}
