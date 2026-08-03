// Η προεπισκόπηση μιας καθολικής απόφασης: κάθε στοιχείο σε δική του γραμμή με
// τι είναι, ποιανού είναι, από πού, και τι ιστορικό κρατά.
//
// Δείχνονται ΟΛΑ τα στοιχεία — μια κομμένη λίστα με «…και 2 ακόμα» κρύβει
// ακριβώς αυτά που ο χρήστης θέλει να ελέγξει πριν πει «ναι σε όλα».

import 'package:flutter/material.dart';

import '../../services/asset_disconnect_session.dart';

class AssetDisconnectBulkPreview extends StatelessWidget {
  const AssetDisconnectBulkPreview({
    super.key,
    required this.headline,
    required this.items,
    required this.histories,
    required this.showUndoReminder,
  });

  final String headline;
  final List<AssetDisconnectItem> items;
  final List<AssetHistoryLinks> histories;
  final bool showUndoReminder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(headline),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < items.length; i++)
                    _BulkPreviewRow(
                      item: items[i],
                      history: i < histories.length ? histories[i] : null,
                      showDivider: i < items.length - 1,
                    ),
                ],
              ),
            ),
            if (showUndoReminder) ...[
              const SizedBox(height: 10),
              Text(
                assetDisconnectUndoReminder,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BulkPreviewRow extends StatelessWidget {
  const _BulkPreviewRow({
    required this.item,
    required this.history,
    required this.showDivider,
  });

  final AssetDisconnectItem item;
  final AssetHistoryLinks? history;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final historyLabel = assetDisconnectHistoryLabel(history);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.isPhone ? Icons.phone_outlined : Icons.devices_other_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: item.value,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: ' · ${assetDisconnectItemOwnerLabel(item)}',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (historyLabel.isNotEmpty)
                    TextSpan(
                      text: ' · $historyLabel',
                      style: TextStyle(color: theme.colorScheme.tertiary),
                    ),
                ],
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
