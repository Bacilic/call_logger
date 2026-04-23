import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_init_result.dart';
import '../../features/calls/provider/import_log_provider.dart';
import '../../features/calls/provider/lookup_provider.dart';
import '../../features/calls/screens/calls_screen.dart';
import '../../features/calls/screens/widgets/import_console_widget.dart';
import '../../features/database/screens/database_browser_screen.dart';
import '../../features/dictionary/screens/dictionary_manager_screen.dart';

import '../../features/database/widgets/database_settings_panel.dart';
import '../../features/tasks/screens/tasks_screen.dart';
import '../../features/directory/screens/directory_screen.dart';
import '../../features/history/screens/history_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../providers/greek_dictionary_provider.dart';
import '../providers/directory_tab_intent_provider.dart';
import '../providers/equipment_focus_intent_provider.dart';
import '../providers/history_audit_immersive_provider.dart';
import '../providers/lexicon_full_mode_provider.dart';
import '../../features/history/providers/history_application_audit_view_provider.dart';
import '../providers/main_nav_request_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shell_navigation_intent_provider.dart';
import '../providers/task_focus_intent_provider.dart';
import 'main_nav_destination.dart';
import '../services/import_service.dart';
import '../services/import_types.dart';
import '../services/settings_service.dart';
import '../about/widgets/version_chip.dart';
import '../../features/tasks/providers/tasks_provider.dart';

