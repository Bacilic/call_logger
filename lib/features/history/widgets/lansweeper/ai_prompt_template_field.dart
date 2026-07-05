import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/ai_prompt_template_controller.dart';
import '../../../../core/services/ai_prompt_template_syntax.dart';

/// Είδος πρότασης στο overlay εισαγωγής: μεμονωμένος δεσμευτής θέσης ή block.
enum _PromptSuggestionKind { placeholder, block }

/// Μία πρόταση εισαγωγής (δεσμευτής θέσης ή block) στο floating overlay.
class _PromptSuggestion {
  const _PromptSuggestion({
    required this.name,
    required this.label,
    required this.kind,
  });

  final String name;
  final String label;
  final _PromptSuggestionKind kind;
}

/// Πεδίο προτροπής Gemini με χρωματισμό placeholders/blocks και έλεγχο συντακτικού.
///
/// Πέρα από τον χρωματισμό (μέσω [AiPromptTemplateTextEditingController]),
/// προσφέρει μηχανισμό trigger-based εισαγωγής: όταν ο χρήστης πληκτρολογεί `{`
/// (και δεν βρίσκεται ήδη μέσα σε ολοκληρωμένο token `{...}`), εμφανίζεται
/// floating overlay κάτω από τον δρομέα με φιλτραρισμένη λίστα δεσμευτών θέσης
/// και blocks.
class AiPromptTemplateField extends StatefulWidget {
  const AiPromptTemplateField({
    required this.controller,
    this.onChanged,
    this.minLines = 5,
    this.maxLines = 10,
    super.key,
  });

  final AiPromptTemplateTextEditingController controller;
  final ValueChanged<String>? onChanged;
  final int minLines;
  final int maxLines;

  @override
  State<AiPromptTemplateField> createState() =>
      _AiPromptTemplateFieldState();
}

class _AiPromptTemplateFieldState extends State<AiPromptTemplateField> {
  AiPromptTemplateValidation _validation =
      AiPromptTemplateValidation.valid;

  static const _kShortColorHint =
      'Πράσινο: Δεσμευτές Θέσης · Μπλε: Περιοχές · Μωβ: JSON απάντησης';

  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  final GlobalKey _overlayBoxKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  late final FocusNode _focusNode;

  late final List<_PromptSuggestion> _allSuggestions;

  OverlayEntry? _overlayEntry;

  /// Δείκτης του `{` που ξεκίνησε το ενεργό trigger (null όταν κλειστό).
  int? _triggerStart;

  /// `{` που απορρίφθηκε ρητά (Escape): δεν ξανανοίγει για την ίδια θέση.
  int? _dismissedTriggerStart;

  List<_PromptSuggestion> _filtered = const <_PromptSuggestion>[];
  int _selectedIndex = 0;

  String _lastText = '';
  bool _isApplyingInsertion = false;

  @override
  void initState() {
    super.initState();
    _allSuggestions = _buildAllSuggestions();
    _focusNode = FocusNode(debugLabel: 'AiPromptTemplateField')
      ..onKeyEvent = _handleKeyEvent;
    _focusNode.addListener(_handleFocusChange);
    _scrollController.addListener(_handleFieldScroll);
    _lastText = widget.controller.text;
    widget.controller.addListener(_onTextChanged);
    _validation = AiPromptTemplateSyntax.validate(widget.controller.text);
  }

