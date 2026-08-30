import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/database_init_result.dart';
import '../../../core/database/database_path_pick_flow.dart';
import '../../../core/widgets/compact_tooltip.dart';
import '../../../core/database/schema_downgrade_compatibility.dart';
import '../../../core/services/app_instance_registry.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/updates/app_upgrade_offer.dart';
import '../../../core/updates/update_dialogs.dart';
import '../../../core/updates/update_providers.dart';
import '../services/database_downgrade_service.dart';
import '../services/database_upgrade_copy_service.dart';
import 'schema_upgrade_consent_dialog.dart' show parseSchemaMismatchVersions;

/// Επιλογή χρήστη στον διάλογο «βάση νεότερης έκδοσης».
enum DatabaseNewerVersionChoice {
  /// Αναβάθμιση αυτής της εγκατάστασης από τον φάκελο ενημερώσεων.
  upgradeApp,

  /// Εκκίνηση της νεότερης εγκατάστασης που διαβάζει αυτή τη βάση.
  launchNewer,

  /// Υποβάθμιση ΑΝΤΙΓΡΑΦΟΥ (προτείνεται) — το πρωτότυπο μένει άθικτο.
  downgradeCopy,

  /// Υποβάθμιση του πρωτοτύπου — η νεότερη εφαρμογή θα το ξανα-αναβαθμίσει.
  downgradeOriginal,

  /// Κλείσιμο χωρίς ενέργεια.
  cancel,
}

/// Κοινή ροή ανάκαμψης για βάση ΝΕΟΤΕΡΗΣ έκδοσης (εκκίνηση / Ρυθμίσεις).
/// Επιστρέφει true αν ολοκληρώθηκε επιτυχής ανάκαμψη.
Future<bool> runDatabaseNewerRecovery({
  required BuildContext context,
  required DatabaseInitResult result,
  required Future<void> Function() onSuccess,
}) async {
  final path = (result.path ?? '').trim();
  if (path.isEmpty) return false;

  // Η αξιολόγηση προτιμάται όπως ήρθε από τον φρουρό· αν λείπει (π.χ. το
  // σφάλμα βγήκε από το δίχτυ ασφαλείας), υπολογίζεται τώρα.
  final versions = parseSchemaMismatchVersions(result);
  var assessment = result.schemaDowngrade;
  if (assessment == null && versions.fileVersion > 0) {
    try {
      assessment = await assessSchemaDowngrade(
        path,
        fileVersion: versions.fileVersion,
      );
    } catch (_) {
      assessment = null;
    }
  }

  final newerInstance = await findNewerAppInstance(
    minimumSchemaVersion: versions.fileVersion,
  );
  if (!context.mounted) return false;

  // Ο έλεγχος για νέα έκδοση της εκκίνησης τρέχει ΜΟΝΟ όταν η βάση ανοίξει —
  // εδώ δεν έχει τρέξει ποτέ, οπότε ρωτάμε τώρα τον φάκελο ενημερώσεων.
  final upgradeOffer = await _probeAppUpgradeOffer(
    context,
    fileSchemaVersion: versions.fileVersion,
  );
  if (!context.mounted) return false;

  final choice = await showDatabaseNewerVersionChoiceDialog(
    context: context,
    dbPath: path,
    fileVersion: versions.fileVersion,
    appVersion: versions.appVersion,
    assessment: assessment,
    newerInstance: newerInstance,
    upgradeOffer: upgradeOffer,
  );
  if (!context.mounted) return false;

  switch (choice) {
    case DatabaseNewerVersionChoice.cancel:
      return false;

    case DatabaseNewerVersionChoice.upgradeApp:
      if (upgradeOffer == null) return false;
      // Η κοινή ροή ενημέρωσης: πρόοδος, χειρισμός αποτυχίας και ερώτηση
      // επανεκκίνησης ζουν σε ένα σημείο — εδώ απλώς την καλούμε.
      await runUpdatePrepareFlow(context, upgradeOffer.manifest);
      return false;

    case DatabaseNewerVersionChoice.launchNewer:
      if (newerInstance == null) return false;
      try {
        await Process.start(
          newerInstance.executablePath,
          const <String>[],
          mode: ProcessStartMode.detached,
        );
      } catch (e) {
        if (!context.mounted) return false;
        await _showFailureDialog(
          context,
          title: 'Αποτυχία εκκίνησης',
          message:
              'Η νεότερη εφαρμογή δεν ξεκίνησε: $e\n\n'
              'Διαδρομή: ${newerInstance.executablePath}',
        );
        return false;
      }
      if (!context.mounted) return true;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Η νεότερη εφαρμογή ξεκίνησε — μπορείτε να κλείσετε αυτό το '
            'παράθυρο.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return true;

    case DatabaseNewerVersionChoice.downgradeCopy:
      final outcome = await downgradeCopyToAppVersion(path);
      if (!context.mounted) return false;
      if (!outcome.isSuccess) {
        await _showFailureDialog(
          context,
          title: 'Αποτυχία υποβάθμισης αντιγράφου',
          message: outcome.errorMessage ?? 'Η υποβάθμιση δεν ολοκληρώθηκε.',
        );
        return false;
      }
      return _openDowngradedPath(
        context,
        outcome.dbPath!,
        onSuccess: onSuccess,
      );

    case DatabaseNewerVersionChoice.downgradeOriginal:
      final confirmed = await _confirmDowngradeOriginal(context, path);
      if (!context.mounted || !confirmed) return false;
      final outcome = await downgradeDatabaseFileToAppVersion(path);
      if (!context.mounted) return false;
      if (!outcome.isSuccess) {
        await _showFailureDialog(
          context,
          title: 'Αποτυχία υποβάθμισης',
          message: outcome.errorMessage ?? 'Η υποβάθμιση δεν ολοκληρώθηκε.',
        );
        return false;
      }
      return _openDowngradedPath(context, path, onSuccess: onSuccess);
  }
}

