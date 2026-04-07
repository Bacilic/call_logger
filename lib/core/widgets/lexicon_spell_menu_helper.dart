import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../providers/spell_check_provider.dart';
import 'spell_check_controller.dart';

/// Κοινή λογική μενού ορθογραφίας (λεξικό) για πεδία με [SpellCheckController].
abstract final class LexiconSpellMenuHelper {
  static void replaceWordAtOffset(
    SpellCheckController controller,
    TextEditingValue value,
    int rawOffset,
    String replacement,
    ValueChanged<String>? onChanged,
  ) {
    var offset = rawOffset;
    if (offset < 0) offset = 0;
    if (offset > value.text.length) offset = value.text.length;
    final t = value.text;
    for (final m in SpellCheckController.wordPattern.allMatches(t)) {
      if (offset >= m.start && offset <= m.end) {
        final nt = t.replaceRange(m.start, m.end, replacement);
        controller.value = TextEditingValue(
          text: nt,
          selection: TextSelection.collapsed(
            offset: m.start + replacement.length,
          ),
        );
        onChanged?.call(nt);
        controller.refreshSpellDecorations();
        return;
      }
    }
  }

  static List<ContextMenuButtonItem> spellButtonItems({
    required WidgetRef ref,
    required SpellCheckController controller,
    required EditableTextState state,
    required ValueChanged<String>? onFieldChanged,
  }) {
    final v = state.textEditingValue;
    final offset = v.selection.extentOffset.clamp(0, v.text.length);
    final spellOn = ref.read(enableSpellCheckProvider).value ?? true;
    final spell = switch (ref.read(spellCheckServiceProvider)) {
      AsyncData(:final value) => value,
      _ => null,
    };
    if (!spellOn ||
        spell == null ||
        !controller.isWordMisspelledAt(v, offset)) {
      return [];
    }
    final raw = controller.wordAtCursorOffset(v, offset);
    if (raw == null) return [];
    final extras = <ContextMenuButtonItem>[];
    for (final sug in spell.getSuggestions(raw)) {
      extras.add(
        ContextMenuButtonItem(
          label: sug,
          onPressed: () {
            state.hideToolbar();
            replaceWordAtOffset(
              controller,
              controller.value,
              offset,
              sug,
              onFieldChanged,
            );
          },
        ),
      );
    }
    extras.add(
      ContextMenuButtonItem(
        label: 'Προσθήκη στο λεξικό μου',
        onPressed: () {
          state.hideToolbar();
          unawaited(() async {
            await spell.insertUserWord(raw);
            controller.refreshSpellDecorations();
          }());
        },
      ),
    );
    return extras;
  }

  /// Μετά δεξί κλικ, τοποθετεί τον κέρσορα πριν ανοίξει το μενού.
  static void positionCursorFromSecondaryClick({
    required Offset? global,
    required EditableTextState state,
    bool Function()? isMounted,
  }) {
    if (global == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isMounted != null && !isMounted()) return;
      if (!state.mounted) return;
      state.renderEditable.selectPositionAt(
        from: global,
        cause: SelectionChangedCause.tap,
      );
    });
  }
}
