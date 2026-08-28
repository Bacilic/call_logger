import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/equipment_server_context.dart';
import 'equipment_printers_dialog.dart';
import 'user_logoff_dialog.dart';

/// Εφεδρική κάρτα ενεργειών διακομιστή, για εξοπλισμό ΧΩΡΙΣ ιστορικό κλήσεων.
///
/// Οι ίδιες δύο ενέργειες ζουν ήδη στο μενού ⋮ της κάρτας «Ιστορικό
/// Εξοπλισμού». Όταν όμως εκείνη η κάρτα δεν έχει τι να δείξει — εξοπλισμός
/// εκτός καταλόγου, ή καταχωρημένος αλλά χωρίς καμία κλήση — ο χειριστής
/// έμενε χωρίς καμία πρόσβαση σε αυτές. Η κάρτα αυτή παίρνει τη θέση της.
///
/// **Ποτέ δεν συνυπάρχουν.** Ποια από τις δύο εμφανίζεται το αποφασίζει ένα
/// μόνο σημείο: `CallsLayoutEngine.showEquipmentActions`.
class EquipmentStationActionsCard extends ConsumerStatefulWidget {
  const EquipmentStationActionsCard({super.key, required this.equipmentCode});

  final String equipmentCode;

  @override
  ConsumerState<EquipmentStationActionsCard> createState() =>
      _EquipmentStationActionsCardState();
}

class _EquipmentStationActionsCardState
    extends ConsumerState<EquipmentStationActionsCard> {
  /// Το όνομα σταθμού (π.χ. `PC922`), όπως το βλέπει και η κάρτα
  /// απομακρυσμένης σύνδεσης. Κενό όσο δεν έχει απαντηθεί ή δεν προκύπτει.
  String _stationName = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveStation());
  }

  @override
  void didUpdateWidget(EquipmentStationActionsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.equipmentCode.trim() != widget.equipmentCode.trim()) {
      // Άλλος εξοπλισμός: το παλιό όνομα θα έλεγε ψέματα μέχρι την απάντηση.
      setState(() => _stationName = '');
      _resolveStation();
    }
  }

  /// Ρωτά την ΚΟΙΝΗ πηγή — την ίδια που χρησιμοποιούν και οι δύο διάλογοι —
  /// ώστε το όνομα που δείχνει η κάρτα να μην μπορεί να αποκλίνει από τον
  /// υπολογιστή στον οποίο θα ενεργήσουν.
  Future<void> _resolveStation() async {
    final code = widget.equipmentCode.trim();
    if (code.isEmpty) return;
    String station;
    try {
      final context = await resolveEquipmentServerContext(ref, code);
      station = context.stationName.trim();
    } catch (_) {
      // Το όνομα είναι διακριτική πληροφορία, όχι προϋπόθεση: αν δεν βρεθεί,
      // τα κουμπιά μένουν και ο διάλογος εξηγεί το πρόβλημα με ακρίβεια.
      station = '';
    }
    if (!mounted) return;
    setState(() => _stationName = station);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = widget.equipmentCode.trim();
    if (code.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Ενέργειες υπολογιστή',
                style: theme.textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.logout, size: 18),
              label: const Text(
                'Αποσύνδεση χρήστη…',
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              onPressed: () =>
                  showUserLogoffDialog(context, equipmentCode: code),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text(
                'Εκτυπωτές στον διακομιστή…',
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              onPressed: () =>
                  showEquipmentPrintersDialog(context, equipmentCode: code),
            ),
            if (_stationName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _stationName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
