import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/crash_log_service.dart';
import 'startup_journal.dart';

/// Σημειώσεις εκκίνησης που συλλέγονται όταν αποτυχίες δεν μπλοκάρουν την εκκίνηση,
/// αλλά πρέπει να φανούν στην τεχνική οθόνη σφάλματος.
class StartupNotice {
  const StartupNotice({required this.phase, required this.error, this.stack});

  final String phase;
  final Object error;
  final StackTrace? stack;
}

final List<StartupNotice> _startupNotices = <StartupNotice>[];

/// Συσσωρευμένες σημειώσεις εκκίνησης (μη τροποποιήσιμη όψη).
List<StartupNotice> get startupNotices => List.unmodifiable(_startupNotices);

/// Καταγράφει μια σημείωση εκκίνησης στην ουρά και κάνει debugPrint.
void recordStartupNotice(String phase, Object error, [StackTrace? stack]) {
  _startupNotices.add(StartupNotice(phase: phase, error: error, stack: stack));
  debugPrint('StartupNotice — $phase: $error');
  if (stack != null && stack.toString().trim().isNotEmpty) {
    debugPrint(stack.toString());
  }
}

/// Διαγράφει όλη την ουρά (για απομόνωση τεστ).
void clearStartupNotices() {
  _startupNotices.clear();
}

/// Τρέχει βήμα εκκίνησης που **δεν** επιτρέπεται να ρίξει την εφαρμογή.
///
/// Ένα βήμα νοικοκυριού έχει τρεις εκβάσεις και καθεμιά έχει τον δικό της
/// παραλήπτη: η επιτυχία πάει στο ημερολόγιο που βλέπει ο χρήστης, η
/// παράλειψη πουθενά (σιωπή είναι ο κανόνας όταν δεν υπήρχε δουλειά), και η
/// αποτυχία και στα δύο — γραμμή προειδοποίησης στην οθόνη **και** σημείωση
/// για την τεχνική αναφορά. Χωρίς αυτή τη συνάρτηση κάθε καλών θα θυμόταν
/// μόνος του και τα τρία, που σημαίνει ότι κάποιος θα ξεχνούσε.
///
/// Το [action] επιστρέφει `true` όταν έκανε πράγματι δουλειά.
Future<void> runStartupHousekeeping(
  String label,
  Future<bool> Function() action,
) async {
  final step = StartupJournal.instance.begin(label);
  try {
    final didWork = await action();
    if (didWork) {
      step.ok();
    } else {
      step.skip();
    }
  } catch (e, st) {
    step.warn(e.toString());
    recordStartupNotice(label, e, st);
  }
}

/// Μορφοποιημένη έκθεση των σημειώσεων εκκίνησης.
/// Επιστρέφει `null` αν η ουρά είναι άδεια.
String? startupNoticesReport() {
  if (_startupNotices.isEmpty) return null;
  final buf = StringBuffer('--- Προειδοποιήσεις εκκίνησης ---\n');
  for (final notice in _startupNotices) {
    buf.writeln('${notice.phase}: ${notice.error}');
  }
  return buf.toString().trimRight();
}

/// Γράφει τις σημειώσεις στο ημερολόγιο σφαλμάτων μόλις αυτό είναι διαθέσιμο.
/// Η ουρά αδειάζει ΜΟΝΟ αν το ημερολόγιο ήταν πράγματι διαθέσιμο.
void flushStartupNoticesToCrashLog() {
  final service = CrashLogService.instanceOrNull;
  if (service == null) return;

  // Αν ο φάκελος logs δεν υπάρχει, θεωρούμε ότι το ημερολόγιο δεν είναι
  // διαθέσιμο (π.χ. onStartup απέτυχε).
  if (!Directory(service.logsDirectory).existsSync()) return;

  for (final notice in _startupNotices) {
    service.logError(
      Exception('${notice.phase}: ${notice.error}'),
      notice.stack ?? StackTrace.empty,
      fatal: false,
    );
  }
  _startupNotices.clear();
}
