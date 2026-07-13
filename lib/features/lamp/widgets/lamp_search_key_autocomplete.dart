import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/lamp_search_controller.dart';
import '../controllers/lamp_search_query_parser.dart';

const String kLampGlobalSearchSyntaxTooltip =
    'Σύνταξη στοχευμένης αναζήτησης: κλειδί:τιμή\n'
    'Παραδείγματα:\n'
    '• κατηγορία:υπολογιστής\n'
    '• τμήμα:"Ιατρική Υπηρεσία"\n'
    '• ip:10.10';

/// Πεδίο καθολικής αναζήτησης με autocomplete κλειδιών και tooltip σύνταξης.
class LampSearchKeyAutocomplete extends StatefulWidget {
  const LampSearchKeyAutocomplete({
    super.key,
    required this.search,
    required this.onSubmitted,
    this.width,
  });

  final LampSearchController search;
  final VoidCallback onSubmitted;
  final double? width;

  @override
  State<LampSearchKeyAutocomplete> createState() =>
      _LampSearchKeyAutocompleteState();
}

class _LampSearchKeyAutocompleteState extends State<LampSearchKeyAutocomplete> {
  final LayerLink _layerLink = LayerLink();
  final FocusNode _focusNode = FocusNode();
  OverlayEntry? _overlayEntry;
  List<String> _suggestions = const <String>[];
  int _selectedIndex = 0;

  TextEditingController get _controller => widget.search.globalController;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    // Ο χειριστής πλήκτρων ζει πάνω στο ίδιο το FocusNode του TextField,
    // ώστε το requestFocus μετά από επιλογή πρότασης να επιστρέφει την
    // εστίαση ΜΕΣΑ στο πεδίο (όχι σε εξωτερικό Focus widget).
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
    _removeOverlay();
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _removeOverlay();
    } else {
      _refreshSuggestions();
    }
  }

  void _onTextChanged() {
    _refreshSuggestions();
  }

  String? _currentPiece() {
    final text = _controller.text;
    final selection = _controller.selection;
    if (!selection.isValid) return null;
    final cursor = selection.baseOffset.clamp(0, text.length);
    final beforeCursor = text.substring(0, cursor);
    final colonIndex = beforeCursor.lastIndexOf(':');
    if (colonIndex != -1) {
      final afterColon = beforeCursor.substring(colonIndex + 1);
      if (!afterColon.contains(' ')) return null;
    }
    final lastSpace = beforeCursor.lastIndexOf(' ');
    final piece = beforeCursor.substring(lastSpace + 1);
    if (piece.contains(':') || piece.trim().isEmpty) return null;
    return piece;
  }

  void _refreshSuggestions() {
    if (!_focusNode.hasFocus) {
      _removeOverlay();
      return;
    }
    final piece = _currentPiece();
    if (piece == null) {
      _removeOverlay();
      return;
    }
    final suggestions = LampSearchQueryParser.suggestKeys(piece);
    if (suggestions.isEmpty) {
      _removeOverlay();
      return;
    }
    setState(() {
      _suggestions = suggestions;
      _selectedIndex = 0;
    });
    _showOverlay();
  }

  void _showOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: widget.width ?? 320,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 52),
            // Χωρίς αυτό, το πάτημα σε πρόταση μετράει ως «κλικ εκτός
            // πεδίου» στα Windows: το πεδίο χάνει το focus και το overlay
            // σβήνει πριν ολοκληρωθεί το κλικ.
            child: TextFieldTapRegion(
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    itemBuilder: (context, index) {
                      final key = _suggestions[index];
                      final selected = index == _selectedIndex;
                      final scheme = Theme.of(context).colorScheme;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        selectedTileColor: scheme.primaryContainer,
                        selectedColor: scheme.onPrimaryContainer,
                        title: Text(
                          key,
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
                        onTap: () => _applySuggestion(key),
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

  void _applySuggestion(String key) {
    final text = _controller.text;
    final selection = _controller.selection;
    final cursor = selection.isValid
        ? selection.baseOffset.clamp(0, text.length)
        : text.length;
    final beforeCursor = text.substring(0, cursor);
    final afterCursor = text.substring(cursor);
    final lastSpace = beforeCursor.lastIndexOf(' ');
    final pieceStart = lastSpace + 1;
    final newText = '${text.substring(0, pieceStart)}$key:$afterCursor';
    final newCursor = pieceStart + key.length + 1;
    widget.search.suppressLiveSearch = true;
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
    widget.search.suppressLiveSearch = false;
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
    final field = TextField(
      focusNode: _focusNode,
      controller: _controller,
      decoration: InputDecoration(
        labelText: 'Καθολική Αναζήτηση',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: widget.search.clearFieldSuffix(
          controller: _controller,
          tooltip: 'Καθαρισμός καθολικής αναζήτησης',
        ),
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (_) => widget.onSubmitted(),
    );

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, right: 4),
          child: Tooltip(
            waitDuration: const Duration(milliseconds: 300),
            showDuration: const Duration(seconds: 10),
            message: kLampGlobalSearchSyntaxTooltip,
            child: Icon(
              Icons.info_outline,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: CompositedTransformTarget(link: _layerLink, child: field),
        ),
      ],
    );

    if (widget.width == null) return row;
    return SizedBox(width: widget.width, child: row);
  }
}