/// Ρωτά τον φάκελο ενημερώσεων αν υπάρχει πακέτο που ξεμπλοκάρει τη βάση.
///
/// Σιωπηλή αποτυχία: άφταστος φάκελος δικτύου, build ανάπτυξης ή χαλασμένο
/// `version.json` σημαίνουν απλώς «καμία προσφορά» — ο διάλογος κρατά τις
/// υπόλοιπες διεξόδους του και δεν μολύνεται από σφάλμα ενημερώσεων.
Future<AppUpgradeOffer?> _probeAppUpgradeOffer(
  BuildContext context, {
  required int fileSchemaVersion,
}) async {
  try {
    final container = ProviderScope.containerOf(context);
    final check = await container.read(updateServiceProvider).checkForUpdate();
    final current = check.currentVersion;
    final build = check.currentBuild;
    if (current == null || build == null) return null;
    return evaluateAppUpgradeOffer(
      manifest: check.manifest,
      currentVersion: current,
      currentBuild: build,
      fileSchemaVersion: fileSchemaVersion,
    );
  } catch (_) {
    return null;
  }
}

/// Το πιο πρόσφατο ΑΛΛΟ αντίγραφο που αποδεδειγμένα διαβάζει βάσεις έκδοσης
/// τουλάχιστον [minimumSchemaVersion] και υπάρχει ακόμη στον δίσκο.
///
/// Εγγραφές χωρίς καταγεγραμμένη έκδοση σχήματος (παλαιά αντίγραφα)
/// αποκλείονται: το μητρώο δεν μαντεύει — βλέπει.
Future<AppInstanceRecord?> findNewerAppInstance({
  required int minimumSchemaVersion,
}) async {
  if (minimumSchemaVersion <= 0) return null;

  String currentExecutable = '';
  try {
    currentExecutable = Platform.resolvedExecutable.trim().toLowerCase();
  } catch (_) {}

  final known = await SettingsService().getKnownAppInstances();
  AppInstanceRecord? best;
  for (final record in known) {
    final schema = record.schemaVersion;
    if (schema == null || schema < minimumSchemaVersion) continue;
    if (record.executablePath.trim().toLowerCase() == currentExecutable) {
      continue;
    }
    try {
      if (!File(record.executablePath).existsSync()) continue;
    } catch (_) {
      continue;
    }
    if (best == null || record.lastSeen.isAfter(best.lastSeen)) {
      best = record;
    }
  }
  return best;
}

