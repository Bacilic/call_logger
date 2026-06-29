import 'package:flutter/material.dart';

import '../services/lamp_migration_service.dart';
import '../services/lamp_transfer_preview.dart';

/// Ενιαία reactive φόρμα μετανάστευσης με ενσωματωμένη προεπισκόπηση ενεργειών.
class LampTransferMigrationForm extends StatefulWidget {
  const LampTransferMigrationForm({
    super.key,
    required this.target,
    required this.preview,
    required this.controllers,
    required this.saving,
    required this.onCancel,
    required this.onSave,
    required this.saveLabel,
  });

  final LampTransferTarget target;
  final LampTransferPreview preview;
  final Map<String, TextEditingController> controllers;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final String saveLabel;

  @override
  State<LampTransferMigrationForm> createState() =>
      _LampTransferMigrationFormState();
}

class _LampTransferMigrationFormState extends State<LampTransferMigrationForm> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = widget.preview;
    final fieldByKey = {
      for (final field in preview.fields) field.formKey: field,
    };
    final specs = lampTransferFormFieldSpecs(widget.target);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EntitySummaryHeader(preview: preview),
        if (preview.hasAnyWarning) ...[
          const SizedBox(height: 8),
          _WarningBanner(preview: preview),
        ],
        const SizedBox(height: 10),
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: ListView.separated(
              controller: _scrollController,
              primary: false,
              padding: const EdgeInsets.only(right: 4, bottom: 4),
              itemCount: specs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final spec = specs[index];
                final field = fieldByKey[spec.formKey];
                if (field == null) return const SizedBox.shrink();
                final controller = widget.controllers.putIfAbsent(
                  spec.formKey,
                  () => TextEditingController(),
                );
                return _SmartTransferField(
                  spec: spec,
                  field: field,
                  controller: controller,
                );
              },
            ),
          ),
        ),
        const Divider(height: 20),
        Text(
          buildTransferActionSummary(preview),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: widget.saving ? null : widget.onCancel,
              child: const Text('Άκυρο'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: widget.saving ? null : widget.onSave,
              icon: widget.saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(widget.saveLabel),
            ),
          ],
        ),
      ],
    );
  }
}

class _SmartTransferField extends StatelessWidget {
  const _SmartTransferField({
    required this.spec,
    required this.field,
    required this.controller,
  });

  final LampTransferFormFieldSpec spec;
  final LampTransferPreviewField field;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final readOnly = isTransferFieldReadOnly(
      field.action,
      currentValue: controller.text,
      destinationValue: field.destinationValue,
    );
    final lampHint = (field.lampValue?.trim().isNotEmpty ?? false)
        ? 'Λάμπα: ${field.lampValue!.trim()}'
        : null;
    final destinationHint =
        (field.destinationValue?.trim().isNotEmpty ?? false)
        ? 'Προορισμός: ${field.destinationValue!.trim()}'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                spec.required ? '${spec.label} *' : spec.label,
                style: theme.textTheme.titleSmall,
              ),
            ),
            TransferFieldActionChip(action: field.action, compact: true),
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          key: Key('transfer_field_${spec.formKey}'),
          controller: controller,
          readOnly: readOnly,
          enabled: !readOnly,
          maxLines: spec.maxLines,
          keyboardType: spec.keyboardType,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            filled: readOnly,
            fillColor: readOnly
                ? scheme.surfaceContainerHighest.withValues(alpha: 0.45)
                : null,
            helperText: field.hasWarning
                ? null
                : _fieldHelperText(lampHint, readOnly ? destinationHint : null),
            helperMaxLines: 4,
            helperStyle: field.hasWarning
                ? theme.textTheme.bodySmall?.copyWith(color: scheme.error)
                : theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            errorText: field.hasWarning ? field.warningMessage : null,
            errorMaxLines: 3,
          ),
        ),
        if (field.items.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in field.items)
                InputChip(
                  label: Text(item.value),
                  avatar: item.hasWarning
                      ? Icon(Icons.warning_amber, size: 16, color: scheme.error)
                      : null,
                  visualDensity: VisualDensity.compact,
                  labelStyle: theme.textTheme.labelSmall,
                  side: BorderSide(
                    color: transferFieldActionChipColors(
                      item.action,
                      scheme,
                    ).border,
                  ),
                  backgroundColor: transferFieldActionChipColors(
                    item.action,
                    scheme,
                  ).background,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

String? _fieldHelperText(String? primary, String? secondary) {
  final parts = <String>[
    if (primary != null && primary.isNotEmpty) primary,
    if (secondary != null && secondary.isNotEmpty) secondary,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

class _EntitySummaryHeader extends StatelessWidget {
  const _EntitySummaryHeader({required this.preview});

  final LampTransferPreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = preview.result;

    return Card(
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              result.mainEntityMode == TransferEntityMode.newEntry
                  ? Icons.add_circle_outline
                  : Icons.edit_outlined,
              color: scheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transferEntityModeLabel(result.mainEntityMode),
                    style: theme.textTheme.titleSmall,
                  ),
                  if ((result.mainEntityLabel ?? '').isNotEmpty)
                    Text(
                      result.mainEntityLabel!,
                      style: theme.textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
            Text(
              lampTransferTargetLabel(result.target),
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.preview});

  final LampTransferPreview preview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.errorContainer.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.warning_amber_outlined, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Ελέγξτε τα πεδία με προειδοποίηση πριν την αποθήκευση.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Χρωματιστό chip ενέργειας πεδίου μεταφοράς.
class TransferFieldActionChip extends StatelessWidget {
  const TransferFieldActionChip({
    super.key,
    required this.action,
    this.compact = false,
    this.useShortLabel = true,
  });

  final TransferFieldAction action;
  final bool compact;
  final bool useShortLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = transferFieldActionChipColors(action, scheme);
    final label = useShortLabel
        ? transferFieldActionShortLabel(action)
        : transferFieldActionLabel(action);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

({Color background, Color border, Color foreground}) transferFieldActionChipColors(
  TransferFieldAction action,
  ColorScheme scheme,
) {
  return switch (action) {
    TransferFieldAction.created => (
      background: const Color(0xFFE8F5E9),
      border: const Color(0xFF43A047),
      foreground: const Color(0xFF2E7D32),
    ),
    TransferFieldAction.updated => (
      background: const Color(0xFFFFF3E0),
      border: const Color(0xFFFB8C00),
      foreground: const Color(0xFFE65100),
    ),
    TransferFieldAction.linked => (
      background: scheme.primaryContainer.withValues(alpha: 0.55),
      border: scheme.primary,
      foreground: scheme.onPrimaryContainer,
    ),
    TransferFieldAction.unchanged => (
      background: scheme.surfaceContainerHighest,
      border: scheme.outlineVariant,
      foreground: scheme.onSurfaceVariant,
    ),
    TransferFieldAction.unlinked => (
      background: scheme.errorContainer.withValues(alpha: 0.55),
      border: scheme.error,
      foreground: scheme.onErrorContainer,
    ),
  };
}
