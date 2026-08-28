import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/servers_provider.dart';
import '../../../../core/services/server_sessions/printer_rpc_policy.dart';
import '../../../../core/services/server_sessions/server_session_models.dart';
import '../../../../core/services/server_sessions/smb1_client_status.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../../../core/widgets/section_card.dart';

/// Κάρτα «Κατάσταση αυτού του υπολογιστή» στην οθόνη Διακομιστές.
///
/// Μαζεύει τις **τοπικές προϋποθέσεις** επικοινωνίας με τους παλιούς
/// διακομιστές: ό,τι λείπει από αυτόν εδώ τον υπολογιστή ονομάζεται και, όπου
/// γίνεται, διορθώνεται επί τόπου. Στέκεται εδώ και όχι σε κρυφό διαγνωστικό
/// γιατί, όταν λείπει κάτι, ο διακομιστής απλώς «δεν απαντά» — και η αιτία δεν
/// είναι μαντέψιμη από το μήνυμα σφάλματος.
class ThisComputerStatusCard extends ConsumerWidget {
  const ThisComputerStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      icon: Icons.computer_outlined,
      title: 'Κατάσταση αυτού του υπολογιστή',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _Smb1Section(),
          Divider(height: 24),
          _PrinterRpcSection(),
          Divider(height: 24),
          _LimitedViewHintSwitch(),
        ],
      ),
    );
  }
}

/// Κοινή γραμμή κατάστασης: εικονίδιο ανάλογα με τη σοβαρότητα και κείμενο.
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.text,
    required this.problem,
  });

  final IconData icon;
  final String text;
  final bool problem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: problem ? theme.colorScheme.error : theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _Checking extends StatelessWidget {
  const _Checking();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('Γίνεται έλεγχος…'),
        ],
      ),
    );
  }
}

// --- SMB 1.0/CIFS ----------------------------------------------------------

class _Smb1Section extends ConsumerWidget {
  const _Smb1Section();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(smb1ClientStatusProvider);

