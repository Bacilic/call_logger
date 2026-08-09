import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/database/services/database_exit_backup.dart';
import '../services/app_close_controller.dart';
import '../services/desktop_window_service.dart';
import '../services/settings_service.dart';
import '../services/shutdown_coordinator.dart';
import '../services/shutdown_runner.dart';
import '../services/shutdown_trace_service.dart';
import '../services/crash_log_service.dart';
import '../database/database_file_classifier.dart';
import '../database/database_helper.dart';
import '../database/database_init_result.dart';
import '../database/database_init_runner.dart';
import '../providers/core_lexicon_provider.dart';
import '../providers/quick_call_providers.dart';
import '../../features/calls/screens/widgets/quick_call_dialog.dart';
import '../../features/history/models/lansweeper_report_scope.dart';
import '../../features/history/widgets/lansweeper/lansweeper_report_launcher.dart';
import 'app_keyboard_shortcuts.dart';
import 'main_shell.dart';
import 'shutdown_progress_screen.dart';

/// Root-level Shortcuts και Actions για την εφαρμογή.
/// Κρατά σε state το τρέχον αποτέλεσμα βάσης και ξανατρέχει τους ελέγχους
/// όταν ο χρήστης επιστρέφει από Ρυθμίσεις.
class AppShortcuts extends ConsumerStatefulWidget {
  const AppShortcuts({
    super.key,
    required this.initialDatabaseResult,
    required this.initialIsLocalDevMode,
    this.initialDatabaseProfile,
    this.missingApplicationFiles = const <String>[],
    @visibleForTesting this.shutdownCoordinatorFactory,
    @visibleForTesting this.shutdownTraceFactory,
  });

  final DatabaseInitResult initialDatabaseResult;
  final bool initialIsLocalDevMode;
  final DatabaseFileProfile? initialDatabaseProfile;

  /// Ελλείποντα κρίσιμα αρχεία, όπως τα βρήκε ο δομικός έλεγχος της εκκίνησης.
  /// Το κέλυφος μόνο τα ανακοινώνει — δεν τα ανακαλύπτει.
  final List<String> missingApplicationFiles;

  /// Εργοστάσιο συντονιστή (μόνο για τεστ — παράκαμψη πραγματικών βημάτων).
  final ShutdownCoordinator Function()? shutdownCoordinatorFactory;

  /// Εργοστάσιο ιχνηλάτη (μόνο για τεστ).
  final Future<ShutdownTraceService?> Function()? shutdownTraceFactory;

  @override
  ConsumerState<AppShortcuts> createState() => _AppShortcutsState();
}