  @override
  void didUpdateWidget(covariant AiPromptTemplateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _closeOverlay();
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
      _lastText = widget.controller.text;
      _validation = AiPromptTemplateSyntax.validate(widget.controller.text);
    }
  }

  @override
  void dispose() {
    _closeOverlay();
    widget.controller.removeListener(_onTextChanged);
    _scrollController.removeListener(_handleFieldScroll);
    _scrollController.dispose();
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  static List<_PromptSuggestion> _buildAllSuggestions() {
    return <_PromptSuggestion>[
      for (final placeholder in kAiPromptPlaceholders)
        _PromptSuggestion(
          name: AiPromptTemplateSyntax.placeholderNameFromToken(
            placeholder.token,
          ),
          label: placeholder.label,
          kind: _PromptSuggestionKind.placeholder,
        ),
      for (final placeholder in kAiPromptPlaceholders)
        _PromptSuggestion(
          name: AiPromptTemplateSyntax.placeholderNameFromToken(
            placeholder.token,
          ),
          label: 'Block ${placeholder.label}',
          kind: _PromptSuggestionKind.block,
        ),
    ];
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    final next = AiPromptTemplateSyntax.validate(text);
    if (next.isValid != _validation.isValid ||
        next.errors.join() != _validation.errors.join() ||
        next.warnings.join() != _validation.warnings.join()) {
      setState(() => _validation = next);
    }
    widget.onChanged?.call(text);

    if (!_isApplyingInsertion) {
      _updateTriggerOverlay();
    }
    _lastText = text;
  }

  void _handleFieldScroll() {
    _overlayEntry?.markNeedsBuild();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _closeOverlay();
    }
  }

  // --- Trigger detection -----------------------------------------------------

  /// Εντοπίζει ενεργό trigger `{...` αριστερά του δρομέα.
  ///
  /// Επιστρέφει null όταν: δεν υπάρχει `{` πριν τον δρομέα μέσα στην ίδια
  /// «λέξη», ή ο δρομέας βρίσκεται μέσα σε ήδη ολοκληρωμένο token `{...}`.
  ({int start, String query})? _detectTrigger(String text, int caret) {
    if (caret < 0 || caret > text.length) return null;

    var openIndex = -1;
    for (var i = caret - 1; i >= 0; i--) {
      final ch = text[i];
      if (ch == '{') {
        openIndex = i;
        break;
      }
      if (_isTokenBoundaryChar(ch)) {
        return null;
      }
    }
    if (openIndex < 0) return null;

    // Έλεγχος αν ο δρομέας βρίσκεται μέσα σε ήδη κλειστό token {...}.
    for (var j = caret; j < text.length; j++) {
      final ch = text[j];
      if (ch == '}') {
        return null;
      }
      if (ch == '{' || _isTokenBoundaryChar(ch)) {
        break;
      }
    }

    return (start: openIndex, query: text.substring(openIndex + 1, caret));
  }

  static bool _isTokenBoundaryChar(String ch) {
    return ch == '}' || ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
  }

  void _updateTriggerOverlay() {
    if (!mounted) return;
    final value = widget.controller.value;
    final text = value.text;
    final selection = value.selection;
    final textChanged = text != _lastText;

    if (!selection.isValid || !selection.isCollapsed) {
      _dismissedTriggerStart = null;
      _closeOverlay();
      return;
    }

    final trigger = _detectTrigger(text, selection.baseOffset);
    if (trigger == null) {
      _dismissedTriggerStart = null;
      _closeOverlay();
      return;
    }

    if (_dismissedTriggerStart != null &&
        trigger.start == _dismissedTriggerStart) {
      _closeOverlay();
      return;
    }

    // Άνοιγμα μόνο με πληκτρολόγηση — όχι με σκέτη μετακίνηση δρομέα.
    if (_overlayEntry == null && !textChanged) {
      return;
    }

    _openOrUpdateOverlay(trigger.start, trigger.query);
  }

  // --- Φιλτράρισμα -----------------------------------------------------------

  List<_PromptSuggestion> _filterSuggestions(String query) {
    final normalized = query
        .replaceAll(RegExp(r'^[@/]+'), '')
        .trim()
        .toLowerCase();
    if (normalized.isEmpty) return _allSuggestions;
    return _allSuggestions
        .where((s) => s.name.toLowerCase().contains(normalized))
        .toList(growable: false);
  }

  // --- Overlay lifecycle -----------------------------------------------------

  void _openOrUpdateOverlay(int start, String query) {
    final filtered = _filterSuggestions(query);
    if (filtered.isEmpty) {
      _closeOverlay();
      return;
    }

    final wasOpen = _overlayEntry != null;
    _triggerStart = start;
    _filtered = filtered;

    if (!wasOpen) {
      _selectedIndex = 0;
      final overlay = Overlay.maybeOf(context);
      if (overlay == null) return;
      _overlayEntry = OverlayEntry(builder: _buildSuggestionsOverlay);
      overlay.insert(_overlayEntry!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _overlayEntry?.markNeedsBuild();
      });
    } else {
      _selectedIndex = _selectedIndex.clamp(0, filtered.length - 1);
      _overlayEntry!.markNeedsBuild();
    }
  }

  void _closeOverlay() {
    final entry = _overlayEntry;
    if (entry != null) {
      entry.remove();
      entry.dispose();
    }
    _overlayEntry = null;
    _triggerStart = null;
    _filtered = const <_PromptSuggestion>[];
    _selectedIndex = 0;
  }

  void _dismissOverlayWithEscape() {
    _dismissedTriggerStart = _triggerStart;
    _closeOverlay();
  }

  // --- Εισαγωγή token --------------------------------------------------------

  void _insertSuggestion(_PromptSuggestion suggestion) {
    final start = _triggerStart;
    if (start == null) {
      _closeOverlay();
      return;
    }
    final text = widget.controller.text;
    final caret = widget.controller.selection.baseOffset;
    if (start < 0 || caret < start || caret > text.length) {
      _closeOverlay();
      return;
    }

    final String insert;
    final int caretOffset;
    if (suggestion.kind == _PromptSuggestionKind.placeholder) {
      insert = '{${suggestion.name}}';
      caretOffset = insert.length;
    } else {
      final open = AiPromptTemplateSyntax.blockOpenTag(suggestion.name);
      final close = AiPromptTemplateSyntax.blockCloseTag(suggestion.name);
      insert = '$open$close';
      caretOffset = open.length;
    }

    final newText = text.replaceRange(start, caret, insert);
    _isApplyingInsertion = true;
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + caretOffset),
    );
    _isApplyingInsertion = false;

    widget.onChanged?.call(newText);
    _lastText = newText;
    _dismissedTriggerStart = null;
    _closeOverlay();
    _focusNode.requestFocus();
  }

  // --- Keyboard --------------------------------------------------------------

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_overlayEntry == null || _filtered.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _selectedIndex = (_selectedIndex + 1) % _filtered.length;
      _overlayEntry?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _selectedIndex =
          (_selectedIndex - 1 + _filtered.length) % _filtered.length;
      _overlayEntry?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final index = _selectedIndex.clamp(0, _filtered.length - 1);
      _insertSuggestion(_filtered[index]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _dismissOverlayWithEscape();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleTapOutside(PointerDownEvent event) {
    if (_overlayEntry != null &&
        _overlayContainsGlobalPosition(event.position)) {
      // Tap μέσα στο overlay: διατήρηση εστίασης ώστε να ολοκληρωθεί η εισαγωγή.
      return;
    }
    _focusNode.unfocus();
  }

  bool _overlayContainsGlobalPosition(Offset globalPosition) {
    final box = _overlayBoxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return false;
    final local = box.globalToLocal(globalPosition);
    return local.dx >= 0 &&
        local.dy >= 0 &&
        local.dx <= box.size.width &&
        local.dy <= box.size.height;
  }

  // --- Υπολογισμός θέσης δρομέα ----------------------------------------------

  RenderEditable? _findRenderEditable() {
    final renderObject = _fieldKey.currentContext?.findRenderObject();
    if (renderObject == null) return null;
    RenderEditable? result;
    void visit(RenderObject node) {
      if (result != null) return;
      if (node is RenderEditable) {
        result = node;
        return;
      }
      node.visitChildren(visit);
    }

    visit(renderObject);
    return result;
  }

  /// Θέση (bottom-left) του δρομέα ως προς το πλαίσιο του πεδίου.
  Offset _resolveCaretOffsetInField() {
    final fieldBox = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final renderEditable = _findRenderEditable();
    if (fieldBox == null || !fieldBox.attached) {
      return Offset.zero;
    }
    if (renderEditable == null || !renderEditable.attached) {
      return Offset(0, fieldBox.size.height);
    }
    final caret = widget.controller.selection.baseOffset;
    final position = TextPosition(offset: caret < 0 ? 0 : caret);
    Rect caretRect;
    try {
      caretRect = renderEditable.getLocalRectForCaret(position);
    } catch (_) {
      return Offset(0, fieldBox.size.height);
    }
    final globalPoint = renderEditable.localToGlobal(caretRect.bottomLeft);
    return fieldBox.globalToLocal(globalPoint);
  }

  Widget _buildSuggestionsOverlay(BuildContext overlayContext) {
    final caretOffset = _resolveCaretOffsetInField();
    final fieldBox = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final fieldWidth = fieldBox?.size.width ?? 280.0;
    final width = math.min(math.max(fieldWidth, 220.0), 360.0);

    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: caretOffset + const Offset(0, 4),
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.topLeft,
        child: _PromptSuggestionsOverlay(
          boxKey: _overlayBoxKey,
          suggestions: _filtered,
          selectedIndex: _selectedIndex,
          width: width,
          onSelected: _insertSuggestion,
          onHovered: (index) {
            if (index == _selectedIndex) return;
            _selectedIndex = index;
            _overlayEntry?.markNeedsBuild();
          },
        ),
      ),
    );
  }

  void _insertJsonBlueprint() {
    final controller = widget.controller;
    final selection = controller.selection;
    final text = controller.text;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final insert = kAiJsonResponseBlueprint;
    final newText = text.replaceRange(start, end, insert);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
    widget.onChanged?.call(newText);
  }

  Future<void> _showPromptHelpDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Πώς λειτουργεί η προτροπή'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PromptHelpSection(
                title: 'Χρωματισμός',
                body:
                    'Το κείμενο της προτροπής χρωματίζεται αυτόματα ώστε να '
                    'ξεχωρίζουν τα λειτουργικά τμήματά της:\n'
                    '• Πράσινο — δεσμευτές θέσης (placeholders) όπως {Υπάλληλος}, '
                    '{Τμήμα}: αντικαθίστανται με τα πραγματικά στοιχεία της κλήσης.\n'
                    '• Μπλε — πεδία (blocks) {@Όνομα} … {@/Όνομα}: το περιεχόμενο '
                    'ανάμεσά τους εμφανίζεται στην ΤΝ μόνο όταν το αντίστοιχο '
                    'στοιχείο έχει τιμή· διαφορετικά αποσιωπάται εντελώς.\n'
                    '• Κόκκινο, υπογραμμισμένο — άγνωστος ή λανθασμένος δεσμευτής θέσης.',
              ),
              Divider(height: 24),
              _PromptHelpSection(
                title: 'Δεσμευτές θέσης και πεδία',
                body:
                    'Πληκτρολογήστε τον χαρακτήρα { μέσα στο πεδίο για να ανοίξει '
                    'λίστα προτάσεων με δεσμευτές θέσης (μεμονωμένα στοιχεία) και '
                    'πεδία (προαιρετικά τμήματα κειμένου). Συνεχίστε να γράφετε για '
                    'φιλτράρισμα, πλοηγηθείτε με τα βέλη πάνω/κάτω και επιβεβαιώστε '
                    'με Enter ή με κλικ· το Escape κλείνει τη λίστα. Ένα πεδίο είναι '
                    'χρήσιμο όταν θέλετε μια ολόκληρη φράση να εμφανίζεται μόνο υπό '
                    'προϋπόθεση — π.χ. να αναφέρεται ο εξοπλισμός μόνο αν η κλήση '
                    'συνδέεται με συγκεκριμένο εξοπλισμό.',
              ),
              Divider(height: 24),
              _PromptHelpSection(
                title: 'Μορφή απάντησης',
                body:
                    'Η προτροπή πρέπει πάντα να ζητά από την ΤΝ απάντηση σε JSON με τα '
                    'τρία πεδία title, description, solution — π.χ.\n'
                    '{"title":"…","description":"…","solution":"…"}\n'
                    'Χωρίς αυτό το αίτημα, η εφαρμογή δεν θα μπορέσει να διαβάσει την '
                    'απάντηση και να συμπληρώσει τη φόρμα. Η σειρά των τριών πεδίων δεν '
                    'έχει σημασία· η παρουσία τους είναι το μόνο απαραίτητο.',
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Κατάλαβα'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.45) ??
        const TextStyle(fontSize: 14, height: 1.45);
    final hintStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final validation = _validation;
    const warningColor = Color(0xFFD97706);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(_kShortColorHint, style: hintStyle),
            ),
            IconButton(
              tooltip: 'Πώς λειτουργεί η προτροπή',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              iconSize: 18,
              onPressed: _showPromptHelpDialog,
              icon: Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: ActionChip(
            visualDensity: VisualDensity.compact,
            avatar: const Icon(Icons.data_object_outlined, size: 16),
            label: const Text('JSON απάντησης'),
            onPressed: _insertJsonBlueprint,
          ),
        ),
        const SizedBox(height: 6),
        CompositedTransformTarget(
          link: _layerLink,
          child: InputDecorator(
            key: _fieldKey,
            decoration: InputDecoration(
              labelText: 'Προτροπή Τεχνητής Νοημοσύνης',
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
              errorText: validation.isValid ? null : validation.errors.first,
              errorMaxLines: 4,
            ),
            isFocused: false,
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              scrollController: _scrollController,
              minLines: widget.minLines,
              maxLines: widget.maxLines,
              style: baseStyle,
              cursorColor: theme.colorScheme.primary,
              onTapOutside: _handleTapOutside,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
        if (validation.isValid && validation.warnings.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: warningColor,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  validation.warnings.first,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: warningColor,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (!validation.isValid && validation.errors.length > 1) ...[
          const SizedBox(height: 4),
          ...validation.errors.skip(1).map(
                (error) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    error,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ),
        ],
        if (validation.warnings.length > 1) ...[
          const SizedBox(height: 4),
          ...validation.warnings.skip(1).map(
                (warning) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          size: 14,
                          color: warningColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          warning,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: warningColor,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ],
    );
  }
}

/// Floating overlay με τη φιλτραρισμένη λίστα προτάσεων εισαγωγής.
class _PromptSuggestionsOverlay extends StatelessWidget {
  const _PromptSuggestionsOverlay({
    required this.boxKey,
    required this.suggestions,
    required this.selectedIndex,
    required this.width,
    required this.onSelected,
    required this.onHovered,
  });

  final Key boxKey;
  final List<_PromptSuggestion> suggestions;
  final int selectedIndex;
  final double width;
  final ValueChanged<_PromptSuggestion> onSelected;
  final ValueChanged<int> onHovered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: boxKey,
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      color: theme.colorScheme.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: 240, maxWidth: width),
        child: SizedBox(
          width: width,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            shrinkWrap: true,
            itemCount: suggestions.length,
            itemBuilder: (context, index) {
              final suggestion = suggestions[index];
              final selected = index == selectedIndex;
              final isBlock =
                  suggestion.kind == _PromptSuggestionKind.block;
              return MouseRegion(
                onEnter: (_) => onHovered(index),
                child: InkWell(
                  canRequestFocus: false,
                  onTap: () => onSelected(suggestion),
                  child: Container(
                    color: selected
                        ? theme.colorScheme.primary.withValues(alpha: 0.12)
                        : null,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isBlock
                              ? Icons.view_day_outlined
                              : Icons.label_outline,
                          size: 16,
                          color: isBlock
                              ? const Color(0xFF2563EB)
                              : const Color(0xFF16A34A),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            suggestion.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PromptHelpSection extends StatelessWidget {
  const _PromptHelpSection({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
        ),
      ],
    );
  }
}
