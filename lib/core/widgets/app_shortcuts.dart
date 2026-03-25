import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_helper.dart';
import '../database/database_init_result.dart';
import '../database/database_init_runner.dart';
import '../providers/greek_dictionary_provider.dart';
import 'main_shell.dart';

/// Intent για γρήγορη καταγραφή κλήσης (εστίαση στο πεδίο εσωτερικού).
class QuickCaptureIntent extends Intent {
  const QuickCaptureIntent();
}

/// Root-level Shortcuts και Actions για την εφαρμογή.
/// Κρατά σε state το τρέχον αποτέλεσμα βάσης και ξανατρέχει τους ελέγχους
/// όταν ο χρήστης επιστρέφει από Ρυθμίσεις.
class AppShortcuts extends ConsumerStatefulWidget {
  const AppShortcuts({
    super.key,
    required this.initialDatabaseResult,
    required this.initialIsLocalDevMode,
  });

  final DatabaseInitResult initialDatabaseResult;
  final bool initialIsLocalDevMode;

  @override
  ConsumerState<AppShortcuts> createState() => _AppShortcutsState();
}

class _AppShortcutsState extends ConsumerState<AppShortcuts>
    with WidgetsBindingObserver {
  late DatabaseInitResult _databaseResult;
  late bool _isLocalDevMode;

  static final Map<ShortcutActivator, Intent> _shortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyL, control: true, alt: true):
            const QuickCaptureIntent(),
        SingleActivator(LogicalKeyboardKey.keyC, control: true, alt: true):
            const QuickCaptureIntent(),
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _databaseResult = widget.initialDatabaseResult;
    _isLocalDevMode = widget.initialIsLocalDevMode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(greekDictionaryServiceProvider.future));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(DatabaseHelper.instance.tryWalCheckpoint());
    }
  }

  @override
  void didUpdateWidget(covariant AppShortcuts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDatabaseResult != widget.initialDatabaseResult ||
        oldWidget.initialIsLocalDevMode != widget.initialIsLocalDevMode) {
      _databaseResult = widget.initialDatabaseResult;
      _isLocalDevMode = widget.initialIsLocalDevMode;
    }
  }

  Future<void> _recheckDatabase() async {
    try {
      final runnerResult = await runDatabaseInitChecks(
        closeConnectionFirst: true,
      );
      if (mounted) {
        setState(() {
          _databaseResult = runnerResult.result;
          _isLocalDevMode = runnerResult.isLocalDevMode;
        });
      }
    } catch (e, st) {
      if (mounted) {
        setState(() {
          _databaseResult = DatabaseInitResult.fromException(e, null, st);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          QuickCaptureIntent: CallbackAction<QuickCaptureIntent>(
            onInvoke: (QuickCaptureIntent intent) => null,
          ),
        },
        child: MainShell(
          databaseResult: _databaseResult,
          isLocalDevMode: _isLocalDevMode,
          onReturnFromSettings: _recheckDatabase,
        ),
      ),
    );
  }
}