/// Ο διάλογος επιλογών. Δημόσιος με έτοιμα δεδομένα, ώστε τα τεστ να
/// ελέγχουν τη συμπεριφορά των κουμπιών χωρίς πραγματικά αρχεία.
///
/// Η σειρά των ενοτήτων είναι η σειρά προτίμησης: η αναβάθμιση **πρώτη**,
/// γιατί είναι η μόνη που λύνει το πρόβλημα αντί να το παρακάμπτει — οι
/// υπόλοιπες αφήνουν πίσω τους ένα παλιό αντίγραφο που θα ξανακολλήσει.
Future<DatabaseNewerVersionChoice> showDatabaseNewerVersionChoiceDialog({
  required BuildContext context,
  required String dbPath,
  required int fileVersion,
  required int appVersion,
  required SchemaDowngradeAssessment? assessment,
  required AppInstanceRecord? newerInstance,
  AppUpgradeOffer? upgradeOffer,
}) async {
  final choice = await showDialog<DatabaseNewerVersionChoice>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Η βάση είναι από νεότερη έκδοση'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Το αρχείο «${p.basename(dbPath)}» είναι στην έκδοση '
                '$fileVersion. Αυτή η εφαρμογή διαβάζει έως την έκδοση '
                '$appVersion, οπότε δεν μπορεί να το ανοίξει.',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _UpgradeAppSection(offer: upgradeOffer),
              const _SectionGap(),
              _LaunchNewerSection(
                newerInstance: newerInstance,
                isPreferred: upgradeOffer == null,
              ),
              const _SectionGap(),
              _DowngradeSection(
                dbPath: dbPath,
                appVersion: appVersion,
                assessment: assessment,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(DatabaseNewerVersionChoice.cancel),
          child: const Text('Κλείσιμο'),
        ),
      ],
    ),
  );
  return choice ?? DatabaseNewerVersionChoice.cancel;
}

/// Διαχωριστικό ανάμεσα σε δύο ενότητες διεξόδων.
class _SectionGap extends StatelessWidget {
  const _SectionGap();

  @override
  Widget build(BuildContext context) => const Column(
    mainAxisSize: MainAxisSize.min,
    children: [SizedBox(height: 16), Divider(height: 1), SizedBox(height: 12)],
  );
}

/// Τίτλος ενότητας διεξόδων.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
  );
}

/// Η προτιμώμενη διέξοδος: εγκατάσταση της νεότερης έκδοσης εδώ και τώρα.
class _UpgradeAppSection extends StatelessWidget {
  const _UpgradeAppSection({required this.offer});

  final AppUpgradeOffer? offer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = offer;

