import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/lansweeper_ticket_submit_config.dart';
import '../../providers/lansweeper_ticket_submit_config_provider.dart';

/// Ενότητα ρυθμίσεων παραμετροποίησης πολυβηματικής καταχώρησης Lansweeper.
class LansweeperTicketSubmitSettingsSection extends ConsumerWidget {
  const LansweeperTicketSubmitSettingsSection({super.key});

  static List<String> parseLines(String raw) {
    return raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  static String linesText(List<String> values) => values.join('\n');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(lansweeperTicketSubmitConfigProvider);
    final notifier = ref.read(lansweeperTicketSubmitConfigProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Παραμετροποίηση καταχώρησης εισιτηρίου',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        _CustomFieldsEditor(config: config, notifier: notifier),
        const SizedBox(height: 12),
        _ListWithDefaultSection(
          title: 'Καταστάσεις ticket',
          listLabel: 'Καταστάσεις (μία ανά γραμμή)',
          defaultLabel: 'Προεπιλογή κατάστασης',
          values: config.ticketStates,
          selected: config.defaultTicketState,
          onListChanged: (lines) => unawaited(notifier.setTicketStates(lines)),
          onDefaultChanged: (value) =>
              unawaited(notifier.setDefaultTicketState(value)),
        ),
        const SizedBox(height: 12),
        _ListWithDefaultSection(
          title: 'Τύπος αιτήματος (Type)',
          listLabel: 'Τύποι αιτήματος (μία ανά γραμμή)',
          defaultLabel: 'Προεπιλογή τύπου αιτήματος',
          values: config.ticketTypes,
          selected: config.ticketType,
          onListChanged: (lines) => unawaited(notifier.setTicketTypes(lines)),
          onDefaultChanged: (value) => unawaited(notifier.setTicketType(value)),
        ),
        const SizedBox(height: 12),
        _ListWithDefaultSection(
          title: 'Προτεραιότητα (Priority)',
          listLabel: 'Προτεραιότητες (μία ανά γραμμή)',
          defaultLabel: 'Προεπιλογή προτεραιότητας',
          values: config.priorities,
          selected: config.priority,
          onListChanged: (lines) => unawaited(notifier.setPriorities(lines)),
          onDefaultChanged: (value) => unawaited(notifier.setPriority(value)),
        ),
        const SizedBox(height: 12),
        _ListWithDefaultSection(
          title: 'Ομάδα (Team)',
          listLabel: 'Ομάδες (μία ανά γραμμή)',
          defaultLabel: 'Προεπιλογή ομάδας',
          values: config.teams,
          selected: config.team,
          onListChanged: (lines) => unawaited(notifier.setTeams(lines)),
          onDefaultChanged: (value) => unawaited(notifier.setTeam(value)),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('note_type_${config.noteType}'),
          isExpanded: true,
          initialValue: config.noteType == 'Public' ? 'Public' : 'Internal',
          decoration: const InputDecoration(
            labelText: 'Τύπος σημείωσης',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'Internal', child: Text('Ιδιωτική')),
            DropdownMenuItem(value: 'Public', child: Text('Δημόσια')),
          ],
          onChanged: (value) {
            if (value != null) unawaited(notifier.setNoteType(value));
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ενεργό βήμα σημείωσης (AddNote)'),
          value: config.enableAddNoteStep,
          onChanged: (value) =>
              unawaited(notifier.setEnableAddNoteStep(value)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ενεργό βήμα κατάστασης (EditTicket)'),
          value: config.enableStateUpdateStep,
          onChanged: (value) =>
              unawaited(notifier.setEnableStateUpdateStep(value)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Απομνημόνευση τελευταίων επιλογών φόρμας'),
          value: config.rememberFormSelections,
          onChanged: (value) =>
              unawaited(notifier.setRememberFormSelections(value)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Προσθήκη χρόνου εργασίας στη σημείωση'),
          subtitle: const Text(
            'Όταν είναι ενεργό, προστίθεται γραμμή «Χρόνος: MM:SS» στη σημείωση λύσης.',
          ),
          value: config.includeNoteTime,
          onChanged: (value) =>
              unawaited(notifier.setIncludeNoteTime(value)),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.restore),
            label: const Text('Επαναφορά προεπιλογών'),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Επαναφορά προεπιλογών;'),
                  content: const Text(
                    'Θα αντικατασταθούν όλες οι ρυθμίσεις καταχώρησης '
                    'με τις προεπιλογές Lansweeper.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Ακύρωση'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Επαναφορά'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await notifier.resetToDefaults();
              }
            },
          ),
        ),
      ],
    );
  }
}

