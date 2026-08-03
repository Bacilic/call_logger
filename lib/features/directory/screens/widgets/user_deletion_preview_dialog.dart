import 'package:flutter/material.dart';

import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../services/user_deletion_messages.dart';
import '../../services/user_deletion_zones.dart';

/// Τι αποφάσισε ο χρήστης **και** ποιους υπαλλήλους άφησε στη λίστα.
typedef UserDeletionPreviewResult = ({bool confirmed, List<int> keptUserIds});

/// Ύψος της κυλιόμενης ζώνης όταν οι υπάλληλοι είναι πολλοί.
const double _kMaxListHeight = 380;

/// Προεπισκόπηση πριν τη μαζική διαγραφή υπαλλήλων.
///
/// Ίδια δομή με τη διαγραφή τμημάτων: σταθερή σύνοψη, ζώνες κατά το τι θα
/// ζητηθεί, και κουμπί αφαίρεσης ανά κάρτα.
Future<UserDeletionPreviewResult?> showUserDeletionPreviewDialog({
  required BuildContext context,
  required List<UserDeletionInventory> inventories,
}) {
  return showDialog<UserDeletionPreviewResult>(
    context: context,
    builder: (ctx) =>
        _UserDeletionPreviewDialog(initialInventories: inventories),
  );
}

class _UserDeletionPreviewDialog extends StatefulWidget {
  const _UserDeletionPreviewDialog({required this.initialInventories});

  final List<UserDeletionInventory> initialInventories;

  @override
  State<_UserDeletionPreviewDialog> createState() =>
      _UserDeletionPreviewDialogState();
}

class _UserDeletionPreviewDialogState
    extends State<_UserDeletionPreviewDialog> {
  late List<UserDeletionInventory> _kept;

  @override
  void initState() {
    super.initState();
    _kept = List<UserDeletionInventory>.from(widget.initialInventories);
  }

  void _remove(int userId) {
    setState(() {
      _kept = _kept.where((i) => i.userId != userId).toList();
    });
  }

  void _pop(bool confirmed) {
    Navigator.of(context).pop((
      confirmed: confirmed,
      keptUserIds: [for (final i in _kept) i.userId],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Σύνοψη και ζώνες ξαναϋπολογίζονται σε κάθε αφαίρεση: σύνοψη που δεν
    // ακολουθεί τη λίστα λέει ψέματα τη στιγμή που αποφασίζεται η διαγραφή.
    final zones = UserDeletionZones.from(_kept);
    final rows = buildUserDeletionPreviewRows(_kept);
    final canRemove = _kept.length > 1;
    final hasAnyAssets = zones.withAssets.isNotEmpty;
    final pendingNotice = userDeletionPendingQuestionsNotice(
      zones.totalAssetCount,
    );
    final headline = userDeletionHeadline(
      userCount: _kept.length,
      exclusivePhoneCount: _sumPhones(_kept),
      exclusiveEquipmentCount: _sumEquipment(_kept),
      initiallySelected: widget.initialInventories.length,
    );

    return DraggableDialogShell(
      title: Text(userDeletionConfirmTitle(_kept.length)),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Με έναν υπάλληλο, ή όταν κανείς δεν έχει στοιχεία, η σύνοψη θα
              // επαναλάμβανε ό,τι λέει ήδη η λίστα από κάτω.
              if (_kept.length > 1 && hasAnyAssets) ...[
                _Headline(text: headline),
                const SizedBox(height: 10),
              ],
              if (pendingNotice != null) ...[
                _PendingNotice(text: pendingNotice),
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
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
  }
}

int _sumPhones(List<UserDeletionInventory> list) {
  var total = 0;
  for (final i in list) {
    total += i.exclusivePhoneCount;
  }
  return total;
}

int _sumEquipment(List<UserDeletionInventory> list) {
  var total = 0;
  for (final i in list) {
    total += i.exclusiveEquipmentCount;
  }
  return total;
}

/// Μία γραμμή: επικεφαλίδα ζώνης, κάρτα υπαλλήλου, ή η ομάδα των άδειων.
sealed class UserDeletionPreviewRow {
  const UserDeletionPreviewRow();
}

class UserZoneHeaderRow extends UserDeletionPreviewRow {
  const UserZoneHeaderRow(this.title);
  final String title;
}

class UserCardRow extends UserDeletionPreviewRow {
  const UserCardRow(this.inventory);
  final UserDeletionInventory inventory;
}

class EmptyUsersRow extends UserDeletionPreviewRow {
  const EmptyUsersRow({required this.title, required this.labels});
  final String title;
  final List<String> labels;
}

/// Ξεδιπλώνει τις ζώνες σε επίπεδη λίστα για την τεμπέλικη λίστα.
List<UserDeletionPreviewRow> buildUserDeletionPreviewRows(
  List<UserDeletionInventory> inventories,
) {
  final zones = UserDeletionZones.from(inventories);
  final showHeaders = zones.showsZoneHeaders;
  final rows = <UserDeletionPreviewRow>[];

  if (zones.withAssets.isNotEmpty) {
    if (showHeaders) rows.add(UserZoneHeaderRow(zones.withAssetsHeader));
    rows.addAll(zones.withAssets.map(UserCardRow.new));
  }
  final emptyHeader = zones.emptyHeader;
  if (emptyHeader != null) {
    // Όταν ΟΛΟΙ είναι χωρίς στοιχεία, η ονομαστική λίστα είναι η μόνη
    // πληροφορία που έχει ο χρήστης — δεν συμπτύσσεται.
    if (zones.withAssets.isEmpty) {
      rows.addAll(zones.empty.map(UserCardRow.new));
    } else {
      rows.add(
        EmptyUsersRow(
          title: emptyHeader,
          labels: [for (final inv in zones.empty) inv.displayLabel],
        ),
      );
    }
  }
  return rows;
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.row, this.onRemove});

  final UserDeletionPreviewRow row;
  final void Function(int userId)? onRemove;

  @override
  Widget build(BuildContext context) {
    return switch (row) {
      UserZoneHeaderRow(:final title) => _ZoneHeader(title: title),
      UserCardRow(:final inventory) => _UserCard(
        inventory: inventory,
        onRemove: onRemove,
      ),
      EmptyUsersRow(:final title, :final labels) => _EmptyUsersGroup(
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

class _UserCard extends StatelessWidget {
  const _UserCard({required this.inventory, this.onRemove});

  final UserDeletionInventory inventory;
  final void Function(int userId)? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = inventory.buildSummaryLines();

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
                    inventory.displayLabel,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    tooltip:
                        'Αφαίρεση από τη λίστα — ο υπάλληλος δεν διαγράφεται',
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: () => onRemove!(inventory.userId),
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

/// Οι υπάλληλοι χωρίς προσωπικά στοιχεία σε μία πτυσσόμενη γραμμή.
class _EmptyUsersGroup extends StatelessWidget {
  const _EmptyUsersGroup({required this.title, required this.labels});

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
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              labels.join(', '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
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

class _PendingNotice extends StatelessWidget {
  const _PendingNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}
