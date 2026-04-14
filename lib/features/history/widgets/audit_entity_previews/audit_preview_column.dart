import 'package:flutter/material.dart';

import '../../../audit/services/audit_entity_preview_resolver.dart';

/// Στήλη γραμμών προεπισκόπησης· προαιρετικός τίτλος (απόκρυψη όταν διπλότυπο με summary audit).
class AuditPreviewColumn extends StatelessWidget {
  const AuditPreviewColumn({
    super.key,
    required this.preview,
    this.showTitle = true,
  });

  final AuditEntityPreview preview;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = preview.title.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle && t.isNotEmpty) ...[
          Text(t, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
        ],
        ...preview.lines.map(
          (l) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(l, style: theme.textTheme.bodySmall),
          ),
        ),
      ],
    );
  }
}