    return async.when(
      loading: () => const _Checking(),
      error: (e, _) => Text('Αποτυχία ελέγχου SMB1: $e'),
      data: (status) {
        final problem = status.isProblem;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusLine(
              icon: switch (status) {
                Smb1ClientStatus.running => Icons.check_circle_outline,
                Smb1ClientStatus.unknown => Icons.help_outline,
                _ => Icons.warning_amber_outlined,
              },
              text: status.label,
              problem: problem,
            ),
            if (problem) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text(
                    'Άνοιγμα «Δυνατότητες των Windows» (SMB 1.0/CIFS)',
                  ),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final opened = await openWindowsOptionalFeatures();
                    if (!context.mounted) return;
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          opened
                              ? 'Άνοιξε το παράθυρο δυνατοτήτων. Μετά την '
                                    'αλλαγή χρειάζεται επανεκκίνηση του '
                                    'υπολογιστή.'
                              : 'Δεν ήταν δυνατό το άνοιγμα του παραθύρου '
                                    'δυνατοτήτων των Windows.',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// --- Πολιτική RPC εκτυπωτών ------------------------------------------------

class _PrinterRpcSection extends ConsumerWidget {
  const _PrinterRpcSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(printerRpcPolicyProvider);

    return async.when(
      loading: () => const _Checking(),
      error: (e, _) => Text('Αποτυχία ελέγχου ρύθμισης RPC: $e'),
      data: (state) {
        final status = state.status;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusLine(
              icon: switch (status) {
                PrinterRpcPolicyStatus.enabled => Icons.check_circle_outline,
                PrinterRpcPolicyStatus.unknown => Icons.help_outline,
                _ => Icons.warning_amber_outlined,
              },
              text: state.label,
              problem: status.isProblem,
            ),
            if (status != PrinterRpcPolicyStatus.unknown) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (status.isProblem)
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.print_outlined, size: 18),
                      label: const Text(
                        'Ενεργοποίηση πλήρους προβολής εκτυπωτών',
                      ),
                      onPressed: () =>
                          _showDialog(context, ref, restore: false),
                    ),
                  // Η επαναφορά προσφέρεται μόνο όταν υπάρχει κάτι να ξηλωθεί —
                  // στη μισοπερασμένη ρύθμιση ο χειριστής μπορεί να θέλει είτε
                  // να την ολοκληρώσει είτε να την καθαρίσει.
                  if (status != PrinterRpcPolicyStatus.disabled)
                    TextButton.icon(
                      icon: const Icon(Icons.settings_backup_restore, size: 18),
                      label: const Text('Επαναφορά προεπιλογών των Windows'),
                      onPressed: () => _showDialog(context, ref, restore: true),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _showDialog(
    BuildContext context,
    WidgetRef ref, {
    required bool restore,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _PrinterRpcPolicyDialog(restore: restore),
    );
    if (changed ?? false) ref.invalidate(printerRpcPolicyProvider);
  }
}

/// Το παράθυρο που εξηγεί την αλλαγή και την εκτελεί — και προς τις δύο
/// κατευθύνσεις.
///
/// Ένα παράθυρο για τα δύο και όχι δύο σχεδόν ίδια: η ενεργοποίηση και η
/// επαναφορά διαφέρουν στα λόγια και στην εντολή, σε τίποτε άλλο.
///
/// Επιστρέφει `true` όταν το μητρώο άλλαξε πραγματικά, ώστε ο καλών να
/// ξαναρωτήσει — η αλλαγή πιάνει αμέσως, χωρίς καμία επανεκκίνηση.
class _PrinterRpcPolicyDialog extends ConsumerStatefulWidget {
  const _PrinterRpcPolicyDialog({required this.restore});

  /// `true`: ξηλώνει τη ρύθμιση. `false`: την περνά.
  final bool restore;

  @override
  ConsumerState<_PrinterRpcPolicyDialog> createState() =>
      _PrinterRpcPolicyDialogState();
}

class _PrinterRpcPolicyDialogState
    extends ConsumerState<_PrinterRpcPolicyDialog> {
  bool _working = false;
  String? _error;

  bool get _restore => widget.restore;

  String get _lead =>
      _restore ? 'Η επαναφορά δεν ολοκληρώθηκε' : 'Η ρύθμιση δεν πέρασε';

  Future<void> _apply() async {
    setState(() {
      _working = true;
      _error = null;
    });

    final result = _restore
        ? await PrinterRpcPolicy.restoreDefaultsElevated()
        : await PrinterRpcPolicy.applyElevated();
    if (!mounted) return;

    switch (result.outcome) {
      case PrinterRpcPolicyApplyOutcome.applied:
        Navigator.of(context).pop(true);
      case PrinterRpcPolicyApplyOutcome.cancelled:
        setState(() {
          _working = false;
          _error =
              '$_lead: τα Windows δεν έδωσαν δικαιώματα διαχειριστή. '
              'Χρειάζεται λογαριασμός διαχειριστή αυτού του υπολογιστή.';
        });
      case PrinterRpcPolicyApplyOutcome.failed:
        setState(() {
          _working = false;
          _error = result.detail ?? '$_lead.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableDialogShell(
      title: Text(
        _restore
            ? 'Επαναφορά προεπιλογών των Windows'
            : 'Πλήρης προβολή εκτυπωτών',
      ),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _restore
                      ? 'Ο υπολογιστής γυρίζει στη συμπεριφορά που έχουν τα '
                            'Windows 11 από μόνα τους. Η ειδική ρύθμιση για '
                            'τους παλιούς διακομιστές εκτυπώσεων ξηλώνεται και '
                            'το σύστημα ξαναλειτουργεί σαν να μην είχε '
                            'περαστεί ποτέ.'
                      : 'Οι διακομιστές του 2003 απαντούν για τους εκτυπωτές '
                            'τους μόνο με τον παλιό τρόπο επικοινωνίας, τον '
                            'οποίο τα Windows 11 δεν χρησιμοποιούν από μόνα '
                            'τους. Η ρύθμιση αυτή τα επαναφέρει σε αυτόν — και '
                            'τότε βλέπεις ουρές, εργασίες και ενέργειες αντί '
                            'για σκέτα ονόματα εκτυπωτών.',
                ),
                const SizedBox(height: 12),
                Text(
                  'Τι αλλάζει στον υπολογιστή σου',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _restore
                      ? '• Η προβολή εκτυπωτών ξαναγίνεται περιορισμένη: θα '
                            'βλέπεις ποιοι εκτυπωτές υπάρχουν, αλλά όχι τι '
                            'περιμένει στις ουρές τους, και οι ενέργειες '
                            'σταματούν να είναι διαθέσιμες.\n'
                            '• Ο υπολογιστής ξαναρχίζει να επαληθεύει την '
                            'ταυτότητα των διακομιστών εκτυπώσεων με τους '
                            'οποίους μιλά.\n'
                            '• Τίποτα άλλο δεν πειράζεται: σβήνονται μόνο οι '
                            'δύο τιμές που είχε βάλει η εφαρμογή.\n'
                            '• Μπορείς να την ξαναπεράσεις όποτε θέλεις, από '
                            'το ίδιο σημείο.'
                      : '• Οι ερωτήσεις προς διακομιστές εκτυπώσεων ταξιδεύουν '
                            'ξανά από το παλιό κανάλι.\n'
                            '• Ο υπολογιστής σταματά να επαληθεύει την '
                            'ταυτότητα του διακομιστή εκτυπώσεων με τον οποίο '
                            'μιλά. Αν κάποιος κακόβουλος στήσει ψεύτικο '
                            'διακομιστή εκτυπώσεων στο δίκτυο, ο υπολογιστής '
                            'δεν θα το καταλάβει.\n'
                            '• Αφορά μόνο συνδέσεις που ξεκινά ο ίδιος ο '
                            'υπολογιστής προς τα έξω. Καμία πόρτα δεν ανοίγει '
                            'προς τα μέσα.\n'
                            '• Αναιρείται πλήρως, με το κουμπί «Επαναφορά '
                            'προεπιλογών των Windows» δίπλα σε αυτό.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Χρειάζονται δικαιώματα διαχειριστή: τα Windows θα ζητήσουν '
                  'άδεια. Δεν απαιτείται καμία επανεκκίνηση — η αλλαγή πιάνει '
                  'αμέσως.',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 18,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _working ? null : () => Navigator.of(context).pop(false),
            child: const Text('Άκυρο'),
          ),
          FilledButton.icon(
            icon: _working
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _restore
                        ? Icons.settings_backup_restore
                        : Icons.shield_outlined,
                    size: 18,
                  ),
            label: Text(
              _working ? 'Αναμονή…' : (_restore ? 'Επαναφορά' : 'Ενεργοποίηση'),
            ),
            onPressed: _working ? null : _apply,
          ),
        ],
      ),
    );
  }
}

// --- Υπόδειξη στον διάλογο εκτυπωτών ---------------------------------------

class _LimitedViewHintSwitch extends ConsumerWidget {
  const _LimitedViewHintSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(printersLimitedViewHintProvider);

    return async.when(
      loading: () => const _Checking(),
      error: (e, _) => Text('Αποτυχία ανάγνωσης ρύθμισης: $e'),
      data: (enabled) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Υπόδειξη στους εκτυπωτές'),
        subtitle: const Text(
          'Όταν η προβολή εκτυπωτών είναι περιορισμένη, να λέει πού '
          'ενεργοποιείται η πλήρης.',
        ),
        value: enabled,
        onChanged: (value) async {
          await SettingsService().windowUi.setPrintersLimitedViewHint(value);
          ref.invalidate(printersLimitedViewHintProvider);
        },
      ),
    );
  }
}
