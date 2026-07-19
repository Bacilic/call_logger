import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_init_result.dart';
import '../../features/calls/screens/calls_screen.dart';
import '../../features/database/debug/error_scenarios_screen.dart';
import '../../features/database/screens/database_browser_screen.dart';
import '../../features/dictionary/screens/dictionary_manager_screen.dart';
import '../../features/lamp/screens/lamp_screen.dart';

import '../../features/database/widgets/database_settings_panel.dart';
import '../../features/tasks/screens/tasks_screen.dart';
import '../../features/directory/screens/directory_screen.dart';
import '../../features/history/screens/history_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../providers/core_lexicon_provider.dart';
import '../../features/dictionary/widgets/core_lexicon_setup_dialog.dart';
import '../providers/directory_tab_intent_provider.dart';
import '../providers/equipment_focus_intent_provider.dart';
import '../providers/history_audit_immersive_provider.dart';
import '../providers/lexicon_full_mode_provider.dart';
import '../providers/lamp_open_settings_intent_provider.dart';
import '../providers/lamp_read_path_health_provider.dart';
import '../../features/history/providers/history_application_audit_view_provider.dart';
import '../providers/main_nav_request_provider.dart';
import '../providers/call_department_prefill_intent_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shell_navigation_intent_provider.dart';
import '../providers/task_focus_intent_provider.dart';
import '../providers/quick_call_providers.dart';
import 'main_nav_destination.dart';
import 'quick_call_fab.dart';
import '../services/settings_service.dart';
import '../about/widgets/version_chip.dart';
import '../updates/update_startup_prompt.dart';
import 'nav_rail_attention_badge.dart';
import '../../features/tasks/providers/tasks_provider.dart';
import '../../features/calls/provider/call_entry_provider.dart';

part 'main_shell_nav_icons.dart';
part 'main_shell_destination_content.dart';

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

