import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/calls/provider/import_log_provider.dart';
import '../../features/calls/screens/calls_screen.dart';
import '../../features/calls/screens/widgets/import_console_widget.dart';
import '../services/import_service.dart';

/// Κύριο κέλυφος εφαρμογής: πλευρική πλοήγηση και περιοχή περιεχομένου.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({
    super.key,
    required this.databaseInitSuccess,
    required this.isLocalDevMode,
  });

  final bool databaseInitSuccess;
  final bool isLocalDevMode;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _onImportExcel,
        tooltip: 'Import Excel',
        child: const Icon(Icons.upload_file),
      ),
      body: Row(
        children: [
          NavigationRail(
            extended: true,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.phone_in_talk),
                label: Text('Κλήσεις'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.contacts),
                label: Text('Κατάλογος'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.task_alt),
                label: Text('Εκκρεμότητες'),
              ),
            ],
            selectedIndex: 0,
            onDestinationSelected: (_) {},
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    widget.databaseInitSuccess
                        ? 'Η σύνδεση με τη βάση δεδομένων πέτυχε.'
                        : 'Η σύνδεση με τη βάση δεδομένων απέτυχε.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: widget.databaseInitSuccess
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                  ),
                ),
                const Expanded(child: CallsScreen()),
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
        onLog: (msg) => ref.read(importLogProvider.notifier).addLog(msg),
      );
      if (!result.success && result.errorMessage != null) {
        messenger.showSnackBar(
          SnackBar(content: Text(result.errorMessage!)),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Σφάλμα: $e')),
      );
    }
  }
}
