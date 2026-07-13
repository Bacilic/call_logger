import 'package:flutter/material.dart';

import '../../../../core/models/remote_tool.dart';
import '../../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../../core/widgets/reorder_grab_handle.dart';
import 'remote_tool_form_controller.dart';

/// Επεξεργασία ορισμάτων γραμμής εντολών (οδηγούμενη από [RemoteToolFormController]).
class RemoteToolArgumentsEditor extends StatefulWidget {
  const RemoteToolArgumentsEditor({super.key, required this.controller});

  final RemoteToolFormController controller;

  @override
  State<RemoteToolArgumentsEditor> createState() =>
      _RemoteToolArgumentsEditorState();
}

class _RemoteToolArgumentsEditorState extends State<RemoteToolArgumentsEditor> {
  RemoteToolFormController get _ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onInsertPlaceholder(String token) {
    final focus = _ctrl.insertPlaceholder(token);
    if (focus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        focus.requestFocus();
      });
    }
  }

  List<RemoteToolArgument> _currentArguments() {
    return _ctrl.argRows
        .map(
          (r) => RemoteToolArgument(
            value: r.valueC.text,
            description: r.descC.text,
            isActive: r.active,
          ),
        )
        .toList();
  }

  Widget _buildArgumentsWarningBanner(ThemeData theme, String message) {
    final cs = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: cs.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warningMessage = RemoteTool.buildArgumentsEditorWarning(
      _currentArguments(),
      role: _ctrl.role,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Placeholders: {TARGET}, {EQUIPMENT_CODE}, {FILE}. '
          'Κωδικοί/χρήστης ως απλό κείμενο στο value (π.χ. /p:…). '
          'Κενό value παραλείπεται στην αποθήκευση. '
          'Με ενεργό όρισμα {FILE}, ο εξοπλισμός αποκτά πεδίο "Αρχείο σύνδεσης (.rdp)".',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final ph in [
              '{TARGET}',
              '{EQUIPMENT_CODE}',
              '{FILE}',
            ])
              FilledButton.tonal(
                onPressed: _ctrl.saving ? null : () => _onInsertPlaceholder(ph),
                child: Text(ph),
              ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _ctrl.saving ? null : _ctrl.addArg,
          icon: const Icon(Icons.add),
          label: const Text('Προσθήκη ορίσματος'),
        ),
        if (warningMessage != null) ...[
          const SizedBox(height: 12),
          _buildArgumentsWarningBanner(theme, warningMessage),
        ],
        const SizedBox(height: 12),
        if (_ctrl.argRows.isEmpty)
          Text(
            'Κανένα ορίσμα.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (o, n) {
              if (!_ctrl.saving) _ctrl.reorderArgs(o, n);
            },
            children: [
              for (var i = 0; i < _ctrl.argRows.length; i++)
                KeyedSubtree(
                  key: ValueKey(_ctrl.argRows[i].stableId),
                  child: _ArgRowTile(
                    index: i,
                    row: _ctrl.argRows[i],
                    onRemove: () => _ctrl.removeArg(i),
                    onToggleActive: (v) => _ctrl.setArgActive(i, v ?? false),
                    saving: _ctrl.saving,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _ArgRowTile extends StatelessWidget {
  const _ArgRowTile({
    required this.index,
    required this.row,
    required this.onRemove,
    required this.onToggleActive,
    required this.saving,
  });

  final int index;
  final RemoteToolArgRow row;
  final VoidCallback onRemove;
  final ValueChanged<bool?> onToggleActive;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ReorderGrabHandle(
                    index: index,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  Checkbox(
                    value: row.active,
                    onChanged: saving ? null : onToggleActive,
                  ),
                  Expanded(
                    child: TextField(
                      controller: row.valueC,
                      focusNode: row.valueFocus,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Όρισμα (τιμή)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Διαγραφή',
                    onPressed: saving ? null : onRemove,
                  ),
                ],
              ),
              AbsorbPointer(
                absorbing: saving,
                child: Opacity(
                  opacity: saving ? 0.5 : 1,
                  child: LexiconSpellTextFormField(
                    controller: row.descC,
                    focusNode: row.descFocus,
                    decoration: const InputDecoration(
                      labelText: 'Περιγραφή',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
