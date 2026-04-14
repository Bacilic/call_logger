import 'package:flutter/material.dart';

import '../../../audit/services/audit_entity_preview_resolver.dart';
import 'audit_preview_column.dart';

class TaskPreviewWidget extends StatelessWidget {
  const TaskPreviewWidget({
    super.key,
    required this.preview,
    this.showTitle = true,
  });

  final AuditEntityPreview preview;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    return AuditPreviewColumn(preview: preview, showTitle: showTitle);
  }
}
