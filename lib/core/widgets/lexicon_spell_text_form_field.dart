import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../providers/spell_check_provider.dart';
import 'spell_check_controller.dart';

/// TextFormField με custom ορθογραφικό έλεγχο από εσωτερικό λεξικό.
class LexiconSpellTextFormField extends ConsumerStatefulWidget {
  const LexiconSpellTextFormField({
    super.key,
    required this.controller,
    required this.decoration,
    this.validator,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.minLines,
    this.onChanged,
    this.focusNode,
  });

  final SpellCheckController controller;
  final InputDecoration decoration;
  final String? Function(String?)? validator;
  final TextCapitalization textCapitalization;
  final int? maxLines;
  final int? minLines;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  @override
  ConsumerState<LexiconSpellTextFormField> createState() =>
      _LexiconSpellTextFormFieldState();
}

class _LexiconSpellTextFormFieldState
    extends ConsumerState<LexiconSpellTextFormField> {
  Offset? _lastSecondaryPointerGlobal;

  int _resolveCursorOffsetForContextMenu(
    EditableTextState state,
  ) {
    final value = state.textEditingValue;
    return value.selection.extentOffset.clamp(0, value.text.length);
  }

  void _replaceWordAtOffset(
    TextEditingValue value,
    int rawOffset,
    String replacement,
  ) {
    var offset = rawOffset;
    if (offset < 0) offset = 0;
    if (offset > value.text.length) offset = value.text.length;
    final t = value.text;
    for (final m in SpellCheckController.wordPattern.allMatches(t)) {
      if (offset >= m.start && offset <= m.end) {
        final nt = t.replaceRange(m.start, m.end, replacement);
        widget.controller.value = TextEditingValue(
          text: nt,
          selection: TextSelection.collapsed(
            offset: m.start + replacement.length,
          ),
        );
        widget.onChanged?.call(nt);
        widget.controller.refreshSpellDecorations();
        return;
      }
    }
  }

  Widget _contextMenuBuilder(BuildContext context, EditableTextState state) {
    final v = state.textEditingValue;
    final offset = _resolveCursorOffsetForContextMenu(state);
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
    if (spellOn &&
        spell != null &&
        widget.controller.isWordMisspelledAt(v, offset)) {
      final raw = widget.controller.wordAtCursorOffset(v, offset);
      if (raw != null) {
        for (final sug in spell.getSuggestions(raw)) {
          extras.add(
            ContextMenuButtonItem(
              label: sug,
              onPressed: () {
                state.hideToolbar();
                _replaceWordAtOffset(widget.controller.value, offset, sug);
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
                if (mounted) widget.controller.refreshSpellDecorations();
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
    final useDesktopLayout = platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.fuchsia ||
        platform == TargetPlatform.macOS;
    final anchors = state.contextMenuAnchors;
    if (useDesktopLayout) {
      return _desktopContextMenu(context, items, anchors);
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

  Widget _desktopContextMenu(
    BuildContext context,
    List<ContextMenuButtonItem> items,
    TextSelectionToolbarAnchors anchors,
  ) {
    const kToolbarScreenPadding = 8.0;
    final paddingAbove =
        MediaQuery.paddingOf(context).top + kToolbarScreenPadding;
    final localAdjustment = Offset(kToolbarScreenPadding, paddingAbove);
    final buttonWidgets =
        AdaptiveTextSelectionToolbar.getAdaptiveButtons(context, items)
            .toList();

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

  @override
  Widget build(BuildContext context) {
    final spellAsync = ref.watch(spellCheckServiceProvider);
    final spellEnabledAsync = ref.watch(enableSpellCheckProvider);

    // Άμεσο sync του controller με την τρέχουσα τιμή των providers,
    // ώστε το spell check να ενεργοποιείται σωστά από το πρώτο render.
    spellAsync.whenData(widget.controller.attachSpellService);
    spellEnabledAsync.whenData(widget.controller.setSpellCheckEnabled);

    return Listener(
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons == kSecondaryMouseButton) {
          _lastSecondaryPointerGlobal = event.position;
        }
      },
      child: TextFormField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        decoration: widget.decoration,
        validator: widget.validator,
        textCapitalization: widget.textCapitalization,
        maxLines: widget.maxLines,
        minLines: widget.minLines,
        spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
        contextMenuBuilder: _contextMenuBuilder,
        onChanged: widget.onChanged,
      ),
    );
  }
}
