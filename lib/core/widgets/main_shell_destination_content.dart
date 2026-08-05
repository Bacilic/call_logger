import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../providers/app_instances_provider.dart';
import '../providers/main_nav_request_provider.dart';
import '../services/app_instance_registry.dart';
import '../database/database_state_notice.dart';
import '../database/database_switch_success_notice.dart';
import '../services/settings_service.dart';
import '../../features/calls/screens/calls_screen.dart';
import '../../features/database/debug/error_scenarios_screen.dart';
import '../../features/database/screens/database_browser_screen.dart';
import '../../features/database/widgets/database_settings_dialog.dart';
import '../../features/dictionary/screens/dictionary_manager_screen.dart';
import '../../features/directory/screens/directory_screen.dart';
import '../../features/history/screens/history_screen.dart';
import '../../features/lamp/screens/lamp_screen.dart';
import '../../features/tasks/screens/tasks_screen.dart';
import 'main_nav_destination.dart';
import 'main_shell.dart';

/// Περιεχόμενο προορισμού πλοήγησης και στήλη κύριου panel.
///
/// Συνεργάτης του [MainShellState] (Σύνθεση) — κρατά και την κατάσταση της
/// λωρίδας ειδοποίησης παλιάς/κενής βάσης.
class MainShellDestinationContent {
  MainShellDestinationContent(this.host);

  final MainShellState host;

  /// Η λωρίδα παλιάς/κενής βάσης έκλεισε σε αυτή τη συνεδρία.
  bool _databaseNoticeDismissedThisSession = false;
  bool _acknowledgedNoticeLoaded = false;
  String? _acknowledgedNoticeIdentity;
  late DatabaseStateNotice _databaseStateNotice;

  void initDatabaseStateNotice() {
    _databaseStateNotice = _evaluateCurrentDatabaseNotice();
    unawaited(_loadAcknowledgedDatabaseNoticeIdentity());
  }

  void syncDatabaseStateNotice(MainShell oldWidget) {
    if (oldWidget.databaseProfile != host.widget.databaseProfile ||
        oldWidget.databaseResult.path != host.widget.databaseResult.path) {
      final next = _evaluateCurrentDatabaseNotice();
      if (next.identity != _databaseStateNotice.identity) {
        _databaseNoticeDismissedThisSession = false;
      }
      _databaseStateNotice = next;
    }
  }

  DatabaseStateNotice _evaluateCurrentDatabaseNotice() {
    final path = host.widget.databaseResult.path?.trim() ?? '';
    var modifiedAt = DateTime.fromMillisecondsSinceEpoch(0);
    if (path.isNotEmpty) {
      try {
        modifiedAt = File(path).lastModifiedSync();
      } catch (_) {}
    }
    return evaluateDatabaseStateNotice(
      profile: host.widget.databaseProfile,
      dbPath: path,
      fileModifiedAt: modifiedAt,
      now: DateTime.now(),
    );
  }

  Future<void> _loadAcknowledgedDatabaseNoticeIdentity() async {
    final value = await SettingsService()
        .getAcknowledgedDatabaseNoticeIdentity();
    if (!host.mounted) return;
    _acknowledgedNoticeIdentity = value;
    _acknowledgedNoticeLoaded = true;
    host.notifyShellChanged();
  }

  Future<void> _dismissDatabaseStateNotice() async {
    final identity = _databaseStateNotice.identity;
    _databaseNoticeDismissedThisSession = true;
    _acknowledgedNoticeIdentity = identity;
    host.notifyShellChanged();
    await SettingsService().setAcknowledgedDatabaseNoticeIdentity(identity);
  }

  bool get _showDatabaseStateNotice {
    if (!_acknowledgedNoticeLoaded) return false;
    if (_databaseStateNotice.kind == DatabaseNoticeKind.none) return false;
    if (_databaseNoticeDismissedThisSession) return false;
    return _acknowledgedNoticeIdentity != _databaseStateNotice.identity;
  }

  Future<void> _openDatabaseSettingsDialog() async {
    if (!host.mounted) return;
    await showDatabaseSettingsDialog(
      host.context,
      onDatabaseLifecycleChanged:
          host.widget.onDatabaseReopened ?? () async {},
    );
  }

  Widget _contentForDestination(MainNavDestination dest) {
    switch (dest) {
      case MainNavDestination.calls:
        return const CallsScreen();
      case MainNavDestination.tasks:
        return PrimaryScrollController.none(child: const TasksScreen());
      case MainNavDestination.directory:
        return const DirectoryScreen();
      case MainNavDestination.history:
        return const HistoryScreen();
      case MainNavDestination.database:
        return DatabaseBrowserScreen(
          databaseResult: host.widget.databaseResult,
          onOpenDatabaseSettings: _openDatabaseSettingsDialog,
          onDatabaseReopened: host.widget.onDatabaseReopened,
        );
      case MainNavDestination.dictionary:
        return DictionaryManagerScreen(
          databaseResult: host.widget.databaseResult,
        );
      case MainNavDestination.lamp:
        return const LampScreen();
      case MainNavDestination.debugScenarios:
        return const ErrorScenariosScreen();
    }
  }

  /// Απορροφά scroll notifications από εκκρεμότητες ώστε το εξωτερικό AppBar
  /// να μην ενεργοποιεί Material 3 scrolled-under tint.
  Widget absorbTasksScrollForOuterAppBar(
    MainNavDestination dest,
    Widget child,
  ) {
    if (dest != MainNavDestination.tasks) return child;
    return NotificationListener<ScrollNotification>(
      onNotification: (_) => true,
      child: child,
    );
  }

