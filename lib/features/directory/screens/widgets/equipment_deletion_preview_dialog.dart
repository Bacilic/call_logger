import 'package:flutter/material.dart';

import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../services/equipment_deletion_summary.dart';
import '../../services/equipment_deletion_zones.dart';

/// Τι αποφάσισε ο χρήστης **και** ποιον εξοπλισμό άφησε στη λίστα.
typedef EquipmentDeletionPreviewResult = ({
  bool confirmed,
  List<int> keptEquipmentIds,
});

/// Ύψος της κυλιόμενης ζώνης όταν ο εξοπλισμός είναι πολύς.
const double _kMaxListHeight = 380;

/// Προεπισκόπηση πριν τη μαζική διαγραφή εξοπλισμού.
Future<EquipmentDeletionPreviewResult?> showEquipmentDeletionPreviewDialog({
  required BuildContext context,
  required List<EquipmentDeletionSummary> summaries,
}) {
  return showDialog<EquipmentDeletionPreviewResult>(
    context: context,
    builder: (ctx) =>
        _EquipmentDeletionPreviewDialog(initialSummaries: summaries),
  );
}

class _EquipmentDeletionPreviewDialog extends StatefulWidget {
  const _EquipmentDeletionPreviewDialog({required this.initialSummaries});

  final List<EquipmentDeletionSummary> initialSummaries;

  @override
  State<_EquipmentDeletionPreviewDialog> createState() =>
      _EquipmentDeletionPreviewDialogState();
}

class _EquipmentDeletionPreviewDialogState
    extends State<_EquipmentDeletionPreviewDialog> {
  late List<EquipmentDeletionSummary> _kept;

  @override
  void initState() {
    super.initState();
    _kept = List<EquipmentDeletionSummary>.from(widget.initialSummaries);
  }

  void _remove(int equipmentId) {
    setState(() {
      _kept = _kept.where((s) => s.equipmentId != equipmentId).toList();
    });
  }

  void _pop(bool confirmed) {
    Navigator.of(context).pop((
      confirmed: confirmed,
      keptEquipmentIds: [for (final s in _kept) s.equipmentId],
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Σύνοψη και ζώνες ξαναϋπολογίζονται σε κάθε αφαίρεση: σύνοψη που δεν
    // ακολουθεί τη λίστα λέει ψέματα τη στιγμή που αποφασίζεται η διαγραφή.
    final zones = EquipmentDeletionZones.from(_kept);
    final rows = buildEquipmentDeletionPreviewRows(_kept);
    final canRemove = _kept.length > 1;
    final totals = EquipmentDeletionTotals.fromSummaries(_kept);

    return DraggableDialogShell(
      title: const Text('Διαγραφή εξοπλισμού'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Με έναν εξοπλισμό, ή όταν κανείς δεν αφήνει ίχνη, η σύνοψη θα
              // επαναλάμβανε ό,τι λέει ήδη η λίστα από κάτω.
              if (_kept.length > 1 && zones.withTraces.isNotEmpty) ...[
                _Headline(
                  text: totals.headline(
                    initiallySelected: widget.initialSummaries.length,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: _kMaxListHeight),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _PreviewRow(
                      row: rows[index],
                      onRemove: canRemove ? _remove : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _pop(false),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: _kept.isEmpty ? null : () => _pop(true),
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
  }
}

/// Μία γραμμή: επικεφαλίδα ζώνης, κάρτα εξοπλισμού, ή η ομάδα των άιχνων.
sealed class EquipmentDeletionPreviewRow {
  const EquipmentDeletionPreviewRow();
}

class EquipmentZoneHeaderRow extends EquipmentDeletionPreviewRow {
  const EquipmentZoneHeaderRow(this.title);
  final String title;
}

class EquipmentCardRow extends EquipmentDeletionPreviewRow {
  const EquipmentCardRow(this.summary);
  final EquipmentDeletionSummary summary;
}

class TracelessEquipmentRow extends EquipmentDeletionPreviewRow {
  const TracelessEquipmentRow({required this.title, required this.labels});
  final String title;
  final List<String> labels;
}

/// Ξεδιπλώνει τις ζώνες σε επίπεδη λίστα για την τεμπέλικη λίστα.
List<EquipmentDeletionPreviewRow> buildEquipmentDeletionPreviewRows(
  List<EquipmentDeletionSummary> summaries,
) {
  final zones = EquipmentDeletionZones.from(summaries);
  final showHeaders = zones.showsZoneHeaders;
  final rows = <EquipmentDeletionPreviewRow>[];

  if (zones.withTraces.isNotEmpty) {
    if (showHeaders) rows.add(EquipmentZoneHeaderRow(zones.withTracesHeader));
    rows.addAll(zones.withTraces.map(EquipmentCardRow.new));
  }
  final tracelessHeader = zones.withoutTracesHeader;
  if (tracelessHeader != null) {
    // Όταν ΚΑΝΕΝΑΣ δεν αφήνει ίχνη, η ονομαστική λίστα είναι η μόνη
    // πληροφορία που έχει ο χρήστης — δεν συμπτύσσεται.
    if (zones.withTraces.isEmpty) {
      rows.addAll(zones.withoutTraces.map(EquipmentCardRow.new));
    } else {
      rows.add(
        TracelessEquipmentRow(
          title: tracelessHeader,
          labels: [for (final s in zones.withoutTraces) s.titleLine],
        ),
      );
    }
  }
  return rows;
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.row, this.onRemove});

  final EquipmentDeletionPreviewRow row;
  final void Function(int equipmentId)? onRemove;

  @override
  Widget build(BuildContext context) {
    return switch (row) {
      EquipmentZoneHeaderRow(:final title) => _ZoneHeader(title: title),
      EquipmentCardRow(:final summary) => _EquipmentCard(
        summary: summary,
        onRemove: onRemove,
      ),
      TracelessEquipmentRow(:final title, :final labels) => _TracelessGroup(
        title: title,
        labels: labels,
      ),
    };
  }
}

class _ZoneHeader extends StatelessWidget {
  const _ZoneHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EquipmentCard extends StatelessWidget {
  const _EquipmentCard({required this.summary, this.onRemove});

  final EquipmentDeletionSummary summary;
  final void Function(int equipmentId)? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = summary.buildTraceLines();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    summary.titleLine,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    tooltip:
                        'Αφαίρεση από τη λίστα — ο εξοπλισμός δεν διαγράφεται',
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: () => onRemove!(summary.equipmentId),
                  ),
              ],
            ),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(line, style: theme.textTheme.bodyMedium),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ο εξοπλισμός χωρίς ίχνη χρήσης, σε μία πτυσσόμενη γραμμή.
///
/// Μία γραμμή ανά εξοπλισμό και όχι ενιαίο κείμενο με κόμματα: εδώ κάθε
/// στοιχείο είναι «κωδικός → κάτοχος», που δεν διαβάζεται σε παράθεση.
class _TracelessGroup extends StatelessWidget {
  const _TracelessGroup({required this.title, required this.labels});

  final String title;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        dense: true,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          for (final label in labels)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.55,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
