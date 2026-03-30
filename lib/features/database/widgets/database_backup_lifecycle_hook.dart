import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/database_backup_settings.dart';
import '../providers/database_backup_settings_provider.dart';
import '../services/database_backup_service.dart';

/// Εκκίνηση περιοδικού backup όσο τρέχει η εφαρμογή (σύμφωνα με [DatabaseBackupSettings]).
class DatabaseBackupLifecycleHook extends ConsumerStatefulWidget {
  const DatabaseBackupLifecycleHook({super.key});

  @override
  ConsumerState<DatabaseBackupLifecycleHook> createState() =>
      _DatabaseBackupLifecycleHookState();
}

class _DatabaseBackupLifecycleHookState
    extends ConsumerState<DatabaseBackupLifecycleHook> {
  Timer? _timer;
  DateTime? _lastPeriodicBackup;
  DatabaseBackupSettings? _armedSettings;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _ensureTimer(DatabaseBackupSettings s) {
    if (_armedSettings == s) return;
    _armedSettings = s;
    _timer?.cancel();
    _timer = null;
    if (s.interval == DatabaseBackupInterval.never) return;
    if (s.destinationDirectory.trim().isEmpty) return;

    final d = s.interval == DatabaseBackupInterval.every4Hours
        ? const Duration(hours: 4)
        : const Duration(hours: 1);

    _timer = Timer.periodic(d, (_) => unawaited(_onPeriodicTick()));
  }

  Future<void> _onPeriodicTick() async {
    if (!mounted) return;
    final current = ref.read(databaseBackupSettingsProvider);
    if (current.destinationDirectory.trim().isEmpty) return;
    if (current.interval == DatabaseBackupInterval.never) return;

    final now = DateTime.now();
    if (current.interval == DatabaseBackupInterval.daily) {
      if (_lastPeriodicBackup != null &&
          now.difference(_lastPeriodicBackup!).inHours < 24) {
        return;
      }
    }

    final result = await DatabaseBackupService.runBackup(
      current,
      requireDestination: true,
    );
    if (result.success) {
      _lastPeriodicBackup = now;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await ref.read(databaseBackupSettingsProvider.notifier).load();
      if (!mounted) return;
      _ensureTimer(ref.read(databaseBackupSettingsProvider));
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(databaseBackupSettingsProvider);
    ref.listen(databaseBackupSettingsProvider, (prev, next) {
      if (prev == next) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureTimer(ref.read(databaseBackupSettingsProvider));
      });
    });
    return const SizedBox.shrink();
  }
}