  Widget destinationContentColumn(MainNavDestination dest) {
    final context = host.context;
    final switchSuccessMessage = host.ref.watch(
      databaseSwitchSuccessNoticeProvider,
    );
    final topBanner = topDatabaseBanner(
      showStateNotice: _showDatabaseStateNotice,
      hasSwitchSuccess: switchSuccessMessage != null,
    );
    final instances = host.ref.watch(appInstancesProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (host.widget.isLocalDevMode)
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
        // Ξεχωριστή λωρίδα από την «τοπική βάση» από πάνω: εκείνη σημαίνει
        // «η δικτυακή διαδρομή δεν ήταν προσβάσιμη», αυτή «τα δεδομένα που
        // βλέπεις είναι κατασκευασμένα». Δύο διαφορετικά πράγματα που κάποτε
        // μοιράζονταν το ίδιο σήμα. Η αναγνώριση γίνεται από την υπογραφή του
        // σπορέα ΜΕΣΑ στη βάση — το όνομα του αρχείου δεν λέει τίποτα.
        if (host.widget.databaseProfile?.hasDebugScenarioSignature ?? false)
          Container(
            key: const ValueKey('debug_scenario_database_banner'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            color: Colors.deepOrange.shade300,
            child: Text(
              'ΔΟΚΙΜΑΣΤΙΚΗ ΒΑΣΗ ΣΕΝΑΡΙΩΝ - Τα δεδομένα είναι τεχνητά',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        // Δύο αντίγραφα της εφαρμογής μοιράζονται τις ίδιες ρυθμίσεις. Δεν
        // είναι κίνδυνος — είναι πληροφορία που εξηγεί γιατί μια ρύθμιση
        // «άλλαξε μόνη της». Ο σύνδεσμος οδηγεί στη μόνιμη λίστα.
        if (instances != null && instances.shouldNotify)
          _SharedInstancesBanner(
            otherLabel: AppInstanceRegistry.shortFolderLabel(
              instances.others.first.executablePath,
            ),
            onOpenList: () => host.ref
                .read(mainNavRequestProvider.notifier)
                .request(
                  const MainNavRequest(
                    destination: MainNavDestination.database,
                  ),
                ),
            onDismiss: () => unawaited(dismissAppInstancesNotice(host.ref)),
          ),
        if (topBanner == TopDatabaseBanner.warning)
          Material(
            color: Colors.amber.shade200,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _databaseStateNotice.message,
                      key: const ValueKey('database_state_notice_banner'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('database_state_notice_dismiss'),
                    tooltip: 'Κλείσιμο',
                    icon: const Icon(
                      Icons.close,
                      size: 20,
                      color: Colors.black87,
                    ),
                    onPressed: () {
                      unawaited(_dismissDatabaseStateNotice());
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
        if (topBanner == TopDatabaseBanner.success)
          Material(
            color: Colors.green.shade200,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      switchSuccessMessage!,
                      key: const ValueKey('database_switch_success_banner'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('database_switch_success_dismiss'),
                    tooltip: 'Κλείσιμο',
                    icon: const Icon(
                      Icons.close,
                      size: 20,
                      color: Colors.black87,
                    ),
                    onPressed: () {
                      host.ref
                          .read(databaseSwitchSuccessNoticeProvider.notifier)
                          .clear();
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
        if (dest == MainNavDestination.database &&
            !host.widget.databaseResult.isSuccess)
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
                        host.widget.databaseResult.message ??
                            'Άγνωστο σφάλμα με τη βάση δεδομένων.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.red.shade700,
                        ),
                      ),
                      if (host.widget.databaseResult.details != null) ...[
                        const SizedBox(height: 4),
                        Tooltip(
                          message: host.widget.databaseResult.details!,
                          child: Text(
                            host.widget.databaseResult.details!,
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
      ],
    );
  }
}

/// Λωρίδα «οι ρυθμίσεις μοιράζονται με άλλο αντίγραφο».
///
/// Διακριτική και κλειστή: πληροφορία, όχι προειδοποίηση κινδύνου. Ο σύνδεσμος
/// οδηγεί στη μόνιμη λίστα αντιγράφων (οθόνη Βάσης Δεδομένων).
class _SharedInstancesBanner extends StatelessWidget {
  const _SharedInstancesBanner({
    required this.otherLabel,
    required this.onOpenList,
    required this.onDismiss,
  });

  /// Σύντομη ετικέτα φακέλου — η πλήρης διαδρομή ζει στην κάρτα, όπου
  /// διαβάζεται και επιλέγεται· εδώ θα έσπαγε σε άσχημο σημείο.
  final String otherLabel;
  final VoidCallback onOpenList;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.labelLarge?.copyWith(
      color: Colors.black87,
    );

    return Material(
      color: Colors.blueGrey.shade100,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: RichText(
                key: const ValueKey('shared_instances_banner'),
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: baseStyle,
                  children: [
                    TextSpan(
                      text:
                          'Οι ρυθμίσεις χρησιμοποιούνται και από άλλο αντίγραφο '
                          'της εφαρμογής ($otherLabel). Δείτε τα ',
                    ),
                    TextSpan(
                      text: 'αντίγραφα',
                      style: baseStyle?.copyWith(
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()..onTap = onOpenList,
                    ),
                    const TextSpan(
                      text: ' ή εκτελέστε με --profile για ανεξάρτητη λειτουργία.',
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('shared_instances_banner_dismiss'),
              tooltip: 'Κλείσιμο',
              icon: const Icon(Icons.close, size: 20, color: Colors.black87),
              onPressed: onDismiss,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
