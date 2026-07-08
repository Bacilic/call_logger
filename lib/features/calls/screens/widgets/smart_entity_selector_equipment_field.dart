import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/lookup_service.dart';
import '../../../../core/utils/autocomplete_highlight_scroll.dart';
import '../../../../core/utils/spell_check.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import '../../models/equipment_model.dart';
import '../../provider/smart_entity_selector_provider.dart';
import '../../utils/vnc_remote_target.dart';
import 'smart_entity_equipment_initial_suggestions.dart';
import 'smart_entity_selector_equipment_models.dart';
import 'smart_entity_selector_equipment_suggestion_list.dart';
import 'smart_entity_selector_conflict_badge.dart';
import 'smart_entity_selector_overlay_utils.dart';
import 'text_layout_utils.dart';

/// Πεδίο κωδικού εξοπλισμού με overlay αρχικών προτάσεων και Autocomplete αναζήτησης.
class SmartEntityEquipmentField extends StatefulWidget {
  const SmartEntityEquipmentField({
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
  State<SmartEntityEquipmentField> createState() =>
      _SmartEntityEquipmentFieldState();
}

class _SmartEntityEquipmentFieldState extends State<SmartEntityEquipmentField> {
  bool _isSelectingEquipment = false;
  bool _showInitialList = false;
  bool _isKeyboardPreview = false;
  int _keyboardOptionIndex = -1;
  int _lastAutoScrollIndex = -1;
  String _typedQuery = '';
  final ScrollController _optionsScrollController = ScrollController();
  final ScrollController _overlayScrollController = ScrollController();
  final OverlayPortalController _suggestionOverlayController =
      OverlayPortalController();
  final LayerLink _equipmentLayerLink = LayerLink();
  List<SmartEntityEquipmentSuggestion> _lastInitialSuggestions = const [];
  bool _justSelectedFromCustomList = false;

  void _performLookup() {
    final query = widget.controller.text.trim();
    if (query.isEmpty) return;
    final selected = widget.header.selectedEquipment;
    // Αποφυγή περιττού lookup όταν το κείμενο ταιριάζει ήδη με την επιλεγμένη
    // οντότητα (v2 §Β: η τιμή του πεδίου είναι η αλήθεια).
    if (selected != null && query == _equipmentFieldText(selected)) {
      return;
    }
    widget.notifier.performEquipmentLookupByCode(query);
  }

  @override
  void initState() {
    super.initState();
    _showInitialList = widget.focusNode.hasFocus;
    _typedQuery = widget.controller.text;
    widget.focusNode.addListener(_onEquipmentFocusChange);
    widget.controller.addListener(_onEquipmentTextChange);
  }

  @override
  void reassemble() {
    super.reassemble();
    scheduleOverlayPortalVisibility(
      _suggestionOverlayController,
      false,
      isMounted: () => mounted,
    );
  }

  @override
  void dispose() {
    if (_suggestionOverlayController.isShowing) {
      _suggestionOverlayController.hide();
    }
    _optionsScrollController.dispose();
    _overlayScrollController.dispose();
    widget.focusNode.removeListener(_onEquipmentFocusChange);
    widget.controller.removeListener(_onEquipmentTextChange);
    super.dispose();
  }

  void _onEquipmentFocusChange() {
    if (widget.focusNode.hasFocus) {
      setState(() {
        _showInitialList = true;
      });
    } else {
      _keyboardOptionIndex = -1;
      _lastAutoScrollIndex = -1;
      _isKeyboardPreview = false;
      _performLookup();
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && !widget.focusNode.hasFocus) {
          setState(() {
            _showInitialList = false;
          });
        }
      });
    }
  }

  void _onEquipmentTextChange() {
    if (!mounted) return;
    setState(() {
      if (widget.focusNode.hasFocus) {
        _showInitialList = true;
      }
    });
  }

  String _equipmentKey(EquipmentModel equipment) {
    final code = equipment.code?.trim() ?? '';
    if (code.isNotEmpty) {
      return code;
    }
    return equipment.displayLabel.trim();
  }

  List<EquipmentModel> _dedupeEquipments(Iterable<EquipmentModel> list) {
    final seen = <String>{};
    final result = <EquipmentModel>[];
    for (final equipment in list) {
      if (seen.add(_equipmentKey(equipment))) {
        result.add(equipment);
      }
    }
    return result;
  }

  List<SmartEntityEquipmentSuggestion> _initialSuggestions(
    SmartEntitySelectorState header,
    LookupService? lookupService,
  ) {
    return buildInitialEquipmentSuggestions(header, lookupService);
  }

  List<EquipmentModel> _querySuggestions(
    SmartEntitySelectorState header,
    LookupService? lookupService,
    String query,
  ) {
    final normalized = SearchTextNormalizer.normalizeForSearch(query);
    if (normalized.isEmpty || lookupService == null) {
      return const [];
    }
    return _dedupeEquipments(lookupService.findEquipmentsByCode(query));
  }

  List<EquipmentModel> _equipmentKeyboardOptions(
    SmartEntitySelectorState header,
    LookupService? lookupService,
  ) {
    if (_typedQuery.trim().isEmpty &&
        _showInitialList &&
        widget.controller.text.trim().isEmpty &&
        _lastInitialSuggestions.isNotEmpty) {
      return _lastInitialSuggestions
          .map((suggestion) => suggestion.equipment)
          .toList();
    }
    return _querySuggestions(header, lookupService, _typedQuery);
  }

  static String _equipmentFieldText(EquipmentModel e) =>
      e.code?.trim().isNotEmpty == true ? e.code!.trim() : e.displayLabel;

  void _selectEquipment(
    EquipmentModel equipment, {
    bool fromCustomList = false,
  }) {
    _isSelectingEquipment = true;
    if (fromCustomList) _justSelectedFromCustomList = true;
    final fieldText = _equipmentFieldText(equipment);
    _setControllerText(widget.controller, fieldText);
    widget.notifier.setEquipment(equipment);
    widget.notifier.checkContent(equipmentText: fieldText);
    widget.notifier.performEquipmentLookupByCode(fieldText);
    setState(() {
      _showInitialList = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _isSelectingEquipment = false;
        if (fromCustomList) _justSelectedFromCustomList = false;
      }
    });
  }

  void _setControllerText(TextEditingController controller, String value) {
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  void didUpdateWidget(covariant SmartEntityEquipmentField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onEquipmentFocusChange);
      widget.focusNode.addListener(_onEquipmentFocusChange);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onEquipmentTextChange);
      widget.controller.addListener(_onEquipmentTextChange);
    }
    final sel = widget.header.selectedEquipment;
    // v2 §Β: συμπληρώνουμε το ορατό κείμενο από την επιλογή μόνο όταν το πεδίο
    // είναι κενό· ποτέ δεν αντικαθιστούμε κείμενο που έχει ήδη ο χρήστης.
    if (sel != null &&
        widget.controller.text.trim().isEmpty &&
        _equipmentFieldText(sel).isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _setControllerText(widget.controller, _equipmentFieldText(sel));
        }
      });
    }
    if (sel == null &&
        oldWidget.header.selectedEquipment != null &&
        !_isSelectingEquipment &&
        !_justSelectedFromCustomList &&
        widget.header.equipmentCandidates.length <= 1 &&
        widget.header.isEquipmentAmbiguous == false) {
      // v2 §Β: μη καθαρίζεις ορατό κείμενο που έχει ήδη ο χρήστης (isFilled).
      final manualText = widget.header.equipmentText.trim();
      if (manualText.isNotEmpty) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.controller.clear();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.width;
    final controller = widget.controller;
    final focusNode = widget.focusNode;
    final nextFocusNode = widget.nextFocusNode;
    final header = widget.header;
    final lookupService = widget.lookupService;
    final notifier = widget.notifier;
    final theme = Theme.of(context);

    final hintText = header.equipmentNoMatch ? 'Καμία αντιστοιχία' : null;
    final initialSuggestions = _initialSuggestions(header, lookupService);
    _lastInitialSuggestions = initialSuggestions;
    final showInitialSuggestionList =
        _showInitialList &&
        (controller.text.trim().isEmpty || _isKeyboardPreview) &&
        initialSuggestions.isNotEmpty;
    scheduleOverlayPortalVisibility(
      _suggestionOverlayController,
      showInitialSuggestionList,
      isMounted: () => mounted,
    );

    return SizedBox(
      width: width,
      child: MergeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.computer_outlined,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'Κωδικός Εξοπλισμού',
                      style: theme.textTheme.labelMedium,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
                ConflictBadge(
                  severity: widget.header
                      .conflictSeverityFor(SelectorField.equipment),
                  message: widget.header
                      .conflictTooltipFor(SelectorField.equipment),
                ),
              ],
            ),
            const SizedBox(height: 4),
            OverlayPortal(
              controller: _suggestionOverlayController,
              overlayChildBuilder: (BuildContext overlayContext) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: CompositedTransformFollower(
                    link: _equipmentLayerLink,
                    showWhenUnlinked: false,
                    targetAnchor: Alignment.bottomLeft,
                    followerAnchor: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      child: SmartEntityEquipmentSuggestionList(
                        suggestions: initialSuggestions,
                        theme: theme,
                        highlightedIndex: _keyboardOptionIndex,
                        scrollController: _overlayScrollController,
                        onSelected: (e) =>
                            _selectEquipment(e, fromCustomList: true),
                      ),
                    ),
                  ),
                );
              },
              child: CompositedTransformTarget(
                link: _equipmentLayerLink,
                child: Autocomplete<EquipmentModel>(
                  displayStringForOption: (e) => e.displayLabel,
                  focusNode: focusNode,
                  textEditingController: controller,
                  optionsBuilder: (value) {
                    final effectiveText =
                        _isKeyboardPreview ? _typedQuery : value.text;
                    return _querySuggestions(
                      header,
                      lookupService,
                      effectiveText,
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    final optionsList = options.toList();
                    final listTheme = Theme.of(context);
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        color: listTheme.colorScheme.surface,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: 260,
                            minWidth: 220,
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
                                    viewportExtent: 260,
                                  );
                                }
                              }
                              final label = optionsList[index].displayLabel;
                              return ListTile(
                                dense: true,
                                selected: isHighlighted,
                                selectedTileColor: listTheme.colorScheme.primary
                                    .withValues(alpha: 0.12),
                                title: Text(label),
                                onTap: () => onSelected(optionsList[index]),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                  onSelected: (value) {
                    _selectEquipment(value);
                    widget.onContentChecked();
                    nextFocusNode.requestFocus();
                  },
                  fieldViewBuilder: (
                    context,
                    textController,
                    focusNodeParam,
                    onFieldSubmitted,
                  ) {
                    return Semantics(
                      label: 'Κωδικός εξοπλισμού',
                      child: Focus(
                        onKeyEvent: (node, event) {
                          if (event is! KeyDownEvent) {
                            return KeyEventResult.ignored;
                          }
                          final equipmentOverlayVisible =
                              _showInitialList &&
                              (controller.text.trim().isEmpty ||
                                  _isKeyboardPreview) &&
                              _lastInitialSuggestions.isNotEmpty &&
                              (_typedQuery.trim().isEmpty ||
                                  _isKeyboardPreview);
                          if (equipmentOverlayVisible) {
                            final overlayEquipments = _lastInitialSuggestions
                                .map((suggestion) => suggestion.equipment)
                                .toList();
                            if (event.logicalKey ==
                                LogicalKeyboardKey.arrowDown) {
                              if (overlayEquipments.isEmpty) {
                                return KeyEventResult.ignored;
                              }
                              setState(() {
                                _keyboardOptionIndex =
                                    (_keyboardOptionIndex + 1).clamp(
                                  0,
                                  overlayEquipments.length - 1,
                                );
                              });
                              _isKeyboardPreview = true;
                              _setControllerText(
                                textController,
                                _equipmentFieldText(
                                  overlayEquipments[_keyboardOptionIndex],
                                ),
                              );
                              return KeyEventResult.handled;
                            }
                            if (event.logicalKey ==
                                LogicalKeyboardKey.arrowUp) {
                              if (overlayEquipments.isEmpty) {
                                return KeyEventResult.ignored;
                              }
                              setState(() {
                                _keyboardOptionIndex =
                                    _keyboardOptionIndex <= 0
                                    ? 0
                                    : _keyboardOptionIndex - 1;
                              });
                              _isKeyboardPreview = true;
                              _setControllerText(
                                textController,
                                _equipmentFieldText(
                                  overlayEquipments[_keyboardOptionIndex],
                                ),
                              );
                              return KeyEventResult.handled;
                            }
                            if (event.logicalKey == LogicalKeyboardKey.enter &&
                                overlayEquipments.isNotEmpty &&
                                _keyboardOptionIndex >= 0 &&
                                _keyboardOptionIndex <
                                    overlayEquipments.length) {
                              _selectEquipment(
                                overlayEquipments[_keyboardOptionIndex],
                                fromCustomList: true,
                              );
                              widget.onContentChecked();
                              nextFocusNode.requestFocus();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          }
                          final options = _equipmentKeyboardOptions(
                            header,
                            lookupService,
                          );
                          if (event.logicalKey ==
                              LogicalKeyboardKey.arrowDown) {
                            if (options.isEmpty) return KeyEventResult.ignored;
                            _keyboardOptionIndex = (_keyboardOptionIndex + 1)
                                .clamp(0, options.length - 1);
                            _isKeyboardPreview = true;
                            _setControllerText(
                              textController,
                              _equipmentFieldText(
                                options[_keyboardOptionIndex],
                              ),
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
                              _equipmentFieldText(
                                options[_keyboardOptionIndex],
                              ),
                            );
                            return KeyEventResult.handled;
                          }
                          if (event.logicalKey == LogicalKeyboardKey.enter &&
                              options.isNotEmpty &&
                              _keyboardOptionIndex >= 0 &&
                              _keyboardOptionIndex < options.length) {
                            _selectEquipment(options[_keyboardOptionIndex]);
                            widget.onContentChecked();
                            nextFocusNode.requestFocus();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: textController,
                          focusNode: focusNodeParam,
                          spellCheckConfiguration:
                              platformSpellCheckConfiguration,
                          inputFormatters: [
                            CommaToDotDecimalSeparatorFormatter(),
                          ],
                          decoration: InputDecoration(
                            hintText: hintText,
                            hintStyle: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: showInlineFieldClearButton(
                              textController.text,
                            )
                                ? Semantics(
                                    label: 'Καθαρισμός Εξοπλισμού',
                                    child: IconButton(
                                      icon: const Icon(Icons.close, size: 20),
                                      onPressed: () {
                                        textController.clear();
                                        _typedQuery = '';
                                        _keyboardOptionIndex = -1;
                                        notifier.clearEquipment();
                                      },
                                      tooltip: 'Καθαρισμός Εξοπλισμού',
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
                            if (value.trim().isEmpty) {
                              notifier.clearEquipment();
                              return;
                            }
                            if (_isSelectingEquipment) {
                              notifier.checkContent(equipmentText: value);
                              return;
                            }
                            final selected = header.selectedEquipment;
                            if (selected != null &&
                                value != _equipmentFieldText(selected)) {
                              notifier.clearEquipment();
                            }
                            notifier.checkContent(equipmentText: value);
                          },
                          onSubmitted: (_) {
                            final options = _equipmentKeyboardOptions(
                              header,
                              lookupService,
                            );
                            if (options.isNotEmpty &&
                                _keyboardOptionIndex >= 0 &&
                                _keyboardOptionIndex < options.length) {
                              _selectEquipment(options[_keyboardOptionIndex]);
                              widget.onContentChecked();
                              nextFocusNode.requestFocus();
                              return;
                            }
                            widget.onContentChecked();
                            nextFocusNode.requestFocus();
                            _performLookup();
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
