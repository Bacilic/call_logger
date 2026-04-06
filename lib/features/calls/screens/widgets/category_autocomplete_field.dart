import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/utils/spell_check.dart';
import '../../../history/providers/history_provider.dart';
import '../../provider/call_entry_provider.dart';

/// Επιστρέφει ενεργή κατηγορία αν το [text] ταιριάζει normalized, αλλιώς null.
({int id, String name})? categoryEntryMatchingNormalized(
  String text,
  List<({int id, String name})> entries,
) {
  final key = DatabaseHelper.normalizeCategoryNameForLookup(text.trim());
  if (key.isEmpty) return null;
  for (final e in entries) {
    if (DatabaseHelper.normalizeCategoryNameForLookup(e.name) == key) {
      return e;
    }
  }
  return null;
}

/// Πεδίο αυτόματης συμπλήρωσης κατηγορίας (`categories`) με `category_id` όταν ταιριάζει.
class CategoryAutocompleteField extends ConsumerStatefulWidget {
  const CategoryAutocompleteField({
    super.key,
    required this.onCategoryChanged,
  });

  final void Function(String text, int? categoryId) onCategoryChanged;

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
  bool _suppressCategoryNotify = false;

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
    _suppressCategoryNotify = true;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _suppressCategoryNotify = false;
  }

  void _pushCategoryState(String rawText, List<({int id, String name})> entries) {
    if (_suppressCategoryNotify) return;
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      widget.onCategoryChanged('', null);
      return;
    }
    final m = categoryEntryMatchingNormalized(rawText, entries);
    if (m != null) {
      widget.onCategoryChanged(m.name, m.id);
    } else {
      widget.onCategoryChanged(rawText, null);
    }
  }

  Future<void> _onAddNew(String raw) async {
    final value = raw.trim();
    if (value.isEmpty) return;
    try {
      final insert = await DatabaseHelper.instance.insertCategoryAndGetId(value);
      final newId = insert.id;
      if (!mounted) return;
      ref.invalidate(historyCategoriesProvider);
      ref.invalidate(historyCategoryEntriesProvider);
      if (insert.restored) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(kCategoryRestoredFromDeletedUserMessage)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Η κατηγορία "$value" προστέθηκε'),
          ),
        );
      }
      _setControllerText(_controller, value);
      _keyboardOptionIndex = -1;
      widget.onCategoryChanged(value, newId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Αποτυχία προσθήκης: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncEntries = ref.watch(historyCategoryEntriesProvider);
    final entries = switch (asyncEntries) {
      AsyncData(:final value) => value,
      _ => const <({int id, String name})>[],
    };
    final allCategoryNames = entries.map((e) => e.name).toList();
    final categoriesReady = asyncEntries.hasValue;

    final entryCategory = ref.watch(callEntryProvider.select((s) => s.category));
    if (entryCategory.isEmpty && _controller.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.clear();
      });
    }

    final trimmed = _controller.text.trim();
    final showAdd = categoriesReady &&
        trimmed.isNotEmpty &&
        categoryEntryMatchingNormalized(trimmed, entries) == null;
    final hasText = _controller.text.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
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
                final options = _sortedOptions(allCategoryNames, tev.text);
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
                final m = categoryEntryMatchingNormalized(selection, entries);
                if (m != null) {
                  widget.onCategoryChanged(m.name, m.id);
                } else {
                  widget.onCategoryChanged(selection, null);
                }
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
                      allCategoryNames,
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
                      final m = categoryEntryMatchingNormalized(selected, entries);
                      if (m != null) {
                        widget.onCategoryChanged(m.name, m.id);
                      } else {
                        widget.onCategoryChanged(selected, null);
                      }
                      _keyboardOptionIndex = -1;
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    spellCheckConfiguration: platformSpellCheckConfiguration,
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
                                      widget.onCategoryChanged('', null);
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
                      final m = categoryEntryMatchingNormalized(value, entries);
                      if (m != null && value.trim() != m.name) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          _setControllerText(textEditingController, m.name);
                          widget.onCategoryChanged(m.name, m.id);
                        });
                        return;
                      }
                      _pushCategoryState(value, entries);
                    },
                    onSubmitted: (value) {
                      final options = _sortedOptions(allCategoryNames, value);
                      if (options.isNotEmpty &&
                          _keyboardOptionIndex >= 0 &&
                          _keyboardOptionIndex < options.length) {
                        final selected = options[_keyboardOptionIndex];
                        setState(() {
                          _suppressOptionsUntilTyping = true;
                        });
                        _setControllerText(textEditingController, selected);
                        final m = categoryEntryMatchingNormalized(selected, entries);
                        if (m != null) {
                          widget.onCategoryChanged(m.name, m.id);
                        } else {
                          widget.onCategoryChanged(selected, null);
                        }
                        setState(() {
                          _keyboardOptionIndex = -1;
                        });
                        return;
                      }
                      onFieldSubmitted();
                      _pushCategoryState(value.trim(), entries);
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