    if (available == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Αναβάθμιση της εφαρμογής'),
          const SizedBox(height: 6),
          Text(
            'Δεν βρέθηκε νεότερο πακέτο εγκατάστασης στον φάκελο '
            'ενημερώσεων. Αν ο φάκελος δεν είναι προσβάσιμος τώρα '
            '(π.χ. εκτός δικτύου), δοκιμάστε ξανά όταν συνδεθείτε.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    // Η διατύπωση ακολουθεί τη γνώση: όταν το πακέτο δηλώνει ποια βάση
    // διαβάζει, η υπόσχεση είναι βέβαιη· αλλιώς λέγεται ως πιθανότητα.
    final promise = switch (available.confidence) {
      AppUpgradeConfidence.resolvesForSure =>
        'Η έκδοση ${available.version} διαβάζει αυτή τη βάση — μετά την '
            'αναβάθμιση θα ανοίξει κανονικά.',
      AppUpgradeConfidence.likelyResolves =>
        'Η έκδοση ${available.version} είναι νεότερη από τη δική σας. Το '
            'πακέτο δεν καταγράφει ποια έκδοση βάσης διαβάζει, οπότε είναι '
            'η πιθανότερη λύση — χωρίς εγγύηση.',
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Αναβάθμιση της εφαρμογής (προτείνεται)'),
        const SizedBox(height: 6),
        Text(promise, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: CompactTooltip(
            message:
                'Εγκαθιστά την έκδοση ${available.version} από τον φάκελο '
                'ενημερώσεων.\n\n'
                'Δεν αγγίζει τη βάση δεδομένων ούτε τα δεδομένα σας — '
                'ξαναγράφει μόνο τα αρχεία της εφαρμογής.',
            child: FilledButton.icon(
              key: const Key('newer_db_upgrade_app_button'),
              onPressed: () => Navigator.of(
                context,
              ).pop(DatabaseNewerVersionChoice.upgradeApp),
              icon: const Icon(Icons.system_update_alt, size: 18),
              label: Text('Αναβάθμιση στην έκδοση ${available.version}'),
            ),
          ),
        ),
      ],
    );
  }
}

/// Η γρήγορη διέξοδος: άλλο, ήδη νεότερο αντίγραφο στον ίδιο υπολογιστή.
class _LaunchNewerSection extends StatelessWidget {
  const _LaunchNewerSection({
    required this.newerInstance,
    required this.isPreferred,
  });

  final AppInstanceRecord? newerInstance;

