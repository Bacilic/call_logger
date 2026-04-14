import 'package:flutter/material.dart';

import '../../../../core/services/audit_service.dart';
import '../../../audit/services/audit_entity_preview_resolver.dart';
import 'backup_preview_widget.dart';
import 'call_preview_widget.dart';
import 'equipment_preview_widget.dart';
import 'settings_preview_widget.dart';
import 'task_preview_widget.dart';
import 'user_preview_widget.dart';

/// Επιλογή κατάλληλου widget προεπισκόπησης ανά `entity_type`.
class AuditEntityPreviewBody extends StatelessWidget {
  const AuditEntityPreviewBody({
    super.key,
    required this.entityType,
    required this.preview,
    this.showPreviewTitle = true,
  });

  final String? entityType;
  final AuditEntityPreview preview;

  /// Στο side panel audit: false — ο τίτλος καλύπτεται ήδη από το `summaryLine`.
  final bool showPreviewTitle;

  @override
  Widget build(BuildContext context) {
    final t = entityType?.trim() ?? '';
    final st = showPreviewTitle;
    switch (t) {
      case AuditEntityTypes.call:
        return CallPreviewWidget(preview: preview, showTitle: st);
      case AuditEntityTypes.task:
        return TaskPreviewWidget(preview: preview, showTitle: st);
      case AuditEntityTypes.user:
        return UserPreviewWidget(preview: preview, showTitle: st);
      case AuditEntityTypes.equipment:
        return EquipmentPreviewWidget(preview: preview, showTitle: st);
      case AuditEntityTypes.phone:
        return UserPreviewWidget(preview: preview, showTitle: st);
      case AuditEntityTypes.maintenance:
        return BackupPreviewWidget(preview: preview, showTitle: st);
      default:
        return SettingsPreviewWidget(preview: preview, showTitle: st);
    }
  }
}
