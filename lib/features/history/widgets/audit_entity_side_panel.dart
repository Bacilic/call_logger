import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/audit_service.dart';
import '../../audit/models/audit_log_model.dart';
import '../../audit/providers/audit_providers.dart';
import '../../audit/services/audit_entity_preview_resolver.dart';
import '../../audit/services/audit_formatter_service.dart';
import 'audit_before_after_section.dart';
import 'audit_entity_previews/audit_entity_preview_body.dart';

/// Δεξιό panel: λεπτομέρειες εγγραφής audit + πεδία οντότητας (ενιαία επιλογή κειμένου).
class AuditEntitySidePanel extends ConsumerWidget {
  const AuditEntitySidePanel({
    super.key,
    required this.entry,
  });

  final AuditLogModel entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    const formatter = AuditFormatterService();
    final isMaintenance =
        entry.entityType?.trim() == AuditEntityTypes.maintenance;

    return Material(
      elevation: 1,
      color: theme.colorScheme.surfaceContainerLow,
      child: SizedBox(
        width: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Λεπτομέρειες',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Κλείσιμο πλαισίου',
                    onPressed: () => ref
                        .read(auditSidePanelOpenProvider.notifier)
                        .setOpen(false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SelectionArea(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Text(
                      formatter.summaryLine(entry),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    if (entry.hasMeaningfulPerformingUser) ...[
                      Text(
                        'Χρήστης: ${entry.userPerforming!.trim()}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (entry.timestamp != null)
                      Text(
                        'Ώρα: ${formatter.formatAuditTimestamp(entry.timestamp)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (entry.details != null &&
                        entry.details!.trim().isNotEmpty &&
                        !entry.isTechnicalTableDetailsOnly) ...[
                      const SizedBox(height: 8),
                      Text(
                        entry.details!.trim(),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (entry.hasAnyDeltaJson) ...[
                      const SizedBox(height: 12),
                      AuditBeforeAfterSection(entry: entry),
                    ],
                    const SizedBox(height: 16),
                    _buildPreviewBlock(
                      context,
                      ref,
                      isMaintenance,
                      formatter,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewBlock(
    BuildContext context,
    WidgetRef ref,
    bool isMaintenance,
    AuditFormatterService formatter,
  ) {
    final theme = Theme.of(context);
    if (isMaintenance) {
      return AuditEntityPreviewBody(
        entityType: AuditEntityTypes.maintenance,
        showPreviewTitle: false,
        preview: AuditEntityPreview(
          title: entry.action ?? 'Συντήρηση βάσης',
          lines: [
            if (entry.details != null && entry.details!.trim().isNotEmpty)
              entry.details!.trim(),
            if (entry.timestamp != null && entry.timestamp!.trim().isNotEmpty)
              'Χρονική σήμανση: ${formatter.formatAuditTimestamp(entry.timestamp)}',
            if ((entry.details == null || entry.details!.trim().isEmpty) &&
                (entry.timestamp == null || entry.timestamp!.trim().isEmpty))
              'Δεν υπάρχει συγκεκριμένη οντότητα.',
          ],
        ),
      );
    }
    if (entry.entityId == null ||
        entry.entityType == null ||
        entry.entityType!.trim().isEmpty) {
      return Text(
        'Δεν συνδέεται με συγκεκριμένη οντότητα (π.χ. μαζική ενέργεια).',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    final type = entry.entityType!.trim();
    if (!AuditEntityPreviewResolver.supportsEntityType(type)) {
      return Text(
        'Δεν υπάρχει διαθέσιμη προεπισκόπηση για τον τύπο οντότητας "$type".',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final previewAsync = ref.watch(
      auditEntityPreviewProvider(
        (
          auditId: entry.id,
          entityType: entry.entityType,
          entityId: entry.entityId,
        ),
      ),
    );

    return previewAsync.when(
      data: (data) {
        if (data == null) {
          return Text(
            'Η οντότητα δεν βρέθηκε στη βάση. Πιθανόν έχει διαγραφεί ή είναι μη διαθέσιμη στην τρέχουσα προβολή.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }
        return AuditEntityPreviewBody(
          entityType: entry.entityType,
          showPreviewTitle: false,
          preview: data,
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => Text(
        'Σφάλμα φόρτωσης: $e',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}
