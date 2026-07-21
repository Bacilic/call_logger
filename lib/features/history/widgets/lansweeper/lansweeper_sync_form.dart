import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/lansweeper_ticket_submit_config.dart';
import '../../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../../core/widgets/spell_check_controller.dart';

class LansweeperSyncForm extends ConsumerWidget {
  const LansweeperSyncForm({
    required this.titleController,
    required this.notesController,
    required this.solutionController,
    this.onSuggest,
    this.onPreviewPrompt,
    this.onEditPromptTemplate,
    this.isSuggesting = false,
    this.suggestModelLabel,
    this.suggestElapsedLabel,
    this.suggestDisabledTooltip,
    this.previewDisabledTooltip,
    this.cooldownRemainingSeconds,
    this.cooldownModelLabel,
    this.onCancelAutoResubmit,
    this.config,
    this.customFieldValues = const <String, String>{},
    this.onCustomFieldChanged,
    this.ticketState,
    this.onTicketStateChanged,
    super.key,
  });

  final SpellCheckController titleController;
  final SpellCheckController notesController;
  final SpellCheckController solutionController;
  final VoidCallback? onSuggest;
  final VoidCallback? onPreviewPrompt;
  final VoidCallback? onEditPromptTemplate;
  final bool isSuggesting;
  final String? suggestModelLabel;
  final String? suggestElapsedLabel;
  final String? suggestDisabledTooltip;
  final String? previewDisabledTooltip;
  final int? cooldownRemainingSeconds;
  final String? cooldownModelLabel;
  final VoidCallback? onCancelAutoResubmit;
  final LansweeperTicketSubmitConfig? config;
  final Map<String, String> customFieldValues;
  final void Function(String fieldId, String value)? onCustomFieldChanged;
  final String? ticketState;
  final ValueChanged<String>? onTicketStateChanged;

  static Color cooldownRemainingColor(int seconds) {
    if (seconds > 30) return Colors.red;
    if (seconds >= 10) return Colors.orange;
    return Colors.green;
  }

