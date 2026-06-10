import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/lookup_service.dart';
import '../../../../core/utils/autocomplete_highlight_scroll.dart';
import '../../../../core/utils/spell_check.dart';
import '../../provider/smart_entity_selector_provider.dart';
import 'smart_entity_selector_conflict_badge.dart';
import 'smart_entity_selector_overlay_utils.dart';
import 'smart_entity_selector_phone_suggestion_list.dart';
import 'smart_entity_selector_phone_utils.dart';
import 'text_layout_utils.dart';

/// Πεδίο Τηλέφωνο με overlay λίστα πολλαπλών candidates και Autocomplete για prefix αναζήτηση.
class SmartEntityPhoneField extends StatefulWidget {
  const SmartEntityPhoneField({
    super.key,
    required this.width,
    required this.controller,
    required this.focusNode,
    required this.nextFocusNode,
    required this.header,
    required this.lookupService,
    required this.notifier,
    required this.onLessThan2DigitsSubmit,
    required this.onClearAll,
    required this.onContentChecked,
    required this.onPhoneSubmitted,
    required this.onPhoneBecameEmpty,
    required this.onPhoneSelectedFromList,
  });

  final double width;
  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode nextFocusNode;
  final SmartEntitySelectorState header;
  final LookupService? lookupService;
  final SmartEntitySelectorNotifier notifier;
  final VoidCallback onLessThan2DigitsSubmit;
  final VoidCallback onClearAll;
  final VoidCallback onContentChecked;
  final VoidCallback onPhoneSubmitted;
  final VoidCallback onPhoneBecameEmpty;
  final ValueChanged<String> onPhoneSelectedFromList;

  @override
  State<SmartEntityPhoneField> createState() => _SmartEntityPhoneFieldState();
}

class _SmartEntityPhoneFieldState extends State<SmartEntityPhoneField> {
  bool _isSelectingFromList = false;
  bool _isKeyboardPreview = false;
  int _keyboardOptionIndex = -1;
  int _lastAutoScrollIndex = -1;
  String _typedQuery = '';
  bool _showSuggestionList = false;
  final ScrollController _optionsScrollController = ScrollController();
  final ScrollController _overlayScrollController = ScrollController();
  Timer? _debounce;
  final OverlayPortalController _suggestionOverlayController =
      OverlayPortalController();
  final LayerLink _phoneLayerLink = LayerLink();

