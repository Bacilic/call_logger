import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/spell_check.dart';
import '../../provider/call_entry_provider.dart';
import '../../provider/notes_field_hint_provider.dart';

/// Πεδίο σημειώσεων σε στυλ post-it (εκτός state για αποφυγή διαρροής μνήμης).
class NotesStickyField extends ConsumerStatefulWidget {
  const NotesStickyField({super.key});

  @override
  ConsumerState<NotesStickyField> createState() => NotesStickyFieldState();
}

class NotesStickyFieldState extends ConsumerState<NotesStickyField> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _flashHighlight = false;
  bool _flashPlaying = false;

  @override
  void initState() {
    super.initState();
    final initialNotes = ref.read(callEntryProvider).notes;
    _controller = TextEditingController(text: initialNotes);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _playDoubleFlash() async {
    if (_flashPlaying || !mounted) return;
    _flashPlaying = true;
    _focusNode.requestFocus();
    try {
      for (var i = 0; i < 2; i++) {
        if (!mounted) return;
        setState(() => _flashHighlight = true);
        await Future<void>.delayed(const Duration(milliseconds: 220));
        if (!mounted) return;
        setState(() => _flashHighlight = false);
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    } finally {
      _flashPlaying = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(callEntryProvider.select((s) => s.notes));
    ref.listen<int>(notesFieldHintTickProvider, (prev, next) {
      if (prev != null && next > prev) {
        _playDoubleFlash();
      }
    });
    if (notes.isEmpty && _controller.text.isNotEmpty) {
      _controller.text = '';
    }
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth.isFinite && c.maxWidth > 0
            ? math.min(400.0, c.maxWidth)
            : 400.0;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF9C4),
            borderRadius: BorderRadius.circular(4),
            border: _flashHighlight
                ? Border.all(color: scheme.primary, width: 3)
                : null,
            boxShadow: [
              BoxShadow(
                color: _flashHighlight
                    ? scheme.primary.withValues(alpha: 0.35)
                    : Colors.black12,
                blurRadius: _flashHighlight ? 10 : 6,
                offset: const Offset(2, 4),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: TextField(
              focusNode: _focusNode,
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'Σημειώσεις...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: true,
                fillColor: Colors.transparent,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              minLines: 2,
              maxLines: 5,
              spellCheckConfiguration: platformSpellCheckConfiguration,
              onChanged: (value) =>
                  ref.read(callEntryProvider.notifier).setNotes(value),
            ),
          ),
        );
      },
    );
  }
}
