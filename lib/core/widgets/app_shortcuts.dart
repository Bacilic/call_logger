import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/database/services/database_exit_backup.dart';
import '../services/desktop_window_service.dart';
import '../services/settings_service.dart';
import '../services/shutdown_coordinator.dart';
import '../services/shutdown_trace_service.dart';
import '../services/crash_log_service.dart';
import '../database/database_helper.dart';
import '../database/database_init_result.dart';
import '../database/database_init_runner.dart';
import '../providers/core_lexicon_provider.dart';
import '../providers/quick_call_providers.dart';
import '../../features/calls/screens/widgets/quick_call_dialog.dart';
import 'main_shell.dart';
import 'quick_call_shortcuts.dart';
import 'shutdown_progress_screen.dart';

/// Root-level Shortcuts και Actions για την εφαρμογή.
/// Κρατά σε state το τρέχον αποτέλεσμα βάσης και ξανατρέχει τους ελέγχους
/// όταν ο χρήστης επιστρέφει από Ρυθμίσεις.
class AppShortcuts extends ConsumerStatefulWidget {
  const AppShortcuts({
    super.key,
    required this.initialDatabaseResult,
    required this.initialIsLocalDevMode,
    @visibleForTesting this.shutdownCoordinatorFactory,
    @visibleForTesting this.shutdownTraceFactory,
  });

  final DatabaseInitResult initialDatabaseResult;
  final bool initialIsLocalDevMode;

  /// Εργοστάσιο συντονιστή (μόνο για τεστ — παράκαμψη πραγματικών βημάτων).
  final ShutdownCoordinator Function()? shutdownCoordinatorFactory;

  /// Εργοστάσιο ιχνηλάτη (μόνο για τεστ).
  final Future<ShutdownTraceService?> Function()? shutdownTraceFactory;

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
  bool _showShutdownProgress = false;
  ShutdownCoordinator? _activeShutdownCoordinator;

  static final Map<ShortcutActivator, Intent> _shortcuts = quickCallShortcuts;

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
      unawaited(ref.read(coreLexiconProvider.notifier).bootstrapFromSavedPath());
    });
    HardwareKeyboard.instance.addHandler(_handleGlobalQuickCallKey);
  }

  void _invokeQuickCapture() {
    if (!isQuickCallCaptureAvailable(ref)) return;
    unawaited(showQuickCallDialog(context));
  }

  bool _handleGlobalQuickCallKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;

    final keyboard = HardwareKeyboard.instance;
    Intent? matched;
    for (final entry in _shortcuts.entries) {
      if (entry.key.accepts(event, keyboard)) {
        matched = entry.value;
        break;
      }
    }
    if (matched is! QuickCaptureIntent) return false;
    if (!isQuickCallCaptureAvailable(ref)) return true;

    _invokeQuickCapture();
    return true;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalQuickCallKey);
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

    // ΣΗΜΕΙΩΣΗ (μη το εκλάβεις ως ξεχασμένο κλείσιμο παραθύρου): εδώ ΔΕΝ καλείται
    // πια `windowManager.destroy()`. Ο ShutdownCoordinator.run() εκτελεί τα βήματα
    // καθαρισμού και τερματίζει ο ίδιος με exit(0), παρακάμπτοντας το teardown της
    // μηχανής Flutter που κατέρρεε (0xc0000005). Το παράθυρο μένει σκόπιμα ορατό,
    // δείχνοντας την οθόνη προόδου — δεν το κρύβουμε, γιατί ο διάλογος προόδου ζει
    // μέσα σε αυτό. Δες lib/core/services/shutdown_coordinator.dart.
    final coordinator = widget.shutdownCoordinatorFactory?.call() ??
        ShutdownCoordinator(
          persistWindowBounds: _persistWindowBoundsIfNeeded,
          walCheckpoint: () =>
              DatabaseHelper.instance.tryWalCheckpoint(mode: 'FULL'),
          exitBackup: DatabaseExitBackup.runIfEnabled,
          closeConnection: DatabaseHelper.instance.closeConnection,
          closeCrashLog: () async {
            await CrashLogService.instanceOrNull?.onShutdown();
          },
        );

    if (mounted) {
      setState(() {
        _activeShutdownCoordinator = coordinator;
      });
    } else {
      _activeShutdownCoordinator = coordinator;
    }

    final trace = widget.shutdownTraceFactory != null
        ? await widget.shutdownTraceFactory!()
        : await _createTraceServiceIfEnabled();
    if (trace != null) {
      await trace.beginSession();
      trace.listenTo(coordinator.events);
    }

    var shutdownStillRunning = true;
    final revealTimer = scheduleShutdownProgressReveal(
      onReveal: () {
        if (!mounted) return;
        setState(() => _showShutdownProgress = true);
      },
      isShutdownStillRunning: () => shutdownStillRunning && mounted,
    );

    try {
      // Ένα frame ώστε το Offstage ShutdownProgressScreen να συνδεθεί στο stream
      // πριν ξεκινήσουν τα γεγονότα των βημάτων.
      await WidgetsBinding.instance.endOfFrame;
      await coordinator.run();
    } finally {
      shutdownStillRunning = false;
      revealTimer.cancel();
      await trace?.endSession();
    }
  }

  Future<ShutdownTraceService?> _createTraceServiceIfEnabled() async {
    try {
      final settings = SettingsService();
      final enabled = await settings.getShutdownTraceEnabled();
      if (!enabled) return null;
      final dbPath = await settings.getDatabasePath();
      if (dbPath.trim().isEmpty) return null;
      return ShutdownTraceService(
        logsDirectory:
            ShutdownTraceService.logsDirectoryForDatabasePath(dbPath),
        enabled: true,
        retentionCount: await settings.getShutdownTraceRetentionCount(),
      );
    } catch (_) {
      return null;
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
    final coordinator = _activeShutdownCoordinator;
    final shell = Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          QuickCaptureIntent: CallbackAction<QuickCaptureIntent>(
            onInvoke: (QuickCaptureIntent intent) {
              _invokeQuickCapture();
              return null;
            },
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

    if (coordinator == null) return shell;

    // Η οθόνη προόδου μένει στο δέντρο (Offstage) ώστε να συλλέγει γεγονότα
    // από την αρχή· γίνεται ορατή μόνο μετά το κατώφλι των 500 ms.
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!_showShutdownProgress) shell,
        Offstage(
          offstage: !_showShutdownProgress,
          child: ShutdownProgressScreen(events: coordinator.events),
        ),
      ],
    );
  }
}
