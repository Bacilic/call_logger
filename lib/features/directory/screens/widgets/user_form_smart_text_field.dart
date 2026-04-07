import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/lexicon_spell_menu_helper.dart';
import '../../../../core/widgets/spell_check_controller.dart';

/// Πεδίο φόρμας χρήστη: πρώτο κλικ μετά το focus = επιλογή όλου, μετά κανονικό κλικ,
/// γρήγορο διπλό κλικ = λέξη, τριπλό = όλο. Μενού επιλογής με πλάτος περιεχομένου.
///
/// Με [lexiconSpellAssist] χρησιμοποιείται ο ίδιος ορθογραφικός έλεγχος λεξικού
/// όπως στις Σημειώσεις (desktop κ.λπ.)· ο [controller] πρέπει να είναι
/// [SpellCheckController].
class UserFormSmartTextField extends ConsumerStatefulWidget {
  const UserFormSmartTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.decoration,
    this.validator,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.spellCheckConfiguration,
    this.lexiconSpellAssist = false,
    this.onChanged,
    this.onEditingComplete,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final InputDecoration decoration;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int maxLines;
  final SpellCheckConfiguration? spellCheckConfiguration;

  /// Ορθογραφικός έλεγχος μέσω εσωτερικού λεξικού ([SpellCheckController]).
  final bool lexiconSpellAssist;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;

  @override
  ConsumerState<UserFormSmartTextField> createState() =>
      _UserFormSmartTextFieldState();
}

class _UserFormSmartTextFieldState
    extends ConsumerState<UserFormSmartTextField> {
  final GlobalKey _fieldKey = GlobalKey();
  bool _selectAllOnNextTap = true;
  Timer? _multiTapTimer;
  DateTime? _previousPointerDown;
  int _tapChain = 0;
  Offset? _lastPointerGlobal;
  Offset? _lastSecondaryPointerGlobal;

  SpellCheckController? get _spellController =>
      widget.lexiconSpellAssist && widget.controller is SpellCheckController
      ? widget.controller as SpellCheckController
      : null;

  static const _multiTapWindow = Duration(milliseconds: 420);

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    _multiTapTimer?.cancel();
    super.dispose();
  }

  void _onFocusChange() {
    if (widget.focusNode.hasFocus) {
      setState(() => _selectAllOnNextTap = true);
    }
  }

  void _selectAll() {
    final t = widget.controller.text;
    widget.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: t.length,
    );
  }

  bool _isWs(String text, int i) {
    final c = text.codeUnitAt(i);
    return c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
  }

  /// Εύρος «λέξης» (συνεχές μη-κενό) γύρω από το offset.
  (int, int) _wordRangeAt(String text, int offset) {
    if (text.isEmpty) return (0, 0);
    var o = offset.clamp(0, text.length);
    if (o == text.length && o > 0) o = text.length - 1;
    while (o < text.length && _isWs(text, o)) {
      o++;
    }
    if (o >= text.length) return (text.length, text.length);
    var s = o;
    while (s > 0 && !_isWs(text, s - 1)) {
      s--;
    }
    var e = o;
    while (e < text.length && !_isWs(text, e)) {
      e++;
    }
    return (s, e);
  }

  RenderEditable? _findRenderEditable(RenderObject? node) {
    if (node == null) return null;
    if (node is RenderEditable) return node;
    RenderEditable? found;
    node.visitChildren((child) {
      found ??= _findRenderEditable(child);
    });
    return found;
  }

  void _selectWordAt(Offset globalPosition) {
    final ctx = _fieldKey.currentContext;
    if (ctx == null) return;
    final editable = _findRenderEditable(ctx.findRenderObject());
    if (editable == null) return;
    final local = editable.globalToLocal(globalPosition);
    final textPosition = editable.getPositionForPoint(local);
    final off = textPosition.offset;
    final text = widget.controller.text;
    final range = _wordRangeAt(text, off);
    widget.controller.selection = TextSelection(
      baseOffset: range.$1,
      extentOffset: range.$2,
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons == kSecondaryMouseButton) {
      if (_spellController != null) {
        _lastSecondaryPointerGlobal = event.position;
      }
      return;
    }
    final now = DateTime.now();
    if (_previousPointerDown == null ||
        now.difference(_previousPointerDown!) > _multiTapWindow) {
      _tapChain = 0;
    }
    _previousPointerDown = now;
    _tapChain++;
    _lastPointerGlobal = event.position;
    _multiTapTimer?.cancel();

    if (_tapChain >= 3) {
      _multiTapTimer?.cancel();
      _multiTapTimer = null;
      _selectAll();
      _tapChain = 0;
      return;
    }

    _multiTapTimer = Timer(_multiTapWindow, () {
      if (!mounted) return;
      if (_tapChain == 2 && _lastPointerGlobal != null) {
        _selectWordAt(_lastPointerGlobal!);
      }
      _tapChain = 0;
    });
  }

  Widget _contextMenu(BuildContext context, EditableTextState state) {
    final sc = _spellController;
    if (sc != null) {
      LexiconSpellMenuHelper.positionCursorFromSecondaryClick(
        global: _lastSecondaryPointerGlobal,
        state: state,
        isMounted: () => mounted,
      );
      _lastSecondaryPointerGlobal = null;
    }

    final defaults = state.contextMenuButtonItems
        .where((e) => e.onPressed != null)
        .toList();
    final spellExtras = sc != null
        ? LexiconSpellMenuHelper.spellButtonItems(
            ref: ref,
            controller: sc,
            state: state,
            onFieldChanged: widget.onChanged,
          )
        : <ContextMenuButtonItem>[];
    final items = [...spellExtras, ...defaults];
    final platform = Theme.of(context).platform;
    final useDesktopLayout =
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.fuchsia ||
        platform == TargetPlatform.macOS;
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final anchors = state.contextMenuAnchors;
    if (useDesktopLayout) {
      return _desktopIntrinsicContextMenu(context, items, anchors);
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

  /// Σε Windows/Linux/macOS το [TextSelectionToolbar] δεν τοποθετείται σωστά·
  /// ακολουθούμε τη διάταξη [DesktopTextSelectionToolbar] με στενό [IntrinsicWidth].
  Widget _desktopIntrinsicContextMenu(
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
    return Listener(
      onPointerDown: _handlePointerDown,
      child: TextFormField(
        key: _fieldKey,
        controller: widget.controller,
        focusNode: widget.focusNode,
        decoration: widget.decoration,
        validator: widget.validator,
        keyboardType: widget.keyboardType,
        textCapitalization: widget.textCapitalization,
        maxLines: widget.maxLines,
        spellCheckConfiguration: widget.lexiconSpellAssist
            ? const SpellCheckConfiguration.disabled()
            : widget.spellCheckConfiguration,
        contextMenuBuilder: _contextMenu,
        onEditingComplete: widget.onEditingComplete,
        onChanged: widget.onChanged,
        onTap: () {
          if (_selectAllOnNextTap) {
            _selectAll();
            setState(() => _selectAllOnNextTap = false);
          }
        },
      ),
    );
  }
}
