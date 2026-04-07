import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../providers/spell_check_provider.dart';
import 'lexicon_spell_menu_helper.dart';
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

  Widget _contextMenuBuilder(BuildContext context, EditableTextState state) {
    final global = _lastSecondaryPointerGlobal;
    LexiconSpellMenuHelper.positionCursorFromSecondaryClick(
      global: global,
      state: state,
      isMounted: () => mounted,
    );
    _lastSecondaryPointerGlobal = null;

    final extras = LexiconSpellMenuHelper.spellButtonItems(
      ref: ref,
      controller: widget.controller,
      state: state,
      onFieldChanged: widget.onChanged,
    );

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