  Widget _buildCustomField(
    BuildContext context,
    LansweeperCustomFieldDef field,
  ) {
    final currentValue = customFieldValues[field.id] ?? field.defaultValue;

    if (field.widgetType == LansweeperFieldWidgetType.text) {
      return TextFormField(
        key: ValueKey('lansweeper_custom_field_${field.id}'),
        initialValue: currentValue,
        decoration: InputDecoration(
          labelText: field.formLabel,
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) => onCustomFieldChanged?.call(field.id, value),
      );
    }

    final dropdownValue = field.options.contains(currentValue)
        ? currentValue
        : (field.options.isNotEmpty ? field.options.first : null);

    return DropdownButtonFormField<String>(
      key: ValueKey('lansweeper_custom_field_${field.id}'),
      isExpanded: true,
      initialValue: dropdownValue,
      decoration: InputDecoration(
        labelText: field.formLabel,
        border: const OutlineInputBorder(),
      ),
      selectedItemBuilder: (context) => field.options
          .map(
            (option) => Text(
              option,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          )
          .toList(),
      items: field.options
          .map(
            (option) => DropdownMenuItem<String>(
              value: option,
              child: Text(
                option,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          )
          .toList(),
      onChanged: onCustomFieldChanged == null
          ? null
          : (value) {
              if (value != null) {
                onCustomFieldChanged!.call(field.id, value);
              }
            },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inCooldown = cooldownRemainingSeconds != null;
    final suggestEnabled = !isSuggesting && !inCooldown && onSuggest != null;

    final suggestButtonLabel = inCooldown
        ? (cooldownModelLabel ?? 'Αναμονή ποσόστωσης')
        : isSuggesting
        ? (suggestModelLabel ?? 'Πρόταση…')
        : 'Πρόταση ΤΝ';

    final suggestButton = FilledButton.tonalIcon(
      onPressed: suggestEnabled ? onSuggest : null,
      icon: isSuggesting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('✨', style: TextStyle(fontSize: 16)),
      label: Text(suggestButtonLabel),
    );

    final previewButton = OutlinedButton.icon(
      onPressed: isSuggesting || inCooldown ? null : onPreviewPrompt,
      icon: const Icon(Icons.article_outlined, size: 18),
      label: const Text('Προεπισκόπηση προτροπής'),
    );

    final promptEditorButton = onEditPromptTemplate == null
        ? null
        : IconButton(
            tooltip: 'Επεξεργασία προτύπου προτροπής',
            onPressed: isSuggesting || inCooldown ? null : onEditPromptTemplate,
            icon: Image.asset(
              'assets/prompt_editor.png',
              width: 20,
              height: 20,
            ),
          );

    final cooldownTooltip = inCooldown
        ? 'Αναμένεται διαθεσιμότητα ποσόστωσης για το μοντέλο '
            '${cooldownModelLabel ?? 'ΤΝ'}.'
        : suggestDisabledTooltip;

    final suggestRow = Row(
      children: [
        if (!suggestEnabled && cooldownTooltip != null)
          Tooltip(message: cooldownTooltip, child: suggestButton)
        else
          suggestButton,
        if (isSuggesting && suggestElapsedLabel != null) ...[
          const SizedBox(width: 10),
          Text(
            '${suggestElapsedLabel!} δλ',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ],
        if (inCooldown) ...[
          const SizedBox(width: 10),
          Text(
            '${cooldownRemainingSeconds!} δλ',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: cooldownRemainingColor(cooldownRemainingSeconds!),
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (onCancelAutoResubmit != null) ...[
            const SizedBox(width: 6),
            TextButton(
              onPressed: onCancelAutoResubmit,
              child: const Text('Ακύρωση'),
            ),
          ],
        ],
        const Spacer(),
        if (promptEditorButton != null) ...[
          promptEditorButton,
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: previewDisabledTooltip != null && onPreviewPrompt == null
                  ? Tooltip(
                      message: previewDisabledTooltip!,
                      child: previewButton,
                    )
                  : previewButton,
            ),
          ),
        ),
      ],
    );

    final formConfig = config;
    final customFieldWidgets = <Widget>[];
    if (formConfig != null) {
      for (final field in formConfig.customFields) {
        if (!field.showInForm || !field.visible) continue;
        customFieldWidgets.add(const SizedBox(height: 10));
        customFieldWidgets.add(_buildCustomField(context, field));
      }
      customFieldWidgets.add(const SizedBox(height: 10));
      customFieldWidgets.add(
        DropdownButtonFormField<String>(
          key: const ValueKey('lansweeper_ticket_state'),
          isExpanded: true,
          initialValue: ticketState ?? formConfig.defaultTicketState,
          decoration: const InputDecoration(
            labelText: 'Κατάσταση ticket',
            border: OutlineInputBorder(),
          ),
          items: formConfig.ticketStates
              .map(
                (state) => DropdownMenuItem<String>(
                  value: state,
                  child: Text(state),
                ),
              )
              .toList(),
          onChanged: onTicketStateChanged == null
              ? null
              : (value) {
                  if (value != null) {
                    onTicketStateChanged!(value);
                  }
                },
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            suggestRow,
            const SizedBox(height: 8),
            Text(
              'Φόρμα καταχώρησης Lansweeper',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            LexiconSpellTextFormField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Τίτλος',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            LexiconSpellTextFormField(
              controller: notesController,
              minLines: 2,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: 'Σημειώσεις - Πρόβλημα (περιγραφή ticket)',
                hintText:
                    'Καλών και εξοπλισμό συμπληρώνετε χειροκίνητα στο Lansweeper.',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            LexiconSpellTextFormField(
              controller: solutionController,
              minLines: 2,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: 'Λύση',
                hintText:
                    'Προστίθεται ως σημείωση (Note) στο ticket — ΟΧΙ στην περιγραφή.',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            ...customFieldWidgets,
          ],
        ),
      ),
    );
  }
}
