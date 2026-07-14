import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/old_database/lamp_issue_resolution_models.dart';
import '../../../core/utils/search_text_normalizer.dart';

typedef LampEntityCodeSearchCallback = Future<List<LampEntityCodeSuggestion>>
    Function(String query);

/// Πεδίο κωδικού με autocomplete ονόματος/κωδικού (μοτίβο desktop overlay).
class LampEntityCodeAutocomplete extends StatefulWidget {
  const LampEntityCodeAutocomplete({
    super.key,
    required this.controller,
    required this.searchSuggestions,
    this.decoration,
    this.onCodeSelected,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final LampEntityCodeSearchCallback searchSuggestions;
  final InputDecoration? decoration;
  final ValueChanged<int>? onCodeSelected;

  /// Αν true, το πεδίο εστιάζεται μόλις ανοίξει ο διάλογος, ώστε ο χρήστης να
  /// μπορεί να πληκτρολογήσει αμέσως χωρίς κλικ (τυπική συμπεριφορά Windows).
  final bool autofocus;

  @override
  State<LampEntityCodeAutocomplete> createState() =>
      _LampEntityCodeAutocompleteState();
}

class _LampEntityCodeAutocompleteState extends State<LampEntityCodeAutocomplete> {
  final LayerLink _layerLink = LayerLink();
  final FocusNode _focusNode = FocusNode();
  OverlayEntry? _overlayEntry;
  List<LampEntityCodeSuggestion> _suggestions = const <LampEntityCodeSuggestion>[];
  int _selectedIndex = 0;
  Timer? _searchDebounce;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.onKeyEvent = _handleKey;
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void deactivate() {
    _removeOverlay();
    super.deactivate();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _removeOverlay();
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.onKeyEvent = null;
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _removeOverlay();
    } else {
      _scheduleSearch();
    }
  }

  void _onTextChanged() {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
    _scheduleSearch();
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 120), _refreshSuggestions);
  }

  Future<void> _refreshSuggestions() async {
    if (!_focusNode.hasFocus) {
      _removeOverlay();
      return;
    }
    final query = widget.controller.text.trim();
    if (query.isEmpty) {
      _removeOverlay();
      return;
    }

    final generation = ++_searchGeneration;
    final results = await widget.searchSuggestions(query);
    if (!mounted || generation != _searchGeneration) return;

    if (results.isEmpty) {
      _removeOverlay();
      return;
    }

    setState(() {
      _suggestions = results.take(10).toList();
      _selectedIndex = 0;
    });
    _showOverlay();
  }

  void _showOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: 480,
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
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    itemBuilder: (context, index) {
                      final suggestion = _suggestions[index];
                      final selected = index == _selectedIndex;
                      final scheme = Theme.of(context).colorScheme;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        selectedTileColor: scheme.primaryContainer,
                        selectedColor: scheme.onPrimaryContainer,
                        title: Text(
                          suggestion.displayText,
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
                        onTap: () => _applySuggestion(suggestion),
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
      _suggestions = const <LampEntityCodeSuggestion>[];
      if (mounted) setState(() {});
    }
  }

  void _applySuggestion(LampEntityCodeSuggestion suggestion) {
    widget.controller.text = suggestion.code.toString();
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    _removeOverlay();
    _focusNode.requestFocus();
    widget.onCodeSelected?.call(suggestion.code);
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
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex =
            (_selectedIndex - 1 + _suggestions.length) % _suggestions.length;
      });
      _overlayEntry?.markNeedsBuild();
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
    // Το πεδίο τυλίγεται ΠΑΝΤΑ στο CompositedTransformTarget: αν άλλαζε η δομή
    // του δέντρου κάθε φορά που εμφανίζεται/κρύβεται η λίστα, η Flutter θα
    // ξαναδημιουργούσε το TextField και θα έχανε το focus (κέρσορας/πληκτρολόγηση).
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        focusNode: _focusNode,
        controller: widget.controller,
        decoration: widget.decoration,
        autofocus: widget.autofocus,
      ),
    );
  }
}

/// Τοπικό φιλτράρισμα λίστας προτάσεων (χωρίς τόνους / πεζά-κεφαλαία).
List<LampEntityCodeSuggestion> filterEntityCodeSuggestions(
  List<LampEntityCodeSuggestion> source,
  String query, {
  int limit = 10,
}) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const <LampEntityCodeSuggestion>[];
  final normalizedQuery = SearchTextNormalizer.normalizeForSearch(trimmed);
  final compactQuery = trimmed.replaceAll(RegExp(r'\s+'), '');

  final matches = <LampEntityCodeSuggestion>[];
  for (final item in source) {
    final codeText = item.code.toString();
    final labelMatches = SearchTextNormalizer.matchesNormalizedQuery(
      item.label,
      normalizedQuery,
    );
    final codeMatches =
        compactQuery.isNotEmpty && codeText.contains(compactQuery);
    if (labelMatches || codeMatches) {
      matches.add(item);
      if (matches.length >= limit) break;
    }
  }
  return matches;
}