class _AppShortcutsState extends ConsumerState<AppShortcuts>
    with WidgetsBindingObserver, WindowListener
    implements ShutdownUiPresenter {
  late DatabaseInitResult _databaseResult;
  late bool _isLocalDevMode;
  DatabaseFileProfile? _databaseProfile;
  Timer? _windowBoundsSaveTimer;
  final DesktopWindowService _desktopWindow = DesktopWindowService();
  AppLifecycleListener? _appLifecycleListener;
  bool _windowCloseHandling = false;
  bool _showShutdownProgress = false;
  ShutdownCoordinator? _activeShutdownCoordinator;
  Timer? _shutdownRevealTimer;
  bool _shutdownStillRunning = false;

  static final Map<ShortcutActivator, Intent> _shortcuts = appKeyboardShortcuts;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isWindows) {
      try {
        // Ο listener μένει για onWindowResized/onWindowMoved. Το κλείσιμο ΔΕΝ
        // περνά από εδώ: το `preventClose` ανήκει στον AppCloseController, ώστε
        // να υπάρχει χειριστής και στις οθόνες που αντικαθιστούν το κέλυφος.
        windowManager.addListener(this);
      } on MissingPluginException catch (_) {}
      appCloseController.registerUiHandler(_onCloseRequestedFromUi);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _warnIfMissingStartupAssets();
      });
    }
    _databaseResult = widget.initialDatabaseResult;
    _isLocalDevMode = widget.initialIsLocalDevMode;
    _databaseProfile = widget.initialDatabaseProfile;
    _appLifecycleListener = AppLifecycleListener(
      onExitRequested: () async => AppExitResponse.exit,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(coreLexiconProvider.notifier).bootstrapFromSavedPath(),
      );
    });
    HardwareKeyboard.instance.addHandler(_handleGlobalShortcutKey);
  }

  /// Μη-μπλοκάρουσα ανακοίνωση όταν λείπουν μη-μοιραία αρχεία πόρων.
  ///
  /// Ο εντοπισμός έγινε στην αρχικοποίηση, πριν από τους ελέγχους βάσης· εδώ
  /// μένει μόνο η εμφάνιση. Τρέχει το πολύ μία φορά ανά εκκίνηση.
  void _warnIfMissingStartupAssets() {
    if (!mounted) return;
    final missing = widget.missingApplicationFiles;
    if (missing.isEmpty) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Text(
          'Λείπουν αρχεία της εφαρμογής: ${missing.join(', ')}. '
          'Η εφαρμογή λειτουργεί περιορισμένα· συνιστάται επανεγκατάσταση.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
            },
            child: const Text('Το κατάλαβα'),
          ),
        ],
      ),
    );
  }

  void _invokeQuickCapture() {
    if (!isQuickCallCaptureAvailable(ref)) return;
    unawaited(showQuickCallDialog(context));
  }

  /// Η καθημερινή εργασία «όλες οι σημερινές κλήσεις στο Lansweeper», ένα
  /// πάτημα από παντού. Ο φρουρός διπλού ανοίγματος ζει στον launcher.
  void _invokeLansweeperReport() {
    unawaited(
      openLansweeperReport(context, ref, scope: LansweeperReportScope.today),
    );
  }

  bool _handleGlobalShortcutKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;

    final keyboard = HardwareKeyboard.instance;
    Intent? matched;
    for (final entry in _shortcuts.entries) {
      if (entry.key.accepts(event, keyboard)) {
        matched = entry.value;
        break;
      }
    }

    switch (matched) {
      case QuickCaptureIntent():
        // Το `true` και όταν η καταγραφή δεν είναι διαθέσιμη: η συντόμευση
        // αναγνωρίστηκε, δεν πρέπει να πέσει σε άλλον χειριστή.
        if (isQuickCallCaptureAvailable(ref)) _invokeQuickCapture();
        return true;
      case LansweeperReportIntent():
        _invokeLansweeperReport();
        return true;
      default:
        return false;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalShortcutKey);
    _windowBoundsSaveTimer?.cancel();
    _shutdownRevealTimer?.cancel();
    _appLifecycleListener?.dispose();
    _appLifecycleListener = null;
    if (Platform.isWindows) {
      // Αποσύρεται μόνο ο δανεισμένος χειριστής· το `preventClose` παραμένει
      // οπλισμένο και ο AppCloseController αναλαμβάνει από εδώ και πέρα.
      appCloseController.unregisterUiHandler(_onCloseRequestedFromUi);
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

  /// Καλείται από τον [AppCloseController] όσο αυτό το κέλυφος είναι ζωντανό.
  void _onCloseRequestedFromUi() {
    if (!Platform.isWindows) return;
    if (_windowCloseHandling) return;
    unawaited(_handleWindowsClose());
  }

  Future<void> _handleWindowsClose() async {
    if (_windowCloseHandling) return;
    _windowCloseHandling = true;

    final runner = ShutdownRunner(
      createCoordinator: () =>
          widget.shutdownCoordinatorFactory?.call() ??
          ShutdownCoordinator(
            persistWindowBounds: _persistWindowBoundsIfNeeded,
            walCheckpoint: () =>
                DatabaseHelper.instance.tryWalCheckpoint(mode: 'FULL'),
            exitBackup: DatabaseExitBackup.runIfEnabled,
            closeConnection: DatabaseHelper.instance.closeConnection,
            closeCrashLog: () async {
              await CrashLogService.instanceOrNull?.onShutdown();
            },
          ),
      createTrace: () =>
          widget.shutdownTraceFactory?.call() ?? _createTraceServiceIfEnabled(),
      presenter: this,
    );
    await runner.run();
  }

  // --- ShutdownUiPresenter: μόνο παρουσίαση, καμία ενορχήστρωση ---

  @override
  void onShutdownStarted(ShutdownCoordinator coordinator) {
    if (mounted) {
      setState(() => _activeShutdownCoordinator = coordinator);
    } else {
      _activeShutdownCoordinator = coordinator;
    }
    _shutdownStillRunning = true;
    _shutdownRevealTimer = scheduleShutdownProgressReveal(
      onReveal: () {
        if (!mounted) return;
        setState(() => _showShutdownProgress = true);
      },
      isShutdownStillRunning: () => _shutdownStillRunning && mounted,
    );
  }

  /// Ένα frame ώστε το Offstage ShutdownProgressScreen να συνδεθεί στο stream
  /// πριν ξεκινήσουν τα γεγονότα των βημάτων.
  @override
  Future<void> awaitNextFrame() => WidgetsBinding.instance.endOfFrame;

  @override
  void onShutdownFinished() {
    _shutdownStillRunning = false;
    _shutdownRevealTimer?.cancel();
    _shutdownRevealTimer = null;
  }

  Future<ShutdownTraceService?> _createTraceServiceIfEnabled() async {
    try {
      final settings = SettingsService();
      final enabled = await settings.catalogs.getShutdownTraceEnabled();
      if (!enabled) return null;
      final dbPath = await settings.getDatabasePath();
      if (dbPath.trim().isEmpty) return null;
      return ShutdownTraceService(
        logsDirectory: ShutdownTraceService.logsDirectoryForDatabasePath(
          dbPath,
        ),
        enabled: true,
        retentionCount: await settings.catalogs
            .getShutdownTraceRetentionCount(),
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
        oldWidget.initialIsLocalDevMode != widget.initialIsLocalDevMode ||
        oldWidget.initialDatabaseProfile != widget.initialDatabaseProfile) {
      _databaseResult = widget.initialDatabaseResult;
      _isLocalDevMode = widget.initialIsLocalDevMode;
      _databaseProfile = widget.initialDatabaseProfile;
    }
  }

  Future<void> _recheckDatabase() async {
    try {
      // Μετά από εναλλαγή βάσης η νέα διαδρομή έχει ήδη επαληθευτεί και η
      // σύνδεση είναι ανοιχτή: κλείνουμε και ξανανοίγουμε μόνο αν κάτι όντως
      // άλλαξε από τότε.
      final runnerResult = await runDatabaseInitChecks(
        closeConnectionFirst: true,
        reuseIfFresh: true,
      );
      if (mounted) {
        setState(() {
          _databaseResult = runnerResult.result;
          _isLocalDevMode = runnerResult.isLocalDevMode;
          _databaseProfile = runnerResult.databaseProfile;
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
          LansweeperReportIntent: CallbackAction<LansweeperReportIntent>(
            onInvoke: (LansweeperReportIntent intent) {
              _invokeLansweeperReport();
              return null;
            },
          ),
        },
        child: MainShell(
          databaseResult: _databaseResult,
          isLocalDevMode: _isLocalDevMode,
          databaseProfile: _databaseProfile,
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
