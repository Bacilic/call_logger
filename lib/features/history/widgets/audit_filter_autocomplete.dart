import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/search_text_normalizer.dart';

/// Επιλογή για το [AuditFilterAutocomplete]: αποθηκευμένη τιμή + ετικέτα UI.
class AuditFilterAutocompleteOption {
  const AuditFilterAutocompleteOption({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;
}

/// Πεδίο φίλτρου με autocomplete (μοτίβο Λάμπας: overlay, Enter, X, κενό = όλα).
class AuditFilterAutocomplete extends StatefulWidget {
  const AuditFilterAutocomplete({
    super.key,
    required this.labelText,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
    this.selectedLabel,
    this.enabled = true,
  });

  final String labelText;
  final List<AuditFilterAutocompleteOption> options;
  final String? selectedValue;
  final String? selectedLabel;
  final ValueChanged<String?> onSelected;
  final bool enabled;

  @override
  State<AuditFilterAutocomplete> createState() =>
      _AuditFilterAutocompleteState();
}

class _AuditFilterAutocompleteState extends State<AuditFilterAutocomplete> {
  /// Σταθερό ύψος γραμμής πρότασης — απαραίτητο για την κύλιση-στην-επιλογή.
  static const double _kOptionExtent = 44;

  final LayerLink _layerLink = LayerLink();
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _overlayScroll = ScrollController();
  OverlayEntry? _overlayEntry;
  List<AuditFilterAutocompleteOption> _suggestions =
      const <AuditFilterAutocompleteOption>[];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _syncControllerFromSelection();
    _controller.addListener(_onTextChanged);
    _focusNode.onKeyEvent = _handleKey;
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant AuditFilterAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedValue != widget.selectedValue &&
        !_focusNode.hasFocus) {
      _syncControllerFromSelection();
    }
    if (oldWidget.options != widget.options && _focusNode.hasFocus) {
      _refreshSuggestions();
    }
  }

  @override
  void deactivate() {
    _focusNode.unfocus();
    _removeOverlay();
    super.deactivate();
  }

  @override
  void dispose() {
    _removeOverlay();
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    _overlayScroll.dispose();
    super.dispose();
  }

  /// Κρατά την επισημασμένη πρόταση ορατή όταν η πλοήγηση γίνεται με βέλη.
  void _ensureHighlightedVisible() {
    if (!_overlayScroll.hasClients) return;
    final itemTop = _selectedIndex * _kOptionExtent;
    final itemBottom = itemTop + _kOptionExtent;
    final viewTop = _overlayScroll.offset;
    final viewBottom = viewTop + _overlayScroll.position.viewportDimension;
    double? target;
    if (itemTop < viewTop) {
      target = itemTop;
    } else if (itemBottom > viewBottom) {
      target = itemBottom - _overlayScroll.position.viewportDimension;
    }
    if (target != null) {
      _overlayScroll.jumpTo(
        target.clamp(0.0, _overlayScroll.position.maxScrollExtent),
      );
    }
  }

  void _syncControllerFromSelection() {
    final next = widget.selectedLabel ?? widget.selectedValue ?? '';
    if (_controller.text == next) return;
    _controller.text = next;
    _controller.selection = TextSelection.collapsed(offset: next.length);
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _removeOverlay();
      _syncControllerFromSelection();
    } else {
      _refreshSuggestions();
    }
  }

  void _onTextChanged() {
    setState(() {});
    _refreshSuggestions();
  }

  List<AuditFilterAutocompleteOption> _filteredOptions(String query) {
    final normalized = SearchTextNormalizer.normalizeForSearch(query.trim());
    if (normalized.isEmpty) {
      return widget.options;
    }
    return widget.options
        .where(
          (option) =>
              SearchTextNormalizer.matchesNormalizedQuery(
                option.label,
                normalized,
              ) ||
              SearchTextNormalizer.matchesNormalizedQuery(
                option.value,
                normalized,
              ),
        )
        .toList();
  }

  /// Το overlay ΔΕΝ επιτρέπεται να αλλάξει μέσα σε build (π.χ. κλήση από
  /// didUpdateWidget)· εκτός build εκτελείται άμεσα, αλλιώς στο επόμενο frame.
  void _runOutsideBuild(VoidCallback action) {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      action();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  void _refreshSuggestions() {
    if (!widget.enabled || !_focusNode.hasFocus) {
      _runOutsideBuild(_removeOverlay);
      return;
    }
    final suggestions = _filteredOptions(_controller.text);
    if (suggestions.isEmpty) {
      _runOutsideBuild(_removeOverlay);
      return;
    }
    setState(() {
      _suggestions = suggestions;
      _selectedIndex = 0;
    });
    _runOutsideBuild(() {
      if (!_focusNode.hasFocus) return;
      _showOverlay();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_overlayScroll.hasClients) _overlayScroll.jumpTo(0);
      });
    });
  }

  void _showOverlay() {
    _removeOverlay();
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: 320,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 52),
            child: TextFieldTapRegion(
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    controller: _overlayScroll,
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemExtent: _kOptionExtent,
                    itemCount: _suggestions.length,
                    itemBuilder: (context, index) {
                      final option = _suggestions[index];
                      final selected = index == _selectedIndex;
                      final scheme = Theme.of(context).colorScheme;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        selectedTileColor: scheme.primaryContainer,
                        selectedColor: scheme.onPrimaryContainer,
                        title: Text(
                          option.label,
                          style: selected
                              ? const TextStyle(fontWeight: FontWeight.w700)
                              : null,
                        ),
                        trailing: selected
                            ? Icon(
                                Icons.keyboard_return,
                                size: 16,
                                color: scheme.onPrimaryContainer,
                              )
                            : null,
                        onTap: () => _applySuggestion(option),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    final entry = _overlayEntry;
    if (entry != null) {
      entry.remove();
      entry.dispose();
      _overlayEntry = null;
    }
  }

  void _applySuggestion(AuditFilterAutocompleteOption option) {
    _controller.text = option.label;
    _controller.selection = TextSelection.collapsed(
      offset: option.label.length,
    );
    widget.onSelected(option.value);
    _removeOverlay();
    _focusNode.requestFocus();
  }

  void _clearSelection() {
    _controller.clear();
    widget.onSelected(null);
    _removeOverlay();
    _focusNode.requestFocus();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (_overlayEntry == null || _suggestions.isEmpty) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _removeOverlay();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1) % _suggestions.length;
      });
      _overlayEntry?.markNeedsBuild();
      _ensureHighlightedVisible();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex =
            (_selectedIndex - 1 + _suggestions.length) % _suggestions.length;
      });
      _overlayEntry?.markNeedsBuild();
      _ensureHighlightedVisible();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _applySuggestion(_suggestions[_selectedIndex]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _removeOverlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        focusNode: _focusNode,
        controller: _controller,
        enabled: widget.enabled,
        decoration: InputDecoration(
          labelText: widget.labelText,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          isDense: true,
          suffixIcon: _controller.text.trim().isEmpty
              ? null
              : IconButton(
                  tooltip: 'Καθαρισμός ${widget.labelText.toLowerCase()}',
                  onPressed: widget.enabled ? _clearSelection : null,
                  icon: const Icon(Icons.clear),
                ),
        ),
      ),
    );
  }
}
