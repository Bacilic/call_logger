import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/lookup_service.dart';
import '../../../../core/utils/autocomplete_highlight_scroll.dart';
import '../../../../core/utils/spell_check.dart';
import '../../../../features/directory/models/department_model.dart';
import '../../provider/smart_entity_selector_provider.dart';
import 'smart_entity_selector_conflict_badge.dart';
import 'text_layout_utils.dart';
class SmartEntityDepartmentField extends StatefulWidget {
  const SmartEntityDepartmentField({
    super.key,
    required this.width,
    required this.controller,
    required this.focusNode,
    required this.nextFocusNode,
    required this.header,
    required this.lookupService,
    required this.notifier,
    required this.onContentChecked,
  });

  final double width;
  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode nextFocusNode;
  final SmartEntitySelectorState header;
  final LookupService? lookupService;
  final SmartEntitySelectorNotifier notifier;
  final VoidCallback onContentChecked;

  @override
  State<SmartEntityDepartmentField> createState() => SmartEntityDepartmentFieldState();
}

class SmartEntityDepartmentFieldState extends State<SmartEntityDepartmentField> {
  bool _isKeyboardPreview = false;
  int _keyboardOptionIndex = -1;
  int _lastAutoScrollIndex = -1;
  String _typedQuery = '';
  final ScrollController _optionsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _typedQuery = widget.controller.text;
    widget.controller.addListener(_onDepartmentTextChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onDepartmentTextChange);
    _optionsScrollController.dispose();
    super.dispose();
  }

  void _onDepartmentTextChange() {
    if (_isKeyboardPreview) {
      if (mounted) setState(() {});
      return;
    }
    final currentText = widget.controller.text;
    if (_typedQuery != currentText) {
      _typedQuery = currentText;
    }
    if (currentText.trim().isEmpty) {
      _keyboardOptionIndex = -1;
      _lastAutoScrollIndex = -1;
    }
    if (mounted) setState(() {});
  }

  List<DepartmentModel> _departmentOptions(String query) {
    final lookupService = widget.lookupService;
    if (lookupService == null) return const <DepartmentModel>[];
    return lookupService.searchDepartments(query.trim());
  }

  void _setControllerText(TextEditingController controller, String value) {
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _commitDepartmentSelection(DepartmentModel selection) {
    _keyboardOptionIndex = -1;
    _lastAutoScrollIndex = -1;
    _isKeyboardPreview = false;
    _setControllerText(widget.controller, selection.name);
    widget.notifier.selectDepartment(selection);
    widget.onContentChecked();
    widget.nextFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textDirection = Directionality.of(context);
    final width = widget.width;
    final controller = widget.controller;
    final focusNode = widget.focusNode;
    final notifier = widget.notifier;
    final onContentChecked = widget.onContentChecked;
    final nextFocusNode = widget.nextFocusNode;
    final lookupService = widget.lookupService;
    return SizedBox(
      width: widget.width,
      child: MergeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.business_outlined,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Τμήμα',
                    style: theme.textTheme.labelMedium,
                    softWrap: true,
                  ),
                ),
                ConflictBadge(
                  severity: widget.header
                      .conflictSeverityFor(SelectorField.department),
                  message: widget.header
                      .conflictTooltipFor(SelectorField.department),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Autocomplete<DepartmentModel>(
              displayStringForOption: (DepartmentModel d) => d.name,
              focusNode: focusNode,
              textEditingController: controller,
              optionsBuilder: (TextEditingValue value) {
                final effectiveText = _isKeyboardPreview
                    ? _typedQuery
                    : value.text;
                final query = effectiveText.trim();
                if (lookupService == null) return const [];
                return lookupService.searchDepartments(query);
              },
              optionsViewBuilder: (context, onSelected, options) {
                final optionsList = options.toList();
                final theme = Theme.of(context);
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    color: theme.colorScheme.surface,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 240,
                        minWidth: 180,
                      ),
                      child: ListView.builder(
                        controller: _optionsScrollController,
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: optionsList.length,
                        itemBuilder: (context, index) {
                          final frameworkHighlighted =
                              AutocompleteHighlightedOption.of(context) ==
                              index;
                          final keyboardHighlighted =
                              _keyboardOptionIndex >= 0 &&
                              _keyboardOptionIndex == index;
                          final isHighlighted = _isKeyboardPreview
                              ? keyboardHighlighted
                              : frameworkHighlighted;
                          if (isHighlighted && _isKeyboardPreview) {
                            if (_lastAutoScrollIndex != index) {
                              _lastAutoScrollIndex = index;
                              syncAutocompleteHighlightedListScroll(
                                controller: _optionsScrollController,
                                highlightedIndex: index,
                                itemExtent: 48,
                                viewportExtent: 240,
                              );
                            }
                          }
                          return ListTile(
                            dense: true,
                            selected: isHighlighted,
                            selectedTileColor: theme.colorScheme.primary
                                .withValues(alpha: 0.12),
                            title: Text(optionsList[index].name),
                            onTap: () => onSelected(optionsList[index]),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
              onSelected: (DepartmentModel selection) {
                _commitDepartmentSelection(selection);
              },
              fieldViewBuilder:
                  (context, textController, focusNodeParam, onFieldSubmitted) {
                    final style =
                        theme.textTheme.bodyLarge ?? const TextStyle();
                    final showTooltip =
                        !focusNodeParam.hasFocus &&
                        textOverflowsSingleLine(
                          text: textController.text,
                          style: style,
                          maxWidth: width - 88,
                          textDirection: textDirection,
                        );
                    final field = Focus(
                      onKeyEvent: (node, event) {
                        if (event is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }
                        final options = _departmentOptions(_typedQuery);
                        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          if (options.isEmpty) return KeyEventResult.ignored;
                          _keyboardOptionIndex = (_keyboardOptionIndex + 1)
                              .clamp(0, options.length - 1);
                          _isKeyboardPreview = true;
                          _setControllerText(
                            textController,
                            options[_keyboardOptionIndex].name,
                          );
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                          if (options.isEmpty) return KeyEventResult.ignored;
                          _keyboardOptionIndex = _keyboardOptionIndex <= 0
                              ? 0
                              : _keyboardOptionIndex - 1;
                          _isKeyboardPreview = true;
                          _setControllerText(
                            textController,
                            options[_keyboardOptionIndex].name,
                          );
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.enter &&
                            options.isNotEmpty &&
                            _keyboardOptionIndex >= 0 &&
                            _keyboardOptionIndex < options.length) {
                          _commitDepartmentSelection(
                            options[_keyboardOptionIndex],
                          );
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: textController,
                        focusNode: focusNodeParam,
                        spellCheckConfiguration: platformSpellCheckConfiguration,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: showInlineFieldClearButton(
                            textController.text,
                          )
                              ? Semantics(
                                  label: 'Καθαρισμός Τμήματος',
                                  child: IconButton(
                                    icon: const Icon(Icons.close, size: 20),
                                    onPressed: () {
                                      textController.clear();
                                      _typedQuery = '';
                                      _keyboardOptionIndex = -1;
                                      notifier.updateDepartmentText('');
                                      onContentChecked();
                                    },
                                    tooltip: 'Καθαρισμός Τμήματος',
                                  ),
                                )
                              : null,
                        ),
                        onChanged: (value) {
                          if (_isKeyboardPreview) {
                            _isKeyboardPreview = false;
                            return;
                          }
                          _typedQuery = value;
                          _keyboardOptionIndex = -1;
                          _lastAutoScrollIndex = -1;
                          notifier.updateDepartmentText(value);
                          onContentChecked();
                        },
                        onSubmitted: (_) {
                          final options = _departmentOptions(_typedQuery);
                          if (options.isNotEmpty &&
                              _keyboardOptionIndex >= 0 &&
                              _keyboardOptionIndex < options.length) {
                            _commitDepartmentSelection(
                              options[_keyboardOptionIndex],
                            );
                            return;
                          }
                          onContentChecked();
                          nextFocusNode.requestFocus();
                        },
                      ),
                    );
                    return Semantics(
                      label: 'Τμήμα',
                      child: SizedBox(
                        width: width,
                        child: showTooltip
                            ? Tooltip(
                                message: textController.text,
                                child: field,
                              )
                            : field,
                      ),
                    );
                  },
            ),
          ],
        ),
      ),
    );
  }
}