  void _performLookup() {
    final digits = widget.controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 3) {
      widget.notifier.performPhoneLookup(digits);
      widget.notifier.markPhoneUsed(digits);
    }
  }

  void _scheduleCompletedLookup() {
    if (_isSelectingFromList) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      if (_isSelectingFromList) return;
      _performLookup();
    });
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {});
    }
    if (widget.focusNode.hasFocus) {
      setState(() => _showSuggestionList = true);
      return;
    }
    _keyboardOptionIndex = -1;
    _lastAutoScrollIndex = -1;
    _isKeyboardPreview = false;
    if (_isSelectingFromList) return;
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      if (widget.focusNode.hasFocus) return;
      setState(() => _showSuggestionList = false);
      _scheduleCompletedLookup();
    });
  }

  void _onPhoneChanged(String value) {
    if (_isSelectingFromList) return;
    if (_isKeyboardPreview) {
      _isKeyboardPreview = false;
      return;
    }
    _typedQuery = value;
    _keyboardOptionIndex = -1;
    _lastAutoScrollIndex = -1;
    _debounce?.cancel();
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    final headerPhone = widget.header.selectedPhone ?? '';
    if (digits != headerPhone) {
      widget.notifier.updatePhone(digits.isEmpty ? null : digits);
    }
    if (digits.isEmpty) {
      widget.onPhoneBecameEmpty();
    }
    // v2 §Ζ: το entity lookup ΔΕΝ τρέχει κατά την πληκτρολόγηση. Εκτελείται
    // μόνο σε commit (focus-out, Enter, επιλογή από λίστα). Η ζωντανή λίστα
    // autocomplete (prefix search) παραμένει ενεργή μέσω του optionsBuilder.
  }

  void _onPhoneTextChange() {
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
    if (!mounted) return;
    setState(() {
      if (widget.focusNode.hasFocus) {
        _showSuggestionList = true;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _showSuggestionList = widget.focusNode.hasFocus;
    _typedQuery = widget.controller.text;
    widget.focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onPhoneTextChange);
  }

  List<String> _phoneAutocompleteOptions(
    String query,
    SmartEntitySelectorState header,
    LookupService? lookupService,
  ) {
    final text = query.replaceAll(RegExp(r'[^0-9]'), '');
    if (header.phoneCandidates.isNotEmpty) {
      final candidates = sortPhonesByRecent(
        List<String>.from(header.phoneCandidates),
        header.recentPhones,
      );
      if (text.isEmpty) return candidates;
      return candidates.where((p) {
        final digits = p.replaceAll(RegExp(r'[^0-9]'), '');
        return digits.contains(text) || digits.startsWith(text);
      }).toList();
    }
    if (text.length < 2) return const <String>[];
    final list = lookupService?.searchPhonesByPrefix(text) ?? <String>[];
    return sortPhonesByRecent(list, header.recentPhones);
  }

  void _setControllerText(TextEditingController controller, String value) {
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _commitPhoneSelection({
    required String value,
    required TextEditingController controller,
    required FocusNode focusNode,
    required FocusNode nextFocusNode,
    required SmartEntitySelectorState header,
    required SmartEntitySelectorNotifier notifier,
    required VoidCallback onContentChecked,
  }) {
    setState(() {
      _isSelectingFromList = true;
      _showSuggestionList = false;
      _keyboardOptionIndex = -1;
      _lastAutoScrollIndex = -1;
      _isKeyboardPreview = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setControllerText(controller, value);
      notifier.updatePhone(value.replaceAll(RegExp(r'[^0-9]'), ''));
      notifier.setPhone(value);
      final fromCandidates = header.phoneCandidates.contains(value);
      if (fromCandidates) {
        notifier.selectPhoneFromCandidates(value);
      } else {
        notifier.markPhoneUsed(value);
        notifier.performPhoneLookup(value.replaceAll(RegExp(r'[^0-9]'), ''));
      }
      widget.onPhoneSelectedFromList(value);
      onContentChecked();
      if (focusNode.hasFocus) {
        nextFocusNode.requestFocus();
      }
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) setState(() => _isSelectingFromList = false);
      });
    });
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
    _debounce?.cancel();
    _optionsScrollController.dispose();
    _overlayScrollController.dispose();
    widget.focusNode.removeListener(_onFocusChange);
    widget.controller.removeListener(_onPhoneTextChange);
    super.dispose();
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
    final onLessThan2DigitsSubmit = widget.onLessThan2DigitsSubmit;
    final onClearAll = widget.onClearAll;
    final onContentChecked = widget.onContentChecked;
    final showPhoneCandidates =
        header.phoneCandidates.isNotEmpty &&
        _showSuggestionList &&
        (controller.text.trim().isEmpty || _isKeyboardPreview);
    scheduleOverlayPortalVisibility(
      _suggestionOverlayController,
      showPhoneCandidates,
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.phone_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Τηλέφωνο',
                    style: Theme.of(context).textTheme.labelMedium,
                    softWrap: true,
                  ),
                ),
                ConflictBadge(
                  severity:
                      widget.header.conflictSeverityFor(SelectorField.phone),
                  message:
                      widget.header.conflictTooltipFor(SelectorField.phone),
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
                    link: _phoneLayerLink,
                    showWhenUnlinked: false,
                    targetAnchor: Alignment.bottomLeft,
                    followerAnchor: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      child: SmartEntityPhoneSuggestionList(
                        phones: sortPhonesByRecent(
                          List<String>.from(header.phoneCandidates),
                          header.recentPhones,
                        ),
                        highlightedIndex: _keyboardOptionIndex,
                        scrollController: _overlayScrollController,
                        onSelected: (value) {
                          setState(() {
                            _isSelectingFromList = true;
                            _showSuggestionList = false;
                          });
                          notifier.selectPhoneFromCandidates(value);
                          focusNode.requestFocus();
                          widget.onPhoneSelectedFromList(value);
                          Future.delayed(const Duration(milliseconds: 300), () {
                            if (mounted) {
                              setState(() {
                                _isSelectingFromList = false;
                              });
                            }
                          });
                        },
                      ),
                    ),
                  ),
                );
              },
              child: CompositedTransformTarget(
                link: _phoneLayerLink,
                child: Autocomplete<String>(
                  focusNode: focusNode,
                  textEditingController: controller,
                  optionsBuilder: (value) {
                    final effectiveText =
                        _isKeyboardPreview ? _typedQuery : value.text;
                    final text =
                        effectiveText.replaceAll(RegExp(r'[^0-9]'), '');
                    if (header.phoneCandidates.isNotEmpty) {
                      final candidates = sortPhonesByRecent(
                        List<String>.from(header.phoneCandidates),
                        header.recentPhones,
                      );
                      if (text.isEmpty) return const Iterable<String>.empty();
                      return candidates.where((p) {
                        final digits = p.replaceAll(RegExp(r'[^0-9]'), '');
                        return digits.contains(text) || digits.startsWith(text);
                      });
                    }
                    if (text.length < 2) return const Iterable<String>.empty();
                    final list =
                        lookupService?.searchPhonesByPrefix(text) ?? [];
                    return sortPhonesByRecent(list, header.recentPhones);
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
                            minWidth: 160,
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
                                title: Text(optionsList[index]),
                                onTap: () => onSelected(optionsList[index]),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                  onSelected: (value) {
                    _commitPhoneSelection(
                      value: value,
                      controller: controller,
                      focusNode: focusNode,
                      nextFocusNode: nextFocusNode,
                      header: header,
                      notifier: notifier,
                      onContentChecked: onContentChecked,
                    );
                  },
                  fieldViewBuilder: (
                    context,
                    textController,
                    focusNodeParam,
                    onFieldSubmitted,
                  ) {
                    return Semantics(
                      label: 'Αριθμός τηλεφώνου',
                      child: Focus(
                        onKeyEvent: (node, event) {
                          if (event is! KeyDownEvent) {
                            return KeyEventResult.ignored;
                          }
                          final phoneCandidatesVisible =
                              header.phoneCandidates.isNotEmpty &&
                              _showSuggestionList &&
                              (controller.text.trim().isEmpty ||
                                  _isKeyboardPreview);
                          if (phoneCandidatesVisible) {
                            final overlayPhones = sortPhonesByRecent(
                              List<String>.from(header.phoneCandidates),
                              header.recentPhones,
                            );
                            if (event.logicalKey ==
                                LogicalKeyboardKey.arrowDown) {
                              if (overlayPhones.isEmpty) {
                                return KeyEventResult.ignored;
                              }
                              setState(() {
                                _keyboardOptionIndex =
                                    (_keyboardOptionIndex + 1).clamp(
                                  0,
                                  overlayPhones.length - 1,
                                );
                              });
                              _isKeyboardPreview = true;
                              _setControllerText(
                                textController,
                                overlayPhones[_keyboardOptionIndex],
                              );
                              return KeyEventResult.handled;
                            }
                            if (event.logicalKey ==
                                LogicalKeyboardKey.arrowUp) {
                              if (overlayPhones.isEmpty) {
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
                                overlayPhones[_keyboardOptionIndex],
                              );
                              return KeyEventResult.handled;
                            }
                            if (event.logicalKey == LogicalKeyboardKey.enter &&
                                overlayPhones.isNotEmpty &&
                                _keyboardOptionIndex >= 0 &&
                                _keyboardOptionIndex < overlayPhones.length) {
                              _commitPhoneSelection(
                                value: overlayPhones[_keyboardOptionIndex],
                                controller: textController,
                                focusNode: focusNode,
                                nextFocusNode: nextFocusNode,
                                header: header,
                                notifier: notifier,
                                onContentChecked: onContentChecked,
                              );
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          }
                          final shouldHideInlineSuggestions =
                              event.logicalKey ==
                                  LogicalKeyboardKey.arrowDown ||
                              event.logicalKey == LogicalKeyboardKey.arrowUp ||
                              event.logicalKey == LogicalKeyboardKey.enter;
                          if (_showSuggestionList &&
                              shouldHideInlineSuggestions) {
                            setState(() => _showSuggestionList = false);
                          }
                          final options = _phoneAutocompleteOptions(
                            _typedQuery,
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
                              options[_keyboardOptionIndex],
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
                              options[_keyboardOptionIndex],
                            );
                            return KeyEventResult.handled;
                          }
                          if (event.logicalKey == LogicalKeyboardKey.enter &&
                              options.isNotEmpty &&
                              _keyboardOptionIndex >= 0 &&
                              _keyboardOptionIndex < options.length) {
                            _commitPhoneSelection(
                              value: options[_keyboardOptionIndex],
                              controller: textController,
                              focusNode: focusNode,
                              nextFocusNode: nextFocusNode,
                              header: header,
                              notifier: notifier,
                              onContentChecked: onContentChecked,
                            );
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: textController,
                          focusNode: focusNodeParam,
                          autofocus: true,
                          spellCheckConfiguration:
                              platformSpellCheckConfiguration,
                          decoration: InputDecoration(
                            hintStyle: TextStyle(
                              color: Theme.of(context).hintColor,
                            ),
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: showInlineFieldClearButton(
                              textController.text,
                            )
                                ? Semantics(
                                    label: 'Καθαρισμός Τηλεφώνου',
                                    child: IconButton(
                                      icon: const Icon(Icons.close, size: 20),
                                      onPressed: () {
                                        textController.clear();
                                        _typedQuery = '';
                                        _keyboardOptionIndex = -1;
                                        onClearAll();
                                      },
                                      tooltip: 'Καθαρισμός Τηλεφώνου',
                                    ),
                                  )
                                : null,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          keyboardType: TextInputType.number,
                          onChanged: _onPhoneChanged,
                          onSubmitted: (value) {
                            final options = _phoneAutocompleteOptions(
                              _typedQuery,
                              header,
                              lookupService,
                            );
                            if (options.isNotEmpty &&
                                _keyboardOptionIndex >= 0 &&
                                _keyboardOptionIndex < options.length) {
                              _commitPhoneSelection(
                                value: options[_keyboardOptionIndex],
                                controller: textController,
                                focusNode: focusNode,
                                nextFocusNode: nextFocusNode,
                                header: header,
                                notifier: notifier,
                                onContentChecked: onContentChecked,
                              );
                              return;
                            }
                            final digits = value.replaceAll(
                              RegExp(r'[^0-9]'),
                              '',
                            );
                            if (digits.length < 2) {
                              onLessThan2DigitsSubmit();
                              return;
                            }
                            onContentChecked();
                            widget.onPhoneSubmitted();
                            nextFocusNode.requestFocus();
                            _scheduleCompletedLookup();
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
