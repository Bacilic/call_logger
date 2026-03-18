import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/spell_check.dart';
import '../../provider/call_entry_provider.dart';

/// Πεδίο σημειώσεων σε στυλ post-it (εκτός state για αποφυγή διαρροής μνήμης).
class NotesStickyField extends ConsumerStatefulWidget {
  const NotesStickyField({super.key, required this.entry});

  final CallEntryState entry;

  @override
  ConsumerState<NotesStickyField> createState() => NotesStickyFieldState();
}

class NotesStickyFieldState extends ConsumerState<NotesStickyField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.entry.notes);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = ref.watch(callEntryProvider);
    if (entry.notes.isEmpty && _controller.text.isNotEmpty) {
      _controller.text = '';
    }
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth.isFinite && c.maxWidth > 0
            ? math.min(400.0, c.maxWidth)
            : 400.0;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF9C4),
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 6,
                offset: Offset(2, 4),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: TextField(
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