/// Κύριο κέλυφος εφαρμογής: πλευρική πλοήγηση και περιοχή περιεχομένου.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({
    super.key,
    required this.databaseResult,
    required this.isLocalDevMode,
    this.onReturnFromSettings,
    this.onDatabaseReopened,
  });

  final DatabaseInitResult databaseResult;
  final bool isLocalDevMode;

  /// Κλήση όταν ο χρήστης κλείνει την οθόνη Ρυθμίσεων· ξανατρέχουν οι έλεγχοι βάσης.
  final Future<void> Function()? onReturnFromSettings;

  /// Μετά από συντήρηση (νέα βάση κ.λπ.)· επανασύνδεση/έλεγχοι όπως με Ρυθμίσεις.
  final Future<void> Function()? onDatabaseReopened;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  /// True αν άλλαξε η διαδρομή βάσης από Ρυθμίσεις και απαιτείται επανεκκίνηση.
  bool _pendingRestartDueToPathChange = false;
  MainNavDestination _selectedDestination = MainNavDestination.calls;

  /// Εμφάνιση κουμπιού Import Excel (ρύθμιση από Ρυθμίσεις· προεπιλογή false).
  bool _showImportExcelButton = false;

  /// Λεζάντες πλευρικής μπάρας (όταν το πλάτος παραθύρου επιτρέπει extended rail).
  bool _navRailShowLabels = true;

  static const double _kNavRailWideBreakpoint = 760;

  @override
  void initState() {
    super.initState();
    _loadShowImportExcelSetting();
    _loadNavRailShowLabels();
  }

  Future<void> _loadShowImportExcelSetting() async {
    final value = await SettingsService().getShowImportExcelButton();
    if (mounted) setState(() => _showImportExcelButton = value);
  }

  Future<void> _loadNavRailShowLabels() async {
    final value = await SettingsService().getNavRailShowLabels();
    if (mounted) setState(() => _navRailShowLabels = value);
  }

  /// Ίδια λογική με [NavigationRail.onDestinationSelected] (λεξικό, ιστορικό immersive).
  void _selectDestination(MainNavDestination d) {
    setState(() => _selectedDestination = d);
    if (d == MainNavDestination.dictionary) {
      ref.read(lexiconFullModeProvider.notifier).setTrue();
      ref.read(historyAuditImmersiveProvider.notifier).setFalse();
      ref.read(historyApplicationAuditViewProvider.notifier).setFalse();
    } else {
      ref.read(lexiconFullModeProvider.notifier).setFalse();
    }
    if (d != MainNavDestination.history) {
      ref.read(historyAuditImmersiveProvider.notifier).setFalse();
      ref.read(historyApplicationAuditViewProvider.notifier).setFalse();
    }
  }

  void _dispatchFollowUpNavIntents(MainNavRequest req) {
    final tab = req.directoryTabIndex;
    final equipId = req.equipmentFocusEntityId;
    final taskId = req.taskFocusEntityId;
    final callId = req.callFocusEntityId;

    if (req.destination == MainNavDestination.history && callId != null) {
      ref.read(historyApplicationAuditViewProvider.notifier).setFalse();
      ref.read(historyAuditImmersiveProvider.notifier).setFalse();
    }

    if (tab != null) {
      ref.read(directoryTabIntentProvider.notifier).jumpTo(tab);
    }
    if (taskId != null) {
      ref.read(taskFocusIntentProvider.notifier).focus(taskId);
    }

    void focusEquipment() {
      if (equipId != null) {
        ref.read(equipmentFocusIntentProvider.notifier).focus(equipId);
      }
    }

    if (equipId != null && tab == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        focusEquipment();
      });
    } else {
      focusEquipment();
    }
  }

  Widget _tasksNavigationIcon(bool showBadge, int pendingCount) {
    final core = Tooltip(
      waitDuration: const Duration(milliseconds: 600),
      showDuration: const Duration(seconds: 4),
      message:
          'Προβλήματα που χρήζουν παρακολούθησης\nΑνοιχτές εργασίες & υπενθυμίσεις',
      child: const Icon(Icons.task_alt, key: ValueKey('nav_rail_tasks')),
    );
    return Badge(
      isLabelVisible: showBadge && pendingCount > 0,
      label: Text(pendingCount.toString()),
      child: core,
    );
  }

  static List<MainNavDestination> _visibleDestinations(
    bool showDatabaseNav,
    bool showDictionaryNav,
  ) {
    return [
      MainNavDestination.calls,
      MainNavDestination.tasks,
      MainNavDestination.directory,
      MainNavDestination.history,
      if (showDatabaseNav) MainNavDestination.database,
      if (showDictionaryNav) MainNavDestination.dictionary,
    ];
  }

  NavigationRailDestination _railDestination(
    MainNavDestination dest,
    bool showBadge,
    int pendingCount,
  ) {
    switch (dest) {
      case MainNavDestination.calls:
        return NavigationRailDestination(
          icon: Tooltip(
            waitDuration: const Duration(milliseconds: 600),
            showDuration: const Duration(seconds: 4),
            message:
                'Καταγραφή νέας κλήσης τεχνικής υποστήριξης\nΚύρια οθόνη – πατήστε εδώ όταν χτυπά τηλέφωνο',
            child: const Icon(
              Icons.phone_in_talk,
              key: ValueKey('nav_rail_calls'),
            ),
          ),
          label: const Text('Κλήσεις'),
        );
      case MainNavDestination.tasks:
        return NavigationRailDestination(
          icon: _tasksNavigationIcon(showBadge, pendingCount),
          selectedIcon: _tasksNavigationIcon(showBadge, pendingCount),
          label: const Text('Εκκρεμότητες'),
        );
      case MainNavDestination.directory:
        return NavigationRailDestination(
          icon: Tooltip(
            waitDuration: const Duration(milliseconds: 600),
            showDuration: const Duration(seconds: 4),
            message:
                'Διαχείριση χρηστών και εξοπλισμού\nΠροσθήκη / διόρθωση ονομάτων, τμημάτων, υπολογιστών',
            child: const Icon(
              Icons.contacts,
              key: ValueKey('nav_rail_directory'),
            ),
          ),
          label: const Text('Κατάλογος'),
        );
      case MainNavDestination.history:
        return NavigationRailDestination(
          icon: Tooltip(
            waitDuration: const Duration(milliseconds: 600),
            showDuration: const Duration(seconds: 4),
            message:
                'Προηγούμενες κλήσεις & αναζήτηση\nΕμφάνιση, τροποποίηση ή διαγραφή παλιών καταγραφών',
            child: const Icon(Icons.history, key: ValueKey('nav_rail_history')),
          ),
          label: const Text('Ιστορικό'),
        );
      case MainNavDestination.database:
        return NavigationRailDestination(
          icon: Tooltip(
            waitDuration: const Duration(milliseconds: 600),
            showDuration: const Duration(seconds: 4),
            message:
                'Εργαλεία διαχείρισης & εποπτείας βάσης\nΡυθμίσεις βάσης, αντίγραφα ασφαλείας, προβολή πινάκων',
            child: const Icon(
              Icons.storage,
              key: ValueKey('nav_rail_database'),
            ),
          ),
          label: const Text('Βάση Δεδομένων'),
        );
      case MainNavDestination.dictionary:
        return NavigationRailDestination(
          icon: Tooltip(
            waitDuration: const Duration(milliseconds: 600),
            showDuration: const Duration(seconds: 4),
            message:
                'Διαχείριση λεξικού ορθογραφίας\nΕισαγωγές, συγχώνευση και εξαγωγή (compile) σε αρχείο',
            child: const Icon(
              Icons.menu_book,
              key: ValueKey('nav_rail_dictionary'),
            ),
          ),
          label: const Text('Λεξικό'),
        );
    }
  }

  Widget _contentForDestination(MainNavDestination dest) {
    switch (dest) {
      case MainNavDestination.calls:
        return const CallsScreen();
      case MainNavDestination.tasks:
        return const TasksScreen();
      case MainNavDestination.directory:
        return const DirectoryScreen();
      case MainNavDestination.history:
        return const HistoryScreen();
      case MainNavDestination.database:
        return DatabaseBrowserScreen(
          databaseResult: widget.databaseResult,
          onOpenDatabaseSettings: _openDatabaseSettingsDialog,
          onDatabaseReopened: widget.onDatabaseReopened,
        );
      case MainNavDestination.dictionary:
        return DictionaryManagerScreen(databaseResult: widget.databaseResult);
    }
  }

  Future<void> _openDatabaseSettingsDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920, maxHeight: 640),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: DatabaseSettingsPanel(),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSettingsScreen() async {
    final pathBefore = await SettingsService().getDatabasePath();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => SettingsScreen(
          onAfterDatabaseChanged:
              widget.onDatabaseReopened ?? widget.onReturnFromSettings,
        ),
      ),
    );
    if (!mounted) return;
    await widget.onReturnFromSettings?.call();
    if (!mounted) return;
    final pathAfter = await SettingsService().getDatabasePath();
    if (pathBefore != pathAfter) {
      setState(() => _pendingRestartDueToPathChange = true);
    }
    ref.invalidate(showDatabaseNavProvider);
    ref.invalidate(showDictionaryNavProvider);
    ref.invalidate(greekDictionaryServiceProvider);
    await _loadShowImportExcelSetting();
    if (mounted) setState(() {});
  }

  /// Περιεχόμενο προορισμού με μπάνερ dev/βάσης και επανεκκίνησης (χωρίς rail).
  Widget _destinationContentColumn(MainNavDestination dest) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.isLocalDevMode)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            color: Colors.amber,
            child: Text(
              'ΛΕΙΤΟΥΡΓΙΑ ΑΝΑΠΤΥΞΗΣ - Τοπική Βάση Δεδομένων',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (dest == MainNavDestination.database &&
            !widget.databaseResult.isSuccess)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.databaseResult.message ??
                            'Άγνωστο σφάλμα με τη βάση δεδομένων.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.red.shade700,
                        ),
                      ),
                      if (widget.databaseResult.details != null) ...[
                        const SizedBox(height: 4),
                        Tooltip(
                          message: widget.databaseResult.details!,
                          child: Text(
                            widget.databaseResult.details!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Colors.red.shade300,
                                  fontSize: 11,
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Ρυθμίσεις βάσης δεδομένων',
                  icon: const Icon(Icons.dataset_linked),
                  onPressed: _openDatabaseSettingsDialog,
                ),
              ],
            ),
          ),
        Expanded(child: _contentForDestination(dest)),
        if (_pendingRestartDueToPathChange)
          Material(
            color: Colors.grey.shade800,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          children: [
                            const TextSpan(
                              text:
                                  'Έγινε αλλαγή διαδρομής βάσης. Παρακαλώ επανεκκινήστε την εφαρμογή για να ισχύσει πλήρως. ',
                            ),
                            TextSpan(
                              text: 'Επανεκκίνηση...',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {
                                  exit(0);
                                },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final showBadgeAsync = ref.watch(showTasksBadgeProvider);
    final pendingCountAsync = ref.watch(globalPendingTasksCountProvider);
    final showBadge = showBadgeAsync.value ?? true;
    final pendingCount = pendingCountAsync.value ?? 0;
    final showDatabaseNav = ref
        .watch(showDatabaseNavProvider)
        .maybeWhen(data: (v) => v, orElse: () => true);
    final showDictionaryNav = ref
        .watch(showDictionaryNavProvider)
        .maybeWhen(data: (v) => v, orElse: () => true);
    final visibleDestinations = _visibleDestinations(
      showDatabaseNav,
      showDictionaryNav,
    );
    final effectiveDestination =
        visibleDestinations.contains(_selectedDestination)
        ? _selectedDestination
        : MainNavDestination.calls;
    final selectedRailIndex = visibleDestinations.indexOf(effectiveDestination);
    if (effectiveDestination != _selectedDestination) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedDestination != effectiveDestination) {
          setState(() {
            _selectedDestination = effectiveDestination;
            if (effectiveDestination != MainNavDestination.dictionary) {
              ref.read(lexiconFullModeProvider.notifier).setFalse();
            }
            if (effectiveDestination != MainNavDestination.history) {
              ref.read(historyAuditImmersiveProvider.notifier).setFalse();
              ref.read(historyApplicationAuditViewProvider.notifier).setFalse();
            }
          });
        }
      });
    }

    final lexiconFullMode = ref.watch(lexiconFullModeProvider);
    final dictionaryImmersive =
        lexiconFullMode &&
        effectiveDestination == MainNavDestination.dictionary;

    final historyAuditImmersive = ref.watch(historyAuditImmersiveProvider);
    final historyImmersive =
        historyAuditImmersive &&
        effectiveDestination == MainNavDestination.history;

    ref.listen<bool>(lexiconFullModeProvider, (previous, next) {
      if (next == true) {
        ref.read(historyAuditImmersiveProvider.notifier).setFalse();
        ref.read(historyApplicationAuditViewProvider.notifier).setFalse();
      }
      if (previous == true && next == false && mounted) {
        final pending = ref
            .read(shellNavigationIntentProvider.notifier)
            .takePending();
        setState(() {
          _selectedDestination = pending ?? MainNavDestination.calls;
        });
      }
    });

    ref.listen<bool>(historyAuditImmersiveProvider, (previous, next) {
      if (next == true) {
        ref.read(lexiconFullModeProvider.notifier).setFalse();
      }
      if (previous == true && next == false && mounted) {
        final pending = ref
            .read(shellNavigationIntentProvider.notifier)
            .takePending();
        if (pending != null) {
          setState(() => _selectedDestination = pending);
        }
      }
    });

    ref.listen<MainNavRequest?>(mainNavRequestProvider, (previous, req) {
      if (req == null || !mounted) return;
      ref.read(mainNavRequestProvider.notifier).clear();
      _selectDestination(req.destination);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _dispatchFollowUpNavIntents(req);
      });
    });

    final wideEnoughForExtendedRail =
        MediaQuery.sizeOf(context).width >= _kNavRailWideBreakpoint;
    final railExtended = wideEnoughForExtendedRail && _navRailShowLabels;
    final railLabelStyle =
        NavigationRailTheme.of(context).unselectedLabelTextStyle ??
        Theme.of(context).textTheme.labelMedium;

    if (dictionaryImmersive || historyImmersive) {
      return Scaffold(
        appBar: null,
        floatingActionButton: null,
        body: SafeArea(
          child: _destinationContentColumn(
            dictionaryImmersive
                ? MainNavDestination.dictionary
                : MainNavDestination.history,
          ),
        ),
      );
    }

    final showAppBar = effectiveDestination != MainNavDestination.calls;
    return Scaffold(
      appBar: showAppBar
          ? AppBar(title: const Text('Καταγραφή Κλήσεων'))
          : null,
      floatingActionButton: _showImportExcelButton
          ? FloatingActionButton(
              onPressed: _onImportExcel,
              tooltip: 'Import Excel',
              child: const Icon(Icons.upload_file),
            )
          : null,
      body: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: NavigationRail(
                  extended: railExtended,
                  selectedIndex: selectedRailIndex,
                  onDestinationSelected: (index) {
                    _selectDestination(visibleDestinations[index]);
                  },
                  leading: wideEnoughForExtendedRail
                      ? IconButton(
                          key: const ValueKey('nav_rail_toggle'),
                          icon: Icon(
                            railExtended
                                ? Icons.chevron_left
                                : Icons.chevron_right,
                          ),
                          tooltip: railExtended
                              ? 'Σύμπτυξη πλοήγησης'
                              : 'Επέκταση πλοήγησης',
                          onPressed: () async {
                            final next = !_navRailShowLabels;
                            setState(() => _navRailShowLabels = next);
                            await SettingsService().setNavRailShowLabels(next);
                          },
                        )
                      : null,
                  trailing: Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                    child: Tooltip(
                      waitDuration: const Duration(milliseconds: 600),
                      showDuration: const Duration(seconds: 4),
                      message: 'Γενικές ρυθμίσεις της εφαρμογής',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _openSettingsScreen,
                        child: SizedBox(
                          height: 48,
                          width: railExtended ? 220 : 56,
                          child: Row(
                            mainAxisAlignment: railExtended
                                ? MainAxisAlignment.start
                                : MainAxisAlignment.center,
                            children: [
                              if (railExtended) const SizedBox(width: 12),
                              const Icon(Icons.settings),
                              if (railExtended) ...[
                                const SizedBox(width: 16),
                                Text('Ρυθμίσεις', style: railLabelStyle),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  destinations: [
                    for (final d in visibleDestinations)
                      _railDestination(d, showBadge, pendingCount),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: VersionChip(extended: railExtended),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: _destinationContentColumn(effectiveDestination)),
        ],
      ),
    );
  }

  Future<void> _onImportExcel() async {
    ref.read(importLogProvider.notifier).clearLogs();
    if (!context.mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Import Excel – Live Console',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            const Expanded(child: ImportConsoleWidget()),
          ],
        ),
      ),
    );
    final messenger = ScaffoldMessenger.of(context);
    await Future.delayed(const Duration(milliseconds: 100));
    try {
      final result = await ImportService().importFromExcel(
        onLog: (msg, [level]) => ref
            .read(importLogProvider.notifier)
            .addLog(msg, level ?? ImportLogLevel.info),
      );
      if (!result.success && result.errorMessage != null) {
        messenger.showSnackBar(SnackBar(content: Text(result.errorMessage!)));
      } else if (result.success &&
          (result.usersInserted > 0 || result.equipmentInserted > 0)) {
        ref.invalidate(lookupServiceProvider);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Εισήχθησαν ${result.usersInserted} χρήστες και ${result.equipmentInserted} υπολογιστές',
            ),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Σφάλμα: $e')));
    }
  }
}
