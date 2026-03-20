import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../history/providers/history_provider.dart';
import '../../provider/call_entry_provider.dart';

/// Πεδίο αυτόματης συμπλήρωσης κατηγορίας (πίνακας categories) με δυνατότητα προσθήκης νέας.
class CategoryAutocompleteField extends ConsumerStatefulWidget {
  const CategoryAutocompleteField({
    super.key,
    required this.onCategorySelected,
  });

  final ValueChanged<String> onCategorySelected;

  @override
  ConsumerState<CategoryAutocompleteField> createState() =>
      _CategoryAutocompleteFieldState();
}

class _CategoryAutocompleteFieldState
    extends ConsumerState<CategoryAutocompleteField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  int _keyboardOptionIndex = -1;
  bool _suppressOptionsUntilTyping = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<String> _sortedOptions(List<String> all, String query) {
    final q = query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? List<String>.from(all)
        : all
            .where(
              (c) => c.toLowerCase().contains(q),
            )
            .toList();
    filtered.sort(
      (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
    );
    return filtered;
  }

  void _setControllerText(TextEditingController controller, String value) {
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _onAddNew(String raw) async {
    final value = raw.trim();
    if (value.isEmpty) return;
    try {
      await DatabaseHelper.instance.insertCategoryAndGetId(value);
      if (!mounted) return;
      ref.invalidate(historyCategoriesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Η κατηγορία "$value" προστέθηκε'),
        ),
      );
      _controller.text = value;
      _controller.selection = TextSelection.collapsed(offset: value.length);
      _keyboardOptionIndex = -1;
      widget.onCategorySelected(value);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Αποτυχία προσθήκης: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncCats = ref.watch(historyCategoriesProvider);
    final allCategories =
        asyncCats.hasValue ? asyncCats.value! : <String>[];
    final categoriesReady = asyncCats.hasValue;

    final entryCategory = ref.watch(callEntryProvider).category;
    // Μετά από επιτυχή υποβολή το state καθαρίζει την κατηγορία· ευθυγράμμιση πεδίου.
    if (entryCategory.isEmpty && _controller.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.clear();
      });
    }

    final trimmed = _controller.text.trim();
    final showAdd = categoriesReady &&
        trimmed.isNotEmpty &&
        !allCategories.contains(trimmed);
    final hasText = _controller.text.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Ίδιο πλάτος με [NotesStickyField]: εσωτερικό max 400 / διαθέσιμο + padding 12×2.
        final maxInner = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? math.min(400.0, constraints.maxWidth)
            : 400.0;
        final notesOuterWidth = maxInner + 24;

        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: notesOuterWidth,
            child: RawAutocomplete<String>(
              focusNode: _focusNode,
              textEditingController: _controller,
              displayStringForOption: (option) => option,
              optionsBuilder: (TextEditingValue tev) {
                final options = _sortedOptions(allCategories, tev.text);
                final blocked =
                    _suppressOptionsUntilTyping &&
                    tev.text.trim() == _controller.text.trim();
                return blocked ? const Iterable<String>.empty() : options;
              },
              onSelected: (String selection) {
                setState(() {
                  _keyboardOptionIndex = -1;
                  _suppressOptionsUntilTyping = true;
                });
                widget.onCategorySelected(selection);
              },
              fieldViewBuilder: (
                BuildContext context,
                TextEditingController textEditingController,
                FocusNode focusNode,
                VoidCallback onFieldSubmitted,
              ) {
                return Focus(
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) {
                      return KeyEventResult.ignored;
                    }
                    final options = _sortedOptions(
                      allCategories,
                      textEditingController.text,
                    );
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      if (options.isEmpty) return KeyEventResult.ignored;
                      setState(() {
                        _keyboardOptionIndex =
                            (_keyboardOptionIndex + 1).clamp(
                              0,
                              options.length - 1,
                            );
                      });
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      if (options.isEmpty) return KeyEventResult.ignored;
                      setState(() {
                        _keyboardOptionIndex =
                            _keyboardOptionIndex <= 0
                                ? 0
                                : _keyboardOptionIndex - 1;
                      });
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.enter &&
                        options.isNotEmpty &&
                        _keyboardOptionIndex >= 0 &&
                        _keyboardOptionIndex < options.length) {
                      final selected = options[_keyboardOptionIndex];
                      setState(() {
                        _suppressOptionsUntilTyping = true;
                      });
                      _setControllerText(textEditingController, selected);
                      widget.onCategorySelected(selected);
                      _keyboardOptionIndex = -1;
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: 'Κατηγορία προβλήματος',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: (!hasText && !showAdd)
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hasText)
                                  IconButton(
                                    icon: Icon(
                                      Icons.close,
                                      color: Colors.red.shade300,
                                    ),
                                    tooltip: 'Διαγραφή',
                                    onPressed: () {
                                      textEditingController.clear();
                                      setState(() {
                                        _keyboardOptionIndex = -1;
                                      });
                                      widget.onCategorySelected('');
                                    },
                                  ),
                                if (showAdd)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.add_circle,
                                      color: Colors.green,
                                    ),
                                    tooltip: 'Προσθήκη κατηγορίας',
                                    onPressed: () =>
                                        _onAddNew(textEditingController.text),
                                  ),
                              ],
                            ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _keyboardOptionIndex = -1;
                        _suppressOptionsUntilTyping = false;
                      });
                      widget.onCategorySelected(value);
                    },
                    onSubmitted: (value) {
                      final options = _sortedOptions(allCategories, value);
                      if (options.isNotEmpty &&
                          _keyboardOptionIndex >= 0 &&
                          _keyboardOptionIndex < options.length) {
                        final selected = options[_keyboardOptionIndex];
                        setState(() {
                          _suppressOptionsUntilTyping = true;
                        });
                        _setControllerText(textEditingController, selected);
                        widget.onCategorySelected(selected);
                        setState(() {
                          _keyboardOptionIndex = -1;
                        });
                        return;
                      }
                      onFieldSubmitted();
                      widget.onCategorySelected(value.trim());
                    },
                  ),
                );
              },
              optionsViewBuilder: (
                BuildContext context,
                AutocompleteOnSelected<String> onSelected,
                Iterable<String> options,
              ) {
                final opts = options.toList();
                if (opts.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 220,
                        minWidth: 200,
                      ),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: opts.length,
                        itemBuilder: (context, index) {
                          final option = opts[index];
                          final isActive = _keyboardOptionIndex == index;
                          return ColoredBox(
                            color: isActive
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer
                                : Colors.transparent,
                            child: ListTile(
                              dense: true,
                              title: Text(option),
                              onTap: () {
                                setState(() {
                                  _keyboardOptionIndex = -1;
                                  _suppressOptionsUntilTyping = true;
                                });
                                onSelected(option);
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