  /// Όταν δεν προσφέρεται αναβάθμιση, αυτή είναι η μόνη διέξοδος που
  /// ανοίγει τη βάση αυτούσια — και ντύνεται ανάλογα.
  final bool isPreferred;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final instance = newerInstance;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Άνοιγμα με τη νεότερη εφαρμογή'),
        const SizedBox(height: 6),
        if (instance != null) ...[
          Text(
            'Στον υπολογιστή υπάρχει εγκατάσταση που διαβάζει αυτή τη βάση'
            '${instance.version.isNotEmpty ? ' (έκδοση ${instance.version})' : ''}:',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          SelectableText(
            instance.executablePath,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Consolas', 'monospace'],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: isPreferred
                ? FilledButton.icon(
                    key: const Key('newer_db_launch_newer_button'),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(DatabaseNewerVersionChoice.launchNewer),
                    icon: const Icon(Icons.rocket_launch_outlined, size: 18),
                    label: const Text('Εκκίνηση της νεότερης εφαρμογής'),
                  )
                : OutlinedButton.icon(
                    key: const Key('newer_db_launch_newer_button'),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(DatabaseNewerVersionChoice.launchNewer),
                    icon: const Icon(Icons.rocket_launch_outlined, size: 18),
                    label: const Text('Εκκίνηση της νεότερης εφαρμογής'),
                  ),
          ),
        ] else
          Text(
            'Δεν έχει καταγραφεί νεότερη εγκατάσταση σε αυτόν τον '
            'υπολογιστή. Μπορείτε να ανοίξετε τη βάση από τον υπολογιστή '
            'που την αναβάθμισε.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// Η τελευταία διέξοδος: η βάση κατεβαίνει στην έκδοση της εφαρμογής.
class _DowngradeSection extends StatelessWidget {
  const _DowngradeSection({
    required this.dbPath,
    required this.appVersion,
    required this.assessment,
  });

  final String dbPath;
  final int appVersion;
  final SchemaDowngradeAssessment? assessment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = p.basename(dbPath);
    final copyName = upgradeCopyFileName(dbPath, suffix: '_υποβαθμισμένη_');
    final bridgeable = assessment?.isBridgeable ?? false;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Υποβάθμιση της βάσης στην έκδοση $appVersion'),
        const SizedBox(height: 6),
        if (bridgeable) ...[
          Text(
            'Η σύγκριση σχήματος επιτρέπει την υποβάθμιση: ό,τι χρειάζεται '
            'αυτή η έκδοση υπάρχει αυτούσιο στο αρχείο, και οι νεότερες '
            'στήλες θα μείνουν στη θέση τους, αγνοημένες.\n\n'
            'Προσοχή: ό,τι καταχωρείτε μετά την υποβάθμιση γράφεται χωρίς '
            'τα νεότερα πεδία — και αν το ίδιο αρχείο ανοίξει ξανά από τη '
            'νεότερη εφαρμογή, θα ανα-αναβαθμιστεί.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CompactTooltip(
                message:
                    'Δημιουργείται αντίγραφο «$copyName» και υποβαθμίζεται '
                    'εκείνο. Το πρωτότυπο «$fileName» μένει άθικτο για τη '
                    'νεότερη εφαρμογή.',
                child: OutlinedButton(
                  key: const Key('newer_db_downgrade_copy_button'),
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(DatabaseNewerVersionChoice.downgradeCopy),
                  child: const Text('Υποβάθμιση αντιγράφου (προτείνεται)'),
                ),
              ),
              CompactTooltip(
                message:
                    'Η υποβάθμιση γίνεται πάνω στο «$fileName». Η νεότερη '
                    'εφαρμογή θα το ξανα-αναβαθμίσει στο επόμενο άνοιγμα.',
                child: OutlinedButton(
                  key: const Key('newer_db_downgrade_original_button'),
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(DatabaseNewerVersionChoice.downgradeOriginal),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: const Text('Υποβάθμιση της τρέχουσας βάσης'),
                ),
              ),
            ],
          ),
        ] else ...[
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: Key('newer_db_downgrade_copy_button'),
                onPressed: null,
                child: Text('Υποβάθμιση αντιγράφου'),
              ),
              OutlinedButton(
                key: Key('newer_db_downgrade_original_button'),
                onPressed: null,
                child: Text('Υποβάθμιση της τρέχουσας βάσης'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            assessment == null
                ? 'Δεν είναι δυνατή: ο έλεγχος συμβατότητας της βάσης δεν '
                      'ολοκληρώθηκε.'
                : 'Δεν είναι δυνατή: ${assessment!.blockersSummary}.',
            key: const Key('newer_db_downgrade_reason'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

Future<bool> _confirmDowngradeOriginal(
  BuildContext context,
  String dbPath,
) async {
  final fileName = p.basename(dbPath);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Υποβάθμιση της τρέχουσας βάσης;'),
      content: Text(
        'Η υποβάθμιση θα γίνει πάνω στο «$fileName».\n\n'
        '• Οι νεότερες στήλες μένουν στο αρχείο και αγνοούνται — δεν '
        'χάνονται δεδομένα.\n'
        '• Ό,τι καταχωρείτε από εδώ και πέρα γράφεται χωρίς τα νεότερα '
        'πεδία.\n'
        '• Αν το αρχείο ανοίξει ξανά από τη νεότερη εφαρμογή, θα '
        'ανα-αναβαθμιστεί — αν δουλεύετε και με τις δύο εκδόσεις, '
        'προτιμήστε την υποβάθμιση αντιγράφου.',
        style: Theme.of(ctx).textTheme.bodyMedium,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          key: const Key('newer_db_confirm_downgrade_original'),
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          child: const Text('Υποβάθμιση'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

Future<bool> _openDowngradedPath(
  BuildContext context,
  String dbPath, {
  required Future<void> Function() onSuccess,
}) async {
  final outcome = await setAndVerifyDatabasePath(dbPath);
  if (!context.mounted) return false;
  if (!outcome.ok) {
    await _showFailureDialog(
      context,
      title: 'Αποτυχία ανοίγματος',
      message:
          outcome.runner.result.message ??
          'Η υποβαθμισμένη βάση δεν άνοιξε επιτυχώς.',
    );
    return false;
  }
  await onSuccess();
  return true;
}

Future<void> _showFailureDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Εντάξει'),
        ),
      ],
    ),
  );
}
