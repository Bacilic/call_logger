import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/models/remote_tool.dart';
import '../../../../core/widgets/remote_tool_icon.dart';

/// Πεδίο ονόματος με RawAutocomplete και επικύρωση διπλοτύπου.
class NameAutocompleteField extends StatelessWidget {
  const NameAutocompleteField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.suggestions,
    required this.nonDeleted,
    required this.excludeId,
    this.isCreate = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> suggestions;
  final List<RemoteTool> nonDeleted;
  final int? excludeId;
  /// Στη δημιουργία: ετικέτα με * (υποχρεωτικό πεδίο).
  final bool isCreate;

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      displayStringForOption: (s) => s,
      optionsBuilder: (TextEditingValue tev) {
        final q = tev.text.trim().toLowerCase();
        if (q.isEmpty) {
          return suggestions.take(16);
        }
        return suggestions
            .where((n) => n.toLowerCase().contains(q))
            .take(24);
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 400),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final opt = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(opt),
                    onTap: () => onSelected(opt),
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: textEditingController,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: isCreate ? 'Όνομα εργαλείου *' : 'Όνομα εργαλείου',
            border: const OutlineInputBorder(),
          ),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (v) {
            final name = v?.trim() ?? '';
            if (name.isEmpty) return 'Υποχρεωτικό όνομα εργαλείου.';
            final n = name.toLowerCase();
            for (final t in nonDeleted) {
              if (excludeId != null && t.id == excludeId) continue;
              if (t.name.trim().toLowerCase() == n) {
                return 'Υπάρχει ήδη εργαλείο με αυτό το όνομα.';
              }
            }
            return null;
          },
        );
      },
    );
  }
}

class ExecutablePathField extends StatelessWidget {
  const ExecutablePathField({
    super.key,
    required this.controller,
    required this.onPick,
    required this.enabled,
    this.isCreate = false,
  });

  final TextEditingController controller;
  final VoidCallback onPick;
  final bool enabled;
  /// Στη δημιουργία: ετικέτα με * (υποχρεωτικό πεδίο).
  final bool isCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = controller.text.trim();
    String? missingMsg;
    if (path.isNotEmpty) {
      final f = File(path);
      if (!f.existsSync()) {
        missingMsg = 'Το αρχείο δεν βρέθηκε στη διαδρομή.';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: controller,
                enabled: enabled,
                maxLines: 1,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  labelText: isCreate
                      ? 'Διαδρομή εκτελέσιμου *'
                      : 'Διαδρομή εκτελέσιμου',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Εντοπισμός αρχείου',
              onPressed: enabled ? onPick : null,
              icon: const Icon(Icons.folder_open),
            ),
          ],
        ),
        if (missingMsg != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(
              missingMsg,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

class IconFieldWithPreview extends StatelessWidget {
  const IconFieldWithPreview({
    super.key,
    required this.controller,
    required this.onPick,
    required this.enabled,
  });

  final TextEditingController controller;
  final VoidCallback onPick;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw = controller.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: controller,
                enabled: enabled,
                decoration: const InputDecoration(
                  labelText: 'Εικονίδιο εργαλείου (path ή asset)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Επιλογή εικονιδίου',
              onPressed: enabled ? onPick : null,
              icon: const Icon(Icons.image_outlined),
            ),
            const SizedBox(width: 8),
            _IconPreview(text: raw),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 12),
          child: Text(
            'Διαδρομή προς εικόνα (.png/.svg/.ico) ή asset key. Χρησιμοποιείται στα κουμπιά απομακρυσμένης σύνδεσης. '
            'Προτεραιότητα στο iconAssetKey, fallback στο προεπιλεγμένο εικονίδιο.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _IconPreview extends StatelessWidget {
  const _IconPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    const size = 40.0;
    if (text.isEmpty) {
      return const SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(color: Color(0xFFE0E0E0)),
          child: Icon(Icons.image, size: 22),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: RemoteToolIcon(
        iconAssetKey: text,
        size: 22,
        fallback: Icons.image_outlined,
      ),
    );
  }
}
