import 'package:flutter/material.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/database_identity_repository.dart';
import '../../../core/updates/update_manifest.dart';
import '../providers/active_sessions_provider.dart';
import '../services/active_sessions.dart';
import '../../../core/database/database_v1_schema.dart';

/// Αλλάζει αυτή η ενημέρωση τη δομή της κοινής βάσης;
///
/// Συγκρίνει το πακέτο με το **αρχείο**, όχι με την εγκατεστημένη εφαρμογή. Ο
/// ίδιος κανόνας απαντά σωστά σε δύο πολύ διαφορετικές καταστάσεις, χωρίς
/// εξαιρέσεις και χωρίς σημαίες:
///
/// 1. **Ο πρώτος που ενημερώνεται:** αρχείο 66, πακέτο 67 — ναι, θα αλλάξει.
/// 2. **Ο συνάδελφος που αποκλείστηκε** επειδή η βάση προχώρησε πριν από
///    εκείνον: αρχείο 67, πακέτο 67 — όχι, δεν αλλάζει τίποτα. Είναι ακριβώς ο
///    άνθρωπος που **πρέπει** να ενημερωθεί χωρίς εμπόδιο, και μια
///    προειδοποίηση εδώ θα τον κρατούσε έξω από τη δουλειά του.
///
/// Άγνοια σημαίνει σιωπή: πακέτο χωρίς δηλωμένη έκδοση σχήματος (παλαιότερη
/// μορφή) ή βάση που δεν απάντησε δεν δικαιολογούν προειδοποίηση στα τυφλά.
bool updateChangesDatabaseSchema({
  required int? packageSchemaVersion,
  required int? fileSchemaVersion,
}) {
  if (packageSchemaVersion == null || fileSchemaVersion == null) return false;
  if (fileSchemaVersion <= 0) return false;
  return packageSchemaVersion > fileSchemaVersion;
}

/// Η έκδοση σχήματος της βάσης που είναι **ανοιχτή τώρα**, ή `null`.
///
/// Ποτέ δεν ανοίγει σύνδεση: όταν η βάση δεν είναι ανοιχτή, η απάντηση είναι
/// «δεν ξέρω» — και η άγνοια δεν σταματά καμία ενημέρωση.
Future<int?> _openDatabaseSchemaVersion() async {
  try {
    final db = DatabaseHelper.instance.openDatabaseOrNull;
    if (db == null) return null;
    return await DatabaseIdentityRepository(db).readSchemaVersion();
  } catch (_) {
    return null;
  }
}

/// Διάβασμα σχήματος και φόρτωση συνεδριών — αντικαθίστανται στα τεστ.
typedef SchemaVersionProbe = Future<int?> Function();
typedef ActiveSessionsProbe = Future<List<ActiveSession>> Function();

/// Ρωτά πριν από ενημέρωση που θα αλλάξει τη δομή της κοινής βάσης.
///
/// **Η σωστή στιγμή είναι εδώ, όχι μετά.** Μετά την εγκατάσταση ο σταθμός δεν
/// μπορεί να γυρίσει στην προηγούμενη έκδοση: αν η βάση δεν αναβαθμίζεται
/// επειδή δουλεύουν ακόμη συνάδελφοι, ο άνθρωπος μένει εκτός λειτουργίας σε
/// στιγμή που δεν επέλεξε. Εδώ έχει ακόμη επιλογή, και η προεπιλογή είναι το
/// «Αργότερα».
///
/// **Ενημερώνει, δεν απαγορεύει.** Η ενημέρωση της εφαρμογής καθαυτή δεν
/// βλάπτει κανέναν — το μη αναστρέψιμο είναι η αναβάθμιση της βάσης, και εκείνη
/// έχει τον δικό της φρουρό που απαγορεύει.
///
/// Επιστρέφει `true` όταν η ενημέρωση μπορεί να προχωρήσει — και **χωρίς
/// καθόλου διάλογο** όταν το πακέτο δεν αγγίζει τη δομή της βάσης.
Future<bool> confirmSchemaChangingUpdate(
  BuildContext context,
  UpdateManifest manifest, {
  SchemaVersionProbe? readSchemaVersion,
  ActiveSessionsProbe? loadSessions,
}) async {
  final fileVersion = await (readSchemaVersion ?? _openDatabaseSchemaVersion)();
  if (!updateChangesDatabaseSchema(
    packageSchemaVersion: manifest.schemaVersion,
    fileSchemaVersion: fileVersion,
  )) {
    return true;
  }
  if (!context.mounted) return false;

  final sessions = await (loadSessions ?? loadActiveSessions)();
  final others = otherSessions(sessions);
  if (!context.mounted) return false;

  final now = DateTime.now();
  final mine = myAppVersion(sessions);

  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        icon: Icon(Icons.storage_rounded, color: theme.colorScheme.tertiary),
        title: const Text('Η ενημέρωση αλλάζει τη δομή της βάσης'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Η έκδοση ${manifest.version} αλλάζει τη δομή της κοινής '
                  'βάσης. Μετά την εγκατάσταση, η βάση θα αναβαθμιστεί μόνιμα '
                  'και δεν θα ανοίγει πλέον από εφαρμογές παλαιότερης έκδοσης.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  others.isEmpty
                      ? 'Αυτή τη στιγμή καμία άλλη εφαρμογή δεν έχει τη βάση '
                            'ανοιχτή, οπότε η αναβάθμιση θα προχωρήσει αμέσως '
                            'μετά την εγκατάσταση.'
                      : 'Για να προχωρήσει η αναβάθμιση θα πρέπει να κλείσουν '
                            'όλες οι εφαρμογές στο δίκτυο. Αυτή τη στιγμή '
                            'είναι ανοιχτές:',
                  style: theme.textTheme.bodyMedium,
                ),
                if (others.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final session in others)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              describeActiveSession(
                                session,
                                now: now,
                                myAppVersion: mine,
                                databaseSchemaVersion: databaseSchemaVersionV1,
                              ),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Αν ενημερώσετε τώρα, ο υπολογιστής σας δεν θα μπορεί να '
                    'ανοίξει τη βάση μέχρι να κλείσουν όλες. Δεν υπάρχει '
                    'επιστροφή στην προηγούμενη έκδοση.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          // Το «Αργότερα» είναι η ασφαλής επιλογή, γι' αυτό παίρνει τη θέση που
          // πατά κανείς χωρίς να διαβάσει.
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Αργότερα'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ενημέρωση τώρα'),
          ),
        ],
      );
    },
  );
  return proceed == true;
}