class _ListWithDefaultSection extends StatefulWidget {
  const _ListWithDefaultSection({
    required this.title,
    required this.listLabel,
    required this.defaultLabel,
    required this.values,
    required this.selected,
    required this.onListChanged,
    required this.onDefaultChanged,
  });

  final String title;
  final String listLabel;
  final String defaultLabel;
  final List<String> values;
  final String selected;
  final ValueChanged<List<String>> onListChanged;
  final ValueChanged<String> onDefaultChanged;

  @override
  State<_ListWithDefaultSection> createState() =>
      _ListWithDefaultSectionState();
}

class _ListWithDefaultSectionState extends State<_ListWithDefaultSection> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: LansweeperTicketSubmitSettingsSection.linesText(widget.values),
    );
  }

  @override
  void didUpdateWidget(covariant _ListWithDefaultSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextText =
        LansweeperTicketSubmitSettingsSection.linesText(widget.values);
    if (_controller.text != nextText) {
      _controller.text = nextText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.values.isEmpty
        ? <String>[if (widget.selected.trim().isNotEmpty) widget.selected]
        : widget.values;
    final selected = items.contains(widget.selected)
        ? widget.selected
        : (items.isNotEmpty ? items.first : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _controller,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: widget.listLabel,
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          onChanged: (raw) => widget.onListChanged(
            LansweeperTicketSubmitSettingsSection.parseLines(raw),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.defaultLabel}_$selected'),
          isExpanded: true,
          initialValue: selected,
          decoration: InputDecoration(
            labelText: widget.defaultLabel,
            border: const OutlineInputBorder(),
          ),
          items: items
              .map(
                (value) => DropdownMenuItem<String>(
                  value: value,
                  child: Text(value, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: selected == null
              ? null
              : (value) {
                  if (value != null) widget.onDefaultChanged(value);
                },
        ),
      ],
    );
  }
}

class _CustomFieldsEditor extends ConsumerWidget {
  const _CustomFieldsEditor({
    required this.config,
    required this.notifier,
  });

  final LansweeperTicketSubmitConfig config;
  final LansweeperTicketSubmitConfigNotifier notifier;

  Future<void> _editField(
    BuildContext context, {
    LansweeperCustomFieldDef? existing,
    int? index,
  }) async {
    final result = await showDialog<LansweeperCustomFieldDef>(
      context: context,
      builder: (ctx) => _CustomFieldEditDialog(initial: existing),
    );
    if (result == null) return;
    final next = List<LansweeperCustomFieldDef>.from(config.customFields);
    if (index == null) {
      next.add(result);
    } else {
      next[index] = result;
    }
    await notifier.replaceCustomFields(next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Πεδία εισιτηρίου (custom fields)',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            TextButton.icon(
              onPressed: () => unawaited(_editField(context)),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Προσθήκη'),
            ),
          ],
        ),
        if (config.customFields.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Δεν υπάρχουν προσαρμοσμένα πεδία.'),
          ),
        for (var i = 0; i < config.customFields.length; i++) ...[
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(config.customFields[i].formLabel),
              subtitle: Text(
                '${config.customFields[i].apiName} · '
                '${_widgetTypeLabel(config.customFields[i].widgetType)}',
              ),
              trailing: Wrap(
                spacing: 0,
                children: [
                  IconButton(
                    tooltip: 'Μετακίνηση πάνω',
                    onPressed: i == 0
                        ? null
                        : () async {
                            final next = List<LansweeperCustomFieldDef>.from(
                              config.customFields,
                            );
                            final item = next.removeAt(i);
                            next.insert(i - 1, item);
                            await notifier.replaceCustomFields(next);
                          },
                    icon: const Icon(Icons.arrow_upward, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Μετακίνηση κάτω',
                    onPressed: i >= config.customFields.length - 1
                        ? null
                        : () async {
                            final next = List<LansweeperCustomFieldDef>.from(
                              config.customFields,
                            );
                            final item = next.removeAt(i);
                            next.insert(i + 1, item);
                            await notifier.replaceCustomFields(next);
                          },
                    icon: const Icon(Icons.arrow_downward, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Επεξεργασία',
                    onPressed: () => unawaited(
                      _editField(
                        context,
                        existing: config.customFields[i],
                        index: i,
                      ),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Διαγραφή',
                    onPressed: () async {
                      final next = List<LansweeperCustomFieldDef>.from(
                        config.customFields,
                      )..removeAt(i);
                      await notifier.replaceCustomFields(next);
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _widgetTypeLabel(LansweeperFieldWidgetType type) {
    switch (type) {
      case LansweeperFieldWidgetType.dropdown:
        return 'Λίστα';
      case LansweeperFieldWidgetType.radio:
        return 'Ραδιοπλήκτρα';
      case LansweeperFieldWidgetType.text:
        return 'Κείμενο';
    }
  }
}

class _CustomFieldEditDialog extends StatefulWidget {
  const _CustomFieldEditDialog({this.initial});

  final LansweeperCustomFieldDef? initial;

  @override
  State<_CustomFieldEditDialog> createState() => _CustomFieldEditDialogState();
}

class _CustomFieldEditDialogState extends State<_CustomFieldEditDialog> {
  late final TextEditingController _apiName;
  late final TextEditingController _formLabel;
  late final TextEditingController _options;
  late final TextEditingController _defaultValue;
  late LansweeperFieldWidgetType _widgetType;
  late bool _visible;
  late bool _required;
  late bool _showInForm;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _apiName = TextEditingController(text: initial?.apiName ?? '');
    _formLabel = TextEditingController(text: initial?.formLabel ?? '');
    _options = TextEditingController(
      text: LansweeperTicketSubmitSettingsSection.linesText(
        initial?.options ?? const [],
      ),
    );
    _defaultValue = TextEditingController(text: initial?.defaultValue ?? '');
    _widgetType = initial?.widgetType ?? LansweeperFieldWidgetType.dropdown;
    _visible = initial?.visible ?? true;
    _required = initial?.required ?? false;
    _showInForm = initial?.showInForm ?? true;
  }

  @override
  void dispose() {
    _apiName.dispose();
    _formLabel.dispose();
    _options.dispose();
    _defaultValue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initial == null ? 'Νέο πεδίο' : 'Επεξεργασία πεδίου',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _apiName,
                decoration: const InputDecoration(
                  labelText: 'Όνομα API',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _formLabel,
                decoration: const InputDecoration(
                  labelText: 'Ετικέτα φόρμας',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<LansweeperFieldWidgetType>(
                initialValue: _widgetType,
                decoration: const InputDecoration(
                  labelText: 'Τύπος',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: LansweeperFieldWidgetType.dropdown,
                    child: Text('Λίστα'),
                  ),
                  DropdownMenuItem(
                    value: LansweeperFieldWidgetType.radio,
                    child: Text('Ραδιοπλήκτρα'),
                  ),
                  DropdownMenuItem(
                    value: LansweeperFieldWidgetType.text,
                    child: Text('Κείμενο'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _widgetType = value);
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _options,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Επιλογές (μία ανά γραμμή)',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _defaultValue,
                decoration: const InputDecoration(
                  labelText: 'Προεπιλογή',
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ορατό'),
                value: _visible,
                onChanged: (v) => setState(() => _visible = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Υποχρεωτικό'),
                value: _required,
                onChanged: (v) => setState(() => _required = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Εμφάνιση στη φόρμα'),
                value: _showInForm,
                onChanged: (v) => setState(() => _showInForm = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: () {
            final id = widget.initial?.id.trim().isNotEmpty == true
                ? widget.initial!.id
                : 'field_${DateTime.now().millisecondsSinceEpoch}';
            Navigator.of(context).pop(
              LansweeperCustomFieldDef(
                id: id,
                apiName: _apiName.text.trim(),
                formLabel: _formLabel.text.trim(),
                widgetType: _widgetType,
                options: LansweeperTicketSubmitSettingsSection.parseLines(
                  _options.text,
                ),
                defaultValue: _defaultValue.text.trim(),
                visible: _visible,
                required: _required,
                showInForm: _showInForm,
              ),
            );
          },
          child: const Text('Αποθήκευση'),
        ),
      ],
    );
  }
}
