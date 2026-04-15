import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/settings_provider.dart';
import '../../../../core/providers/spell_check_provider.dart';
import '../../../../core/widgets/spell_check_controller.dart';
import '../../provider/call_entry_provider.dart';
import '../../provider/notes_field_hint_provider.dart';

/// Πεδίο σημειώσεων σε στυλ post-it (εκτός state για αποφυγή διαρροής μνήμης).
class NotesStickyField extends ConsumerStatefulWidget {
  const NotesStickyField({super.key});

  @override
  ConsumerState<NotesStickyField> createState() => NotesStickyFieldState();
}

class NotesStickyFieldState extends ConsumerState<NotesStickyField> {
  late final SpellCheckController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _flashHighlight = false;
  bool _flashPlaying = false;
  Offset? _lastSecondaryPointerGlobal;

  @override
  void initState() {
    super.initState();
    final initialNotes = ref.read(callEntryProvider).notes;
    _controller = SpellCheckController();
    _controller.text = initialNotes;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _replaceWordAtCursor(TextEditingValue v, String replacement) {
    var offset = v.selection.extentOffset;
    if (offset < 0) offset = 0;
    if (offset > v.text.length) offset = v.text.length;
    final t = v.text;
    for (final m in SpellCheckController.wordPattern.allMatches(t)) {
      if (offset >= m.start && offset <= m.end) {
        final nt = t.replaceRange(m.start, m.end, replacement);
        _controller.value = TextEditingValue(
          text: nt,
          selection: TextSelection.collapsed(
            offset: m.start + replacement.length,
          ),
        );
        ref.read(callEntryProvider.notifier).setNotes(nt);
        _controller.refreshSpellDecorations();
        return;
      }
    }
  }

  Widget _contextMenuBuilder(BuildContext context, EditableTextState state) {
    final v = state.textEditingValue;
    var offset = v.selection.extentOffset;
    if (offset < 0) offset = 0;
    if (offset > v.text.length) offset = v.text.length;
    final global = _lastSecondaryPointerGlobal;
    if (global != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !state.mounted) return;
        state.renderEditable.selectPositionAt(
          from: global,
          cause: SelectionChangedCause.tap,
        );
      });
    }
    _lastSecondaryPointerGlobal = null;

    final extras = <ContextMenuButtonItem>[];
    final spellOn = ref.read(enableSpellCheckProvider).value ?? true;
    final spell = switch (ref.read(spellCheckServiceProvider)) {
      AsyncData(:final value) => value,
      _ => null,
    };
    if (spellOn && spell != null && _controller.isWordMisspelledAt(v, offset)) {
      final raw = _controller.wordAtCursorOffset(v, offset);
      if (raw != null) {
        for (final sug in spell.getSuggestions(raw)) {
          extras.add(
            ContextMenuButtonItem(
              label: sug,
              onPressed: () {
                state.hideToolbar();
                _replaceWordAtCursor(v, sug);
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
                if (mounted) _controller.refreshSpellDecorations();
              }());
            },
          ),
        );
      }
    }

    final defaults = state.contextMenuButtonItems
        .where((e) => e.onPressed != null)
        .toList();
    final items = <ContextMenuButtonItem>[...extras, ...defaults];

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    final platform = Theme.of(context).platform;
    final useDesktopLayout =
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.fuchsia ||
        platform == TargetPlatform.macOS;
    final anchors = state.contextMenuAnchors;

    if (useDesktopLayout) {
      return _desktopNotesContextMenu(context, items, anchors);
    }
    return TextSelectionToolbar(
      anchorAbove: anchors.primaryAnchor,
      anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
      toolbarBuilder: (ctx, child) {
        return Material(
          borderRadius: BorderRadius.circular(8),
          elevation: 4,
          clipBehavior: Clip.antiAlias,
          color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
          child: IntrinsicWidth(child: child),
        );
      },
      children: [
        for (final item in items)
          InkWell(
            onTap: item.onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: Text(
                  AdaptiveTextSelectionToolbar.getButtonLabel(context, item),
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _desktopNotesContextMenu(
    BuildContext context,
    List<ContextMenuButtonItem> items,
    TextSelectionToolbarAnchors anchors,
  ) {
    const kToolbarScreenPadding = 8.0;
    final paddingAbove =
        MediaQuery.paddingOf(context).top + kToolbarScreenPadding;
    final localAdjustment = Offset(kToolbarScreenPadding, paddingAbove);
    final buttonWidgets = AdaptiveTextSelectionToolbar.getAdaptiveButtons(
      context,
      items,
    ).toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        kToolbarScreenPadding,
        paddingAbove,
        kToolbarScreenPadding,
        kToolbarScreenPadding,
      ),
      child: CustomSingleChildLayout(
        delegate: DesktopTextSelectionToolbarLayoutDelegate(
          anchor: anchors.primaryAnchor - localAdjustment,
        ),
        child: Material(
          borderRadius: BorderRadius.circular(8),
          elevation: 4,
          clipBehavior: Clip.antiAlias,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: buttonWidgets,
            ),
          ),
        ),
      ),
    );
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
    ref.listen(spellCheckServiceProvider, (prev, next) {
      next.whenData((s) {
        if (mounted) _controller.attachSpellService(s);
      });
    });
    ref.listen(enableSpellCheckProvider, (prev, next) {
      next.whenData((e) {
        if (mounted) _controller.setSpellCheckEnabled(e);
      });
    });

    final spellAsync = ref.watch(spellCheckServiceProvider);
    final spellEnabledAsync = ref.watch(enableSpellCheckProvider);
    spellAsync.whenData(_controller.attachSpellService);
    spellEnabledAsync.whenData(_controller.setSpellCheckEnabled);

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
          padding: const EdgeInsets.all(6),
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
            child: Listener(
              onPointerDown: (event) {
                if (event.kind == PointerDeviceKind.mouse &&
                    event.buttons == kSecondaryMouseButton) {
                  _lastSecondaryPointerGlobal = event.position;
                }
              },
              child: TextField(
                focusNode: _focusNode,
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: 'Σημειώσεις...',
                  hintStyle: TextStyle(
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
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
                // Guardrail for future text-snippet expansion (e.g. .pwd):
                // expansion logic must respect remaining characters.
                maxLength: 500,
                buildCounter:
                    (
                      BuildContext context, {
                      required int currentLength,
                      required bool isFocused,
                      required int? maxLength,
                    }) {
                      return Text(
                        '$currentLength / ${maxLength ?? 500}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    },
                spellCheckConfiguration:
                    const SpellCheckConfiguration.disabled(),
                contextMenuBuilder: _contextMenuBuilder,
                onChanged: (value) =>
                    ref.read(callEntryProvider.notifier).setNotes(value),
              ),
            ),
          ),
        );
      },
    );
  }
}
