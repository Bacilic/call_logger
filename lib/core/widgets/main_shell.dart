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
import '../../features/directory/screens/directory_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../services/import_service.dart';
import '../services/import_types.dart';
import '../services/settings_service.dart';

/// Κύριο κέλυφος εφαρμογής: πλευρική πλοήγηση και περιοχή περιεχομένου.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({
    super.key,
    required this.databaseResult,
    required this.isLocalDevMode,
    this.onReturnFromSettings,
  });

  final DatabaseInitResult databaseResult;
  final bool isLocalDevMode;
  /// Κλήση όταν ο χρήστης κλείνει την οθόνη Ρυθμίσεων· ξανατρέχουν οι έλεγχοι βάσης.
  final Future<void> Function()? onReturnFromSettings;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  /// True αν άλλαξε η διαδρομή βάσης από Ρυθμίσεις και απαιτείται επανεκκίνηση.
  bool _pendingRestartDueToPathChange = false;
  /// Επιλεγμένο στοιχείο πλοήγησης: 0=Κλήσεις, 1=Εκκρεμότητες, 2=Κατάλογος, 3=Ιστορικό, 4=Βάση Δεδομένων.
  int _selectedIndex = 0;
  /// Εμφάνιση κουμπιού Import Excel (ρύθμιση από Ρυθμίσεις· προεπιλογή false).
  bool _showImportExcelButton = false;

  @override
  void initState() {
    super.initState();
    _loadShowImportExcelSetting();
  }

  Future<void> _loadShowImportExcelSetting() async {
    final value = await SettingsService().getShowImportExcelButton();
    if (mounted) setState(() => _showImportExcelButton = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Καταγραφή Κλήσεων'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Ρυθμίσεις',
            onPressed: () async {
              final pathBefore =
                  await SettingsService().getDatabasePath();
              if (!context.mounted) return;
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => const SettingsScreen(),
                ),
              );
              if (!context.mounted) return;
              await widget.onReturnFromSettings?.call();
              if (!context.mounted) return;
              final pathAfter =
                  await SettingsService().getDatabasePath();
              if (pathBefore != pathAfter) {
                setState(() => _pendingRestartDueToPathChange = true);
              }
              await _loadShowImportExcelSetting();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      floatingActionButton: _showImportExcelButton
          ? FloatingActionButton(
              onPressed: _onImportExcel,
              tooltip: 'Import Excel',
              child: const Icon(Icons.upload_file),
            )
          : null,
      body: Row(
        children: [
          NavigationRail(
            extended: true,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
            destinations: const [
              NavigationRailDestination(
                icon: Tooltip(
                  waitDuration: Duration(milliseconds: 600),
                  showDuration: Duration(seconds: 4),
                  message:
                      'Καταγραφή νέας κλήσης τεχνικής υποστήριξης\nΚύρια οθόνη – πατήστε εδώ όταν χτυπά τηλέφωνο',
                  child: Icon(Icons.phone_in_talk),
                ),
                label: Text('Κλήσεις'),
              ),
              NavigationRailDestination(
                icon: Tooltip(
                  waitDuration: Duration(milliseconds: 600),
                  showDuration: Duration(seconds: 4),
                  message:
                      'Προβλήματα που χρήζουν παρακολούθησης\nΑνοιχτές εργασίες & υπενθυμίσεις',
                  child: Icon(Icons.task_alt),
                ),
                label: Text('Εκκρεμότητες'),
              ),
              NavigationRailDestination(
                icon: Tooltip(
                  waitDuration: Duration(milliseconds: 600),
                  showDuration: Duration(seconds: 4),
                  message:
                      'Διαχείριση χρηστών και εξοπλισμού\nΠροσθήκη / διόρθωση ονομάτων, τμημάτων, υπολογιστών',
                  child: Icon(Icons.contacts),
                ),
                label: Text('Κατάλογος'),
              ),
              NavigationRailDestination(
                icon: Tooltip(
                  waitDuration: Duration(milliseconds: 600),
                  showDuration: Duration(seconds: 4),
                  message:
                      'Προηγούμενες κλήσεις & αναζήτηση\nΕμφάνιση, τροποποίηση ή διαγραφή παλιών καταγραφών',
                  child: Icon(Icons.history),
                ),
                label: Text('Ιστορικό'),
              ),
              NavigationRailDestination(
                icon: Tooltip(
                  waitDuration: Duration(milliseconds: 600),
                  showDuration: Duration(seconds: 4),
                  message:
                      'Εργαλεία διαχείρισης & εποπτείας βάσης\nΑντίγραφα ασφαλείας, εγγραφές, προβολή πινάκων (για προχωρημένους χρήστες)',
                  child: Icon(Icons.storage),
                ),
                label: Text('Βάση Δεδομένων'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: Column(
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
                if (_selectedIndex != 2)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.databaseResult.isSuccess
                              ? (widget.databaseResult.message ??
                                  'Η σύνδεση με τη βάση δεδομένων πέτυχε.')
                              : (widget.databaseResult.message ??
                                  'Άγνωστο σφάλμα με τη βάση δεδομένων.'),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: widget.databaseResult.isSuccess
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                              ),
                        ),
                        if (widget.databaseResult.details != null &&
                            !widget.databaseResult.isSuccess) ...[
                          const SizedBox(height: 4),
                          Tooltip(
                            message: widget.databaseResult.details!,
                            child: Text(
                              widget.databaseResult.details!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
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
                Expanded(
                  child: switch (_selectedIndex) {
                    2 => const DirectoryScreen(),
                    4 => const DatabaseBrowserScreen(),
                    _ => const CallsScreen(),
                  },
                ),
                if (_pendingRestartDueToPathChange)
                  Material(
                    color: Colors.grey.shade800,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: TextStyle(
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
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer,
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
            ),
          ),
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
        onLog: (msg, [level]) =>
            ref.read(importLogProvider.notifier).addLog(msg, level ?? ImportLogLevel.info),
      );
      if (!result.success && result.errorMessage != null) {
        messenger.showSnackBar(
          SnackBar(content: Text(result.errorMessage!)),
        );
      } else if (result.success && (result.usersInserted > 0 || result.equipmentInserted > 0)) {
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
      messenger.showSnackBar(
        SnackBar(content: Text('Σφάλμα: $e')),
      );
    }
  }
}
