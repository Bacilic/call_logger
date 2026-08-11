import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/lansweeper_identity_diagnosis.dart';
import '../../../../core/services/lansweeper_requester_resolution.dart';
import '../../../../core/services/lansweeper_ticket_submit_config.dart';
import '../../../../core/widgets/compact_tooltip.dart';
import '../../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../../core/widgets/resizable_text_area.dart';
import '../../../../core/widgets/spell_check_controller.dart';
import '../../../../core/widgets/app_asset_image.dart';

/// Διαβάθμιση εγκυρότητας αιτούντα: εντάξει / ύποπτος τομέας / λάθος μορφή.
enum _RequesterSeverity { ok, suspect, invalid }

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
    this.onSaveAsKnowledge,
    this.saveAsKnowledgeDisabledTooltip,
    this.autoParties,
    this.requesterCandidates = const [],
    this.selectedRequesterUsername,
    this.onRequesterChanged,
    this.referenceDomain,
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

  /// Κρατά τη λύση ως άρθρο Βάσης Γνώσης· `null` κρύβει το κουμπί εντελώς.
  final VoidCallback? onSaveAsKnowledge;

  /// Γιατί δεν γίνεται τώρα (π.χ. κενή λύση) — αλλιώς το κουμπί απλώς σβήνει
  /// χωρίς εξήγηση και μοιάζει με βλάβη.
  final String? saveAsKnowledgeDisabledTooltip;

  /// Τι θα μπει αυτόματα στο ticket: αιτών (υπάλληλος) και εξοπλισμός.
  /// Null = δεν έχει φορτώσει ακόμη· η γραμμή δεν εμφανίζεται καθόλου.
  final ({String? requester, String? asset})? autoParties;

  /// Οι λογαριασμοί του τμήματος όταν ο καλών δεν έχει δικό του αναγνωριστικό.
  /// Κενή λίστα = καμία επιλογή προς εμφάνιση.
  final List<LansweeperRequesterCandidate> requesterCandidates;

  /// Τομέας αναφοράς για τις πορτοκαλί υποψίες τομέα — null = χωρίς μέτρο
  /// σύγκρισης (βλ. τη συνάρτηση lansweeperReferenceDomain του πυρήνα).
  final String? referenceDomain;

  /// Ποιος είναι επιλεγμένος· κενό = «χωρίς αιτούντα».
  final String? selectedRequesterUsername;
  final ValueChanged<String>? onRequesterChanged;

  static Color cooldownRemainingColor(int seconds) {
    if (seconds > 30) return Colors.red;
    if (seconds >= 10) return Colors.orange;
    return Colors.green;
  }

  /// Διαβάθμιση ενός αιτούντα με την ίδια γλώσσα των chips του τμήματος.
  _RequesterSeverity _requesterSeverity(String username) {
    final trimmed = username.trim();
    if (trimmed.isEmpty) return _RequesterSeverity.ok;
    if (!diagnoseLansweeperIdentity(trimmed).isValid) {
      return _RequesterSeverity.invalid;
    }
    if (lansweeperDomainMismatchHint(trimmed, referenceDomain) != null) {
      return _RequesterSeverity.suspect;
    }
    return _RequesterSeverity.ok;
  }

  /// Το στοχευμένο μήνυμα για τον αιτούντα — null όταν όλα είναι εντάξει.
  String? _requesterAlertText(String username) {
    final trimmed = username.trim();
    if (trimmed.isEmpty) return null;
    final diagnosis = diagnoseLansweeperIdentity(trimmed);
    if (!diagnosis.isValid) {
      final suggestion = diagnosis.suggestion;
      final base = suggestion == null
          ? diagnosis.problem!
          : '${diagnosis.problem!} — $suggestion';
      return '$base.\nΑν δεν βρεθεί στο Lansweeper, το ticket θα '
          'καταχωρηθεί χωρίς αιτούντα.';
    }
    return lansweeperDomainMismatchHint(trimmed, referenceDomain);
  }

  /// Η γραμμή «Στο ticket»: ο αιτών χρωματίζεται όταν η διάγνωση έχει κάτι
  /// να πει (κόκκινο = λάθος μορφή, πορτοκαλί = ύποπτος τομέας), με το
  /// στοχευμένο μήνυμα στο tooltip — ποτέ φραγμός: τον τελικό λόγο τον έχει
  /// το SearchUsers του Lansweeper κατά την καταχώρηση.
  Widget _buildAutoPartiesLine(BuildContext context) {
    final theme = Theme.of(context);
    final requester = autoParties!.requester;
    final severity = requester == null
        ? _RequesterSeverity.ok
        : _requesterSeverity(requester);
    final alert = requester == null ? null : _requesterAlertText(requester);

    var message =
        'Συμπληρώνονται αυτόματα στο ticket από τα αναγνωριστικά '
        'του Καταλόγου. Το «—» σημαίνει χωρίς αντιστοίχιση: εκεί '
        'το ticket βγαίνει όπως πριν και συμπληρώνετε χειροκίνητα '
        'στο Lansweeper.';
    if (alert != null) {
      message = '$message\n\n⚠ $alert';
    }

    final baseStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final requesterStyle = switch (severity) {
      _RequesterSeverity.invalid => TextStyle(
        color: theme.colorScheme.error,
        fontWeight: FontWeight.w600,
      ),
      _RequesterSeverity.suspect => TextStyle(
        color: Colors.orange.shade800,
        fontWeight: FontWeight.w600,
      ),
      _RequesterSeverity.ok => null,
    };

    return CompactTooltip(
      message: message,
      child: Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            const TextSpan(text: 'Στο ticket — Αιτών: '),
            TextSpan(text: requester ?? '—', style: requesterStyle),
            TextSpan(text: ' · Εξοπλισμός: ${autoParties!.asset ?? '—'}'),
          ],
        ),
        key: const ValueKey('lansweeper_auto_parties_line'),
      ),
    );
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
            (option) =>
                Text(option, overflow: TextOverflow.ellipsis, maxLines: 1),
          )
          .toList(),
      items: field.options
          .map(
            (option) => DropdownMenuItem<String>(
              value: option,
              child: Text(option, overflow: TextOverflow.ellipsis, maxLines: 2),
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
            icon: AppAssetImage(
              assetPath: 'assets/prompt_editor.png',
              width: 20,
              height: 20,
              fallbackIcon: Icons.edit_note,
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
                (state) =>
                    DropdownMenuItem<String>(value: state, child: Text(state)),
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
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (autoParties != null) ...[
              const SizedBox(height: 4),
              _buildAutoPartiesLine(context),
            ],
            if (requesterCandidates.isNotEmpty) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: const ValueKey('lansweeper_requester_picker'),
                isExpanded: true,
                initialValue: selectedRequesterUsername ?? '',
                decoration: const InputDecoration(
                  labelText: 'Αιτών στο ticket',
                  helperText:
                      'Ο καλών δεν έχει δικό του αναγνωριστικό — διαλέξτε '
                      'λογαριασμό του τμήματος.',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final candidate in requesterCandidates)
                    DropdownMenuItem<String>(
                      value: candidate.account.username,
                      child: Text(
                        '${candidate.departmentName} · '
                        '${candidate.account.displayLabel}',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        // Ίδια χρωματική γλώσσα με τα chips του τμήματος:
                        // κόκκινο = λάθος μορφή, πορτοκαλί = ύποπτος τομέας.
                        style: switch (_requesterSeverity(
                          candidate.account.username,
                        )) {
                          _RequesterSeverity.invalid => TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                          _RequesterSeverity.suspect => TextStyle(
                            color: Colors.orange.shade800,
                          ),
                          _RequesterSeverity.ok => null,
                        },
                      ),
                    ),
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('Χωρίς αιτούντα (μπαίνω εγώ ως πράκτορας)'),
                  ),
                ],
                onChanged: onRequesterChanged == null
                    ? null
                    : (value) => onRequesterChanged!(value ?? ''),
              ),
            ],
            const SizedBox(height: 8),
            LexiconSpellTextFormField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Τίτλος',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            ResizableTextArea(
              controller: notesController,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'Σημειώσεις - Πρόβλημα (περιγραφή ticket)',
                hintText: 'Η περιγραφή που θα μπει στο ticket.',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            ResizableTextArea(
              controller: solutionController,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'Λύση',
                hintText:
                    'Προστίθεται ως σημείωση (Note) στο ticket — ΟΧΙ στην περιγραφή.',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            if (onSaveAsKnowledge != null || saveAsKnowledgeDisabledTooltip != null)
              Align(
                alignment: Alignment.centerLeft,
                child: CompactTooltip(
                  message: onSaveAsKnowledge == null
                      ? (saveAsKnowledgeDisabledTooltip ?? '')
                      : 'Κρατά το σύμπτωμα και τη λύση ως άρθρο, για την '
                            'επόμενη φορά που θα εμφανιστεί το ίδιο',
                  child: TextButton.icon(
                    onPressed: onSaveAsKnowledge,
                    icon: const Icon(Icons.healing, size: 18),
                    label: const Text('Αποθήκευση ως γνώση'),
                  ),
                ),
              ),
            ...customFieldWidgets,
          ],
        ),
      ),
    );
  }
}
