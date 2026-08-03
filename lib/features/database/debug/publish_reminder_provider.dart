import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/about/models/changelog_entry.dart';
import '../../../core/about/services/changelog_service.dart';
import 'integrity_debug_seeder_service.dart';
import 'publish_reminder.dart';

/// Κατάσταση υπενθύμισης δημοσίευσης για το σήμα της αποσφαλμάτωσης.
///
/// Διαβάζει το `changelog.json` **από τον δίσκο του έργου**, όχι από το
/// ενσωματωμένο αντίγραφο: η Δημοσίευση γράφει στο αρχείο του έργου, οπότε με
/// το ενσωματωμένο το σήμα δεν θα έσβηνε ποτέ μετά από δημοσίευση.
///
/// Εκτός debug επιστρέφει πάντα ήρεμη κατάσταση — το εικονίδιο δεν υπάρχει καν.
final publishReminderProvider = FutureProvider<PublishReminderStatus>((
  ref,
) async {
  if (!IntegrityDebugSeederService.isEnabled) {
    return PublishReminderStatus.quiet;
  }

  final entries = await ChangelogService(loadAsset: _readChangelogSource).load();
  if (entries.isEmpty) return PublishReminderStatus.quiet;

  ChangelogEntry? unreleased;
  ChangelogEntry? lastRelease;
  for (final entry in entries) {
    if (entry.isUnreleased) {
      unreleased ??= entry;
    } else {
      lastRelease ??= entry;
    }
  }

  return evaluatePublishReminder(
    unreleasedEntryCount: unreleased?.entryCount ?? 0,
    now: DateTime.now(),
    lastReleaseDate: DateTime.tryParse(lastRelease?.date.trim() ?? ''),
    lastReleaseVersion: lastRelease?.version,
  );
});

/// Πηγή αλήθειας: το αρχείο του έργου· εφεδρικά το ενσωματωμένο asset.
Future<String> _readChangelogSource(String assetPath) async {
  try {
    final file = File(p.join(Directory.current.path, assetPath));
    if (await file.exists()) return await file.readAsString();
  } catch (_) {
    // Πέφτουμε στο ενσωματωμένο αντίγραφο παρακάτω.
  }
  return rootBundle.loadString(assetPath);
}
