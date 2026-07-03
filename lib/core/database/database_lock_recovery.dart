import 'dart:async';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config/app_config.dart';
import 'database_init_progress_provider.dart';

/// Timeout για ephemeral WAL checkpoint και PRAGMA wal_checkpoint στο κλείσιμο.
const int databaseWalCheckpointTimeoutSeconds = 5;

/// Συγχώνευση WAL στο κύριο αρχείο με προσωρινή σύνδεση (μετά από crash).
Future<bool> tryEphemeralWalCheckpoint(String dbPath) async {
  if (!await File(dbPath).exists()) return false;
  final walPath = '$dbPath-wal';
  if (!await File(walPath).exists()) return true;

  Database? db;
  try {
    db = await openDatabase(
      dbPath,
      readOnly: false,
      singleInstance: true,
    ).timeout(
      Duration(seconds: databaseWalCheckpointTimeoutSeconds),
      onTimeout: () => throw TimeoutException(
        'ephemeral openDatabase timed out after '
        '${databaseWalCheckpointTimeoutSeconds}s',
      ),
    );
    await db
        .rawQuery('PRAGMA wal_checkpoint(TRUNCATE)')
        .timeout(
          Duration(seconds: databaseWalCheckpointTimeoutSeconds),
          onTimeout: () => throw TimeoutException(
            'ephemeral wal_checkpoint(TRUNCATE) timed out after '
            '${databaseWalCheckpointTimeoutSeconds}s',
          ),
        );
    await db.close();
    db = null;

    final walFile = File(walPath);
    if (!await walFile.exists()) return true;
    return (await walFile.stat()).size <= 0;
  } catch (_) {
    return false;
  } finally {
    if (db != null && db.isOpen) {
      try {
        await db.close();
      } catch (_) {}
    }
  }
}

/// Διαγραφή stale sidecar μόνο αν δεν είναι κλειδωμένο και (για WAL) κενό.
Future<({bool deleted, String? message})> tryDeleteStaleSidecarIfSafe(
  String sidecarPath,
) async {
  final file = File(sidecarPath);
  try {
    if (!await file.exists()) {
      return (deleted: false, message: null);
    }
    final stat = await file.stat();
    if (stat.size <= 0) {
      await file.delete();
      return (
        deleted: true,
        message: 'Διαγράφηκε κενό sidecar: $sidecarPath',
      );
    }

    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.append);
      await raf.close();
      raf = null;
    } catch (_) {
      await raf?.close();
      return (
        deleted: false,
        message:
            'Παραλείφθηκε διαγραφή $sidecarPath: το αρχείο φαίνεται ενεργά κλειδωμένο.',
      );
    }

    if (sidecarPath.endsWith('-wal')) {
      return (
        deleted: false,
        message:
            'Παραλείφθηκε διαγραφή $sidecarPath: παραμένει μη κενό μετά checkpoint.',
      );
    }

    await file.delete();
    return (
      deleted: true,
      message: 'Διαγράφηκε stale sidecar: $sidecarPath',
    );
  } catch (e) {
    return (
      deleted: false,
      message: 'Αποτυχία καθαρισμού $sidecarPath: $e',
    );
  }
}

/// Προληπτικός καθαρισμός stale WAL sidecars πριν το άνοιγμα (όχι σε UNC διαδρομές).
Future<String?> cleanStaleSidecarsIfSafe(
  String dbPath, {
  DatabaseInitProgressNotifier? progressNotifier,
}) async {
  if (AppConfig.isUncDatabasePath(dbPath)) return null;
  progressNotifier?.setStep('Προληπτικός καθαρισμός WAL');
  final messages = <String>[];

  final walPath = '$dbPath-wal';
  final walFile = File(walPath);
  if (await walFile.exists()) {
    final walSize = (await walFile.stat()).size;
    if (walSize > 0) {
      final merged = await tryEphemeralWalCheckpoint(dbPath);
      if (!merged) {
        messages.add(
          'Παραλείφθηκε καθαρισμός WAL: αποτυχία checkpoint — τα δεδομένα διατηρήθηκαν.',
        );
        return messages.join('\n');
      }
    }
  }

  for (final suffix in const <String>['-wal', '-shm']) {
    final sidecarPath = '$dbPath$suffix';
    final outcome = await tryDeleteStaleSidecarIfSafe(sidecarPath);
    if (outcome.message != null) {
      messages.add(outcome.message!);
    }
  }
  if (messages.isEmpty) return null;
  return messages.join('\n');
}