class _MainShellState extends ConsumerState<MainShell>
    with MainShellDestinationContentMixin {
  /// True αν άλλαξε η διαδρομή βάσης από Ρυθμίσεις και απαιτείται επανεκκίνηση.
  bool _pendingRestartDueToPathChange = false;
  MainNavDestination _selectedDestination = MainNavDestination.calls;

  /// Λεζάντες πλευρικής μπάρας (όταν το πλάτος παραθύρου επιτρέπει extended rail).
  bool _navRailShowLabels = true;

  static const double _kNavRailWideBreakpoint = 760;

  @override
  void initState() {
    super.initState();
    _loadNavRailShowLabels();
  }

  Future<void> _loadNavRailShowLabels() async {
    final value = await SettingsService().getNavRailShowLabels();
    if (mounted) setState(() => _navRailShowLabels = value);
  }

  /// Ίδια λογική με [NavigationRail.onDestinationSelected] (λεξικό, ιστορικό immersive).
  Future<void> _selectDestination(MainNavDestination d) async {
    if (d == MainNavDestination.dictionary) {
      final loaded = ref.read(coreLexiconLoadedProvider);
      if (!loaded) {
        final ok = await showCoreLexiconSetupDialog(context: context, ref: ref);
        if (!ok || !mounted) return;
      }
    }
    if (!mounted) return;
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
    final callPrefillDepartment = req.callPrefillDepartmentName?.trim();

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
    if (callPrefillDepartment != null && callPrefillDepartment.isNotEmpty) {
      ref
          .read(callDepartmentPrefillIntentProvider.notifier)
          .prefill(callPrefillDepartment);
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

  static List<MainNavDestination> _visibleDestinations(
    bool showLampNav,
    bool showDatabaseNav,
    bool showDictionaryNav,
    bool enableSpellCheck,
    bool coreLexiconLoaded,
  ) {
    final showDictionary = isDictionaryNavVisible(
      enableSpellCheck: enableSpellCheck,
      showDictionaryNav: showDictionaryNav,
      coreLexiconLoaded: coreLexiconLoaded,
    );
    return [
      MainNavDestination.calls,
      MainNavDestination.tasks,
      MainNavDestination.directory,
      MainNavDestination.history,
      if (showLampNav) MainNavDestination.lamp,
      if (showDatabaseNav) MainNavDestination.database,
      if (showDictionary) MainNavDestination.dictionary,
    ];
  }

  NavigationRailDestination _railDestination(
    MainNavDestination dest,
    bool showBadge,
    int pendingCount, {
    required bool isOnCallsScreen,
    required bool showCoreLexiconWarning,
    required bool showLampReadPathWarning,
  }) {
    switch (dest) {
      case MainNavDestination.calls:
        final callsIcon = _CallsNavigationIcon(isOnCallsScreen: isOnCallsScreen);
        return NavigationRailDestination(
          icon: callsIcon,
          selectedIcon: callsIcon,
          label: const Text('Κλήσεις'),
        );
      case MainNavDestination.tasks:
        final tasksIcon = _TasksNavigationIcon(
          showBadge: showBadge,
          pendingCount: pendingCount,
        );
        return NavigationRailDestination(
          icon: tasksIcon,
          selectedIcon: tasksIcon,
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
          icon: _DictionaryNavigationIcon(showWarning: showCoreLexiconWarning),
          label: const Text('Λεξικό'),
        );
      case MainNavDestination.lamp:
        return NavigationRailDestination(
          icon: _LampNavigationIcon(showWarning: showLampReadPathWarning),
          label: const Text('Λάμπα'),
        );
      case MainNavDestination.debugScenarios:
        // Δεν εμφανίζεται στο rail — πρόσβαση μόνο από κουμπί πάνω από την έκδοση.
        return const NavigationRailDestination(
          icon: Icon(Icons.bug_report_outlined),
          label: Text('Σενάρια'),
        );
    }
  }

  Future<void> _openSettingsScreen() async {
    final pathBefore = await SettingsService().getDatabasePath();
    if (!mounted) return;
    ref.read(settingsRouteOpenForQuickCallProvider.notifier).setOpen(true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => SettingsScreen(
            onAfterDatabaseChanged:
                widget.onDatabaseReopened ?? widget.onReturnFromSettings,
          ),
        ),
      );
    } finally {
      ref.read(settingsRouteOpenForQuickCallProvider.notifier).setOpen(false);
    }
    if (!mounted) return;
    await widget.onReturnFromSettings?.call();
    if (!mounted) return;
    final pathAfter = await SettingsService().getDatabasePath();
    if (pathBefore != pathAfter) {
      setState(() => _pendingRestartDueToPathChange = true);
    }
    ref.invalidate(showLampNavProvider);
    ref.invalidate(showDatabaseNavProvider);
    ref.invalidate(showDictionaryNavProvider);
    ref.invalidate(showQuickCallFabProvider);
    ref.invalidate(coreLexiconProvider);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final showBadgeAsync = ref.watch(showTasksBadgeProvider);
    final pendingCountAsync = ref.watch(globalPendingTasksCountProvider);
    final showBadge = showBadgeAsync.value ?? true;
    final pendingCount = pendingCountAsync.value ?? 0;
    final showLampNav = ref
        .watch(showLampNavProvider)
        .maybeWhen(data: (v) => v, orElse: () => true);
    final showDatabaseNav = ref
        .watch(showDatabaseNavProvider)
        .maybeWhen(data: (v) => v, orElse: () => true);
    final showDictionaryNav = ref
        .watch(showDictionaryNavProvider)
        .maybeWhen(data: (v) => v, orElse: () => true);
    final enableSpellCheck = ref
        .watch(enableSpellCheckProvider)
        .maybeWhen(data: (v) => v, orElse: () => true);
    final coreLexiconLoaded = ref.watch(coreLexiconLoadedProvider);
    final showCoreLexiconWarning = enableSpellCheck && !coreLexiconLoaded;
    final showLampReadPathWarning = ref.watch(lampShowNavWarningProvider);
    final visibleDestinations = _visibleDestinations(
      showLampNav,
      showDatabaseNav,
      showDictionaryNav,
      enableSpellCheck,
      coreLexiconLoaded,
    );
    final effectiveDestination =
        visibleDestinations.contains(_selectedDestination) ||
            _selectedDestination == MainNavDestination.debugScenarios
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
      unawaited(_selectDestination(req.destination));
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

    final currentNavForQuickCall = ref.watch(mainShellEffectiveDestinationProvider);
    if (currentNavForQuickCall != effectiveDestination) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(mainShellEffectiveDestinationProvider.notifier)
            .setDestination(effectiveDestination);
      });
    }

    if (dictionaryImmersive || historyImmersive) {
      return Stack(
        children: [
          Scaffold(
            appBar: null,
            floatingActionButton: const QuickCallFloatingButton(),
            body: SafeArea(
              child: _destinationContentColumn(
                dictionaryImmersive
                    ? MainNavDestination.dictionary
                    : MainNavDestination.history,
                pendingRestartDueToPathChange: _pendingRestartDueToPathChange,
              ),
            ),
          ),
          const UpdateStartupPromptListener(),
        ],
      );
    }

    final showAppBar = effectiveDestination != MainNavDestination.calls;
    final isLampDestination = effectiveDestination == MainNavDestination.lamp;
    return Stack(
      children: [
        Scaffold(
          appBar: showAppBar
              ? AppBar(
                  title: isLampDestination
                      ? Row(
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            const Text('Λάμπα'),
                          ],
                        )
                      : const Text('Καταγραφή Κλήσεων'),
                  actions: isLampDestination
                      ? <Widget>[
                          IconButton(
                            icon: const Icon(Icons.settings),
                            tooltip: 'Ρυθμίσεις Λάμπας',
                            onPressed: () {
                              ref
                                  .read(
                                    lampOpenSettingsRequestProvider.notifier,
                                  )
                                  .request();
                            },
                          ),
                        ]
                      : null,
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
                  selectedIndex: selectedRailIndex < 0 ? 0 : selectedRailIndex,
                  onDestinationSelected: (index) {
                    unawaited(
                      _selectDestination(visibleDestinations[index]),
                    );
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
                    padding: const EdgeInsets.only(
                      bottom: 8,
                      left: 8,
                      right: 8,
                    ),
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
                      _railDestination(
                        d,
                        showBadge,
                        pendingCount,
                        isOnCallsScreen:
                            effectiveDestination == MainNavDestination.calls,
                        showCoreLexiconWarning:
                            d == MainNavDestination.dictionary &&
                            showCoreLexiconWarning,
                        showLampReadPathWarning:
                            d == MainNavDestination.lamp &&
                            showLampReadPathWarning,
                      ),
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
          Expanded(
            child: _absorbTasksScrollForOuterAppBar(
              effectiveDestination,
              _destinationContentColumn(
                effectiveDestination,
                pendingRestartDueToPathChange: _pendingRestartDueToPathChange,
              ),
            ),
          ),
        ],
      ),
        ),
        const UpdateStartupPromptListener(),
      ],
    );
  }
}
