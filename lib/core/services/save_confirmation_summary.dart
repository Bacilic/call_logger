import '../database/audit_diff_helper.dart';
import '../database/audit_service.dart';
import '../models/remote_tool.dart';
import '../models/remote_tool_role.dart';

const _kMaxVisibleFieldChanges = 4;

/// Εμφανίζεται όταν το diff δεν εντοπίζει αλλαγές σε πεδία που παρακολουθεί —
/// η αποθήκευση μπορεί ωστόσο να άγγιξε πεδία εκτός diff (π.χ. εικονίδιο,
/// περιγραφές ορισμάτων), γι' αυτό το κείμενο δεν ισχυρίζεται «καμία αλλαγή».
const String kSaveConfirmationNoChangesMessage = 'Οι αλλαγές αποθηκεύτηκαν';

/// Μήνυμα επιβεβαίωσης ρητής αποθήκευσης (ίδιο λεξιλόγιο με Ιστορικό Εφαρμογής).
String buildSaveConfirmationMessage({
  required String entityType,
  required String entityLabel,
  required Map<String, dynamic> oldMap,
  required Map<String, dynamic> newMap,
  required bool isNew,
}) {
  final label = entityLabel.trim();
  final noun = _entityNoun(entityType);

  if (isNew) {
    return 'Δημιουργήθηκε $noun «$label»';
  }

  final newKeys = newMap.keys.toSet();
  final orderedKeys = AuditDiffHelper.orderedDiffKeys(entityType, newKeys);
  final changeLines = <String>[];

  for (final key in orderedKeys) {
    if (AuditDiffHelper.shouldSkipDerivativeField(key, newKeys)) continue;
    final oldValue = oldMap[key];
    final newValue = newMap[key];
    if (!AuditService.shouldIncludeFieldInAuditDiff(key, oldValue, newValue)) {
      continue;
    }
    final fieldLabel = AuditDiffHelper.fieldTitleLabel(entityType, key);
    final oldText = _displayFieldValue(key, oldValue);
    final newText = _displayFieldValue(key, newValue);
    changeLines.add('$fieldLabel: $oldText → $newText');
  }

  if (changeLines.isEmpty) {
    return kSaveConfirmationNoChangesMessage;
  }

  final lines = <String>['Αποθηκεύτηκε — $noun «$label»'];
  final visible = changeLines.take(_kMaxVisibleFieldChanges);
  lines.addAll(visible);

  final remaining = changeLines.length - _kMaxVisibleFieldChanges;
  if (remaining > 0) {
    lines.add('… και $remaining ακόμη αλλαγές');
  }

  return lines.join('\n');
}

/// Μήνυμα επιβεβαίωσης επεξεργασίας εργαλείου απομακρυσμένης σύνδεσης.
String buildRemoteToolSaveMessage({
  required RemoteTool oldTool,
  required RemoteTool newTool,
}) {
  final label = newTool.name.trim();
  final changeLines = <String>[];

  void addChange(String fieldLabel, String oldText, String newText) {
    if (oldText == newText) return;
    changeLines.add('$fieldLabel: $oldText → $newText');
  }

  addChange('Όνομα', oldTool.name.trim(), newTool.name.trim());
  addChange(
    'Ρόλος',
    _remoteToolRoleDisplayLabel(oldTool.role),
    _remoteToolRoleDisplayLabel(newTool.role),
  );
  addChange(
    'Διαδρομή εκτελέσιμου',
    oldTool.executablePath.trim(),
    newTool.executablePath.trim(),
  );
  addChange(
    'Δοκιμαστική IP',
    _optionalRemoteToolText(oldTool.testTargetIp),
    _optionalRemoteToolText(newTool.testTargetIp),
  );
  addChange(
    'Ενεργό',
    oldTool.isActive ? 'Ναι' : 'Όχι',
    newTool.isActive ? 'Ναι' : 'Όχι',
  );
  addChange(
    'Αποκλειστικό',
    oldTool.isExclusive ? 'Ναι' : 'Όχι',
    newTool.isExclusive ? 'Ναι' : 'Όχι',
  );
  addChange(
    'Ορίσματα',
    _formatRemoteToolArgumentValues(oldTool.arguments),
    _formatRemoteToolArgumentValues(newTool.arguments),
  );

  if (changeLines.isEmpty) {
    return kSaveConfirmationNoChangesMessage;
  }

  final lines = <String>['Αποθηκεύτηκε — εργαλείο «$label»'];
  final visible = changeLines.take(_kMaxVisibleFieldChanges);
  lines.addAll(visible);

  final remaining = changeLines.length - _kMaxVisibleFieldChanges;
  if (remaining > 0) {
    lines.add('… και $remaining ακόμη αλλαγές');
  }

  return lines.join('\n');
}

/// Διάρκεια SnackBar: 5 δευτ. όταν το μήνυμα έχει πάνω από μία γραμμή.
Duration saveConfirmationSnackBarDuration(String message) {
  return message.contains('\n')
      ? const Duration(seconds: 5)
      : const Duration(seconds: 4);
}

/// Αφαιρεί τεχνικά πεδία εκκρεμότητας πριν το diff επιβεβαίωσης αποθήκευσης.
Map<String, dynamic> mapForTaskSaveConfirmationDiff(Map<String, dynamic> source) {
  return {
    for (final entry in source.entries)
      if (entry.key != 'created_at' &&
          entry.key != 'updated_at' &&
          entry.key != 'snooze_history_json')
        entry.key: entry.value,
  };
}

String _displayFieldValue(String field, dynamic value) {
  if (value is List) {
    final items = value
        .map((e) => '$e'.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (items.isEmpty) return '—';
    return items.join(', ');
  }
  final text = AuditDiffHelper.humanizeFieldValue(field, value);
  if (text.isEmpty || text == 'κενό') return '—';
  return text;
}

String _entityNoun(String entityType) {
  switch (entityType.trim()) {
    case 'department':
      return 'τμήμα';
    case 'user':
      return 'υπάλληλος';
    case 'equipment':
      return 'εξοπλισμός';
    case 'remote_tool':
      return 'εργαλείο';
    case 'call':
      return 'κλήση';
    case 'task':
      return 'εκκρεμότητα';
    default:
      return entityType.trim();
  }
}

String _remoteToolRoleDisplayLabel(ToolRole role) {
  return switch (role) {
    ToolRole.generic => 'Κανένα – Χωρίς αυτόματο στόχο',
    ToolRole.anydesk => 'AnyDesk-like',
    ToolRole.rdp => 'RDP Hostname/IP',
    ToolRole.vnc => 'VNC Host',
  };
}

String _optionalRemoteToolText(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? '—' : trimmed;
}

String _formatRemoteToolArgumentValues(List<RemoteToolArgument> arguments) {
  final values = arguments
      .where((a) => a.isActive)
      .map((a) => a.value.trim())
      .where((v) => v.isNotEmpty)
      .toList();
  if (values.isEmpty) return '—';
  return values.join(', ');
}
