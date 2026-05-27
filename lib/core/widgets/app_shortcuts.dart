import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/database/services/database_exit_backup.dart';
import '../services/desktop_window_service.dart';
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
    with WidgetsBindingObserver, WindowListener {
  late DatabaseInitResult _databaseResult;
  late bool _isLocalDevMode;
  Timer? _windowBoundsSaveTimer;
  final DesktopWindowService _desktopWindow = DesktopWindowService();
  AppLifecycleListener? _appLifecycleListener;
  bool _windowCloseHandling = false;

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
    if (Platform.isWindows) {
      try {
        windowManager.addListener(this);
      } on MissingPluginException catch (_) {}
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await windowManager.setPreventClose(true);
        } on MissingPluginException catch (_) {}
      });
    }
    _databaseResult = widget.initialDatabaseResult;
    _isLocalDevMode = widget.initialIsLocalDevMode;
    _appLifecycleListener = AppLifecycleListener(
      onExitRequested: () async => AppExitResponse.exit,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(greekDictionaryServiceProvider.future));
    });
  }

  @override
  void dispose() {
    _windowBoundsSaveTimer?.cancel();
    _appLifecycleListener?.dispose();
    _appLifecycleListener = null;
    if (Platform.isWindows) {
      try {
        windowManager.removeListener(this);
      } on MissingPluginException catch (_) {}
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void onWindowResized() {
    if (!Platform.isWindows) return;
    _schedulePersistWindowBounds();
  }

  @override
  void onWindowMoved() {
    if (!Platform.isWindows) return;
    _schedulePersistWindowBounds();
  }

  void _schedulePersistWindowBounds() {
    _windowBoundsSaveTimer?.cancel();
    _windowBoundsSaveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_persistWindowBoundsIfNeeded());
    });
  }

  Future<void> _persistWindowBoundsIfNeeded() async {
    if (!Platform.isWindows) return;
    try {
      await _desktopWindow.persistWindowBounds(windowManager);
    } on MissingPluginException catch (_) {}
  }

  @override
  void onWindowClose() {
    if (!Platform.isWindows) return;
    if (_windowCloseHandling) return;
    unawaited(_handleWindowsClose());
  }

  Future<void> _handleWindowsClose() async {
    if (_windowCloseHandling) return;
    _windowCloseHandling = true;
    try {
      await _persistWindowBoundsIfNeeded();
      await DatabaseHelper.instance.tryWalCheckpoint();
      await DatabaseExitBackup.runIfEnabled();
      await DatabaseHelper.instance.closeConnection();
    } catch (_) {
      // Συνεχίζουμε προς κλείσιμο παραθύρου ακόμα κι αν αποτύχει βήμα.
    } finally {
      if (Platform.isWindows) {
        try {
          await windowManager.destroy();
        } on MissingPluginException catch (_) {}
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_windowCloseHandling) return;
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
          onDatabaseReopened: _recheckDatabase,
        ),
      ),
    );
  }
}
