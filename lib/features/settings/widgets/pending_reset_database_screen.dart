import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_init_result.dart';
import '../../../core/database/database_path_pick_flow.dart';
import '../../../core/services/application_reset_service.dart';
import '../../../features/directory/screens/widgets/department_palette_store.dart';
import 'create_new_database_dialog.dart';

/// Οθόνη μετά την επαναφορά: επιλογή/δημιουργία βάσης ή αναίρεση (rollback).
class PendingResetDatabaseScreen extends ConsumerStatefulWidget {
  const PendingResetDatabaseScreen({
    super.key,
    required this.onLifecycleChanged,
  });

  final Future<void> Function() onLifecycleChanged;

  @override
  ConsumerState<PendingResetDatabaseScreen> createState() =>
      _PendingResetDatabaseScreenState();
}

class _PendingResetDatabaseScreenState
    extends ConsumerState<PendingResetDatabaseScreen> {
  bool _busy = false;

  Future<void> _rollbackAndExit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await ApplicationResetService.instance.rollbackPendingReset();
      await DepartmentPaletteStore.instance.reloadFromPreferences();
      if (!mounted) return;
      ApplicationResetService.instance.invalidateAfterResetLifecycle(ref);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Δεν βρέθηκε αποθηκευμένη κατάσταση για αναίρεση.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _findDatabase() async {
    if (_busy) return;
    final picked = await pickDatabasePathWithSystemPicker();
    if (!mounted) return;
    if (picked == null || picked.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      final outcome = await setAndVerifyDatabasePath(picked.trim());
      if (!mounted) return;
      if (!outcome.ok) {
        await _showDbError(outcome.runner.result);
        return;
      }
      await widget.onLifecycleChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createNewDatabase() async {
    if (_busy) return;
    final picked = await pickNewDatabaseSavePath();
    if (!mounted) return;
    if (picked == null) return;

    final validationError = validateNewDatabaseSavePath(picked);
    if (validationError != null) {
      await showNewDatabasePathValidationDialog(context, validationError);
      return;
    }

    final norm = picked;
    if (await File(norm).exists()) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Υπάρχον αρχείο στον στόχο'),
          content: Text(
            'Στη διαδρομή:\n\n$norm\n\nυπάρχει ήδη αρχείο. '
            'Δεν διαγράφουμε υπάρχοντα αρχεία· μετακινήστε ή μετονομάστε το χειροκίνητα.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Εντάξει'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await DatabaseHelper.instance.createNewDatabaseFile(norm);
      final outcome = await setAndVerifyDatabasePath(norm);
      if (!mounted) return;
      if (!outcome.ok) {
        await _showDbError(outcome.runner.result);
        return;
      }
      await widget.onLifecycleChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Αποτυχία δημιουργίας νέας βάσης: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showDbError(DatabaseInitResult result) async {
    final msg = result.message ?? 'Η βάση δεν πέρασε τον έλεγχο.';
    final det = result.details?.trim();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Η βάση δεν είναι έγκυρη'),
        content: SingleChildScrollView(
          child: Text(det != null && det.isNotEmpty ? '$msg\n\n$det' : msg),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Εντάξει'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.restart_alt,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Ξεκίνα από την αρχή',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Η εφαρμογή αποσυνδέθηκε από την προηγούμενη βάση. '
                    'Επιλέξτε υπάρχουσα βάση ή δημιουργήστε νέα κενή. '
                    'Αν ακυρώσετε, θα επανέλθουν οι προηγούμενες ρυθμίσεις.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
                  ),
                  const SizedBox(height: 28),
                  if (_busy)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    FilledButton.icon(
                      onPressed: _findDatabase,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('Εύρεση βάσης'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: _createNewDatabase,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Δημιουργία νέας βάσης'),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: _rollbackAndExit,
                      child: const Text('Ακύρωση — επαναφορά ρυθμίσεων'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
