import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/lookup_service.dart';
import '../../../../core/utils/autocomplete_highlight_scroll.dart';
import '../../../../core/utils/spell_check.dart';
import '../../../../core/utils/name_parser.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import '../../models/user_model.dart';
import '../../provider/smart_entity_selector_provider.dart';
import 'smart_entity_selector_caller_presentational.dart' as caller_ui;
import 'smart_entity_selector_conflict_badge.dart';
import 'smart_entity_selector_overlay_utils.dart';
import 'text_layout_utils.dart';

class SmartEntityCallerField extends StatefulWidget {
  const SmartEntityCallerField({
    super.key,
    required this.width,
    required this.controller,
    required this.focusNode,
    required this.nextFocusNode,
    required this.header,
    required this.lookupService,
    required this.notifier,
    required this.getPhoneFieldDigits,
    required this.onContentChecked,
    this.onCallerFocusOut,
  });

  final double width;
  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode nextFocusNode;
  final SmartEntitySelectorState header;
  final LookupService? lookupService;
  final SmartEntitySelectorNotifier notifier;

  /// Ψηφία από το πεδίο τηλεφώνου (ίδια σειρά με το UI) για merge πριν το caller lookup.
  final String Function() getPhoneFieldDigits;
  final VoidCallback onContentChecked;
  final VoidCallback? onCallerFocusOut;

  @override
  State<SmartEntityCallerField> createState() => SmartEntityCallerFieldState();
}

class SmartEntityCallerFieldState extends State<SmartEntityCallerField> {
  /// Όταν true, η λίστα προτάσεων εμφανίζεται. Γίνεται false μόλις ο χρήστης επιλέξει από τη λίστα.
  bool _showSuggestionList = false;
  bool _isKeyboardPreview = false;
  int _keyboardOptionIndex = -1;
  int _lastAutoScrollIndex = -1;
  String _typedQuery = '';
  final ScrollController _optionsScrollController = ScrollController();
  Timer? _debounce;
  final OverlayPortalController _suggestionOverlayController =
      OverlayPortalController();
  final LayerLink _callerLayerLink = LayerLink();

  void _performLookup() {
    final query = widget.controller.text.trim();
    if (query.isEmpty || query == 'Άγνωστος') return;
    widget.notifier.performCallerLookup(query);
  }

  void _scheduleCompletedLookup() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _performLookup();
    });
  }

  String _extractDisplayName(String selection) {
    if (selection == 'Άγνωστος') return selection;
    return NameParserUtility.stripParentheticalSuffix(selection);
  }

  UserModel? _resolveSelectedUser(
    String selection,
    SmartEntitySelectorState header,
    LookupService? lookupService,
  ) {
    for (final user in header.callerCandidates) {
      if (user.fullNameWithDepartment == selection || user.name == selection) {
        return user;
      }
    }
    if (lookupService == null) {
      return null;
    }
    final displayName = _extractDisplayName(selection);
    final matches = lookupService.searchUsersByQuery(displayName).where((user) {
      return user.fullNameWithDepartment == selection ||
          user.name == displayName;
    }).toList();
    if (matches.isEmpty) {
      return null;
    }
    final exactFullName = matches.where((user) {
      return user.fullNameWithDepartment == selection;
    }).toList();
    if (exactFullName.isNotEmpty) {
      return exactFullName.first;
    }
    return matches.first;
  }

  @override
  void initState() {
    super.initState();
    _showSuggestionList = widget.focusNode.hasFocus;
    _typedQuery = widget.controller.text;
    widget.focusNode.addListener(_onCallerFocusChange);
    widget.controller.addListener(_onCallerTextChange);
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
    widget.focusNode.removeListener(_onCallerFocusChange);
    widget.controller.removeListener(_onCallerTextChange);
    super.dispose();
  }

  void _onCallerTextChange() {
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

  void _onCallerFocusChange() {
    if (widget.focusNode.hasFocus) {
      setState(() => _showSuggestionList = true);
    } else {
      _keyboardOptionIndex = -1;
      _lastAutoScrollIndex = -1;
      _isKeyboardPreview = false;
      // Καθυστέρηση κλεισίματος ώστε να προλάβει το onTap στη λίστα.
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && !widget.focusNode.hasFocus) {
          setState(() => _showSuggestionList = false);
        }
      });
      // v2 §Ζ: entity lookup σε focus-out (commit). Μόνο για ελεύθερο κείμενο
      // που δεν έχει ήδη επιλεγμένο καλούντα — ώστε να μη χαλάει ρητή επιλογή.
      if (widget.controller.text.trim().isNotEmpty &&
          widget.header.selectedCaller == null) {
        _scheduleCompletedLookup();
      }
      widget.onCallerFocusOut?.call();
    }
  }

  void _onSuggestionSelected() {
    setState(() => _showSuggestionList = false);
  }

  List<String> _callerOverlayKeyboardOptions(
    SmartEntitySelectorState header, {
    required bool showUnknownOption,
  }) {
    final callerDisplayName =
        header.selectedCaller?.name ??
        header.selectedCaller?.fullNameWithDepartment ??
        '';
    final options = <String>[];
    for (final user in header.callerCandidates) {
      final candidateName = (user.name ?? user.fullNameWithDepartment).trim();
      if (candidateName.isNotEmpty && candidateName != callerDisplayName) {
        options.add(user.fullNameWithDepartment);
      }
    }
    if (callerDisplayName.isNotEmpty) {
      options.add(callerDisplayName);
    }
    if (showUnknownOption) {
      options.add('Άγνωστος');
    }
    return options;
  }

  String _callerPreviewTextForSelection(
    String selection,
    SmartEntitySelectorState header,
    LookupService? lookupService,
  ) {
    if (selection == 'Άγνωστος') return selection;
    final foundUser = _resolveSelectedUser(selection, header, lookupService);
    if (foundUser != null && foundUser.name?.trim().isNotEmpty == true) {
      return foundUser.name!.trim();
    }
    return _extractDisplayName(selection);
  }

  List<String> _callerAutocompleteOptions(
    String rawQuery,
    SmartEntitySelectorState header,
    LookupService? lookupService,
  ) {
    final q = SearchTextNormalizer.normalizeForSearch(rawQuery);
    final options = <String>[];
    if (header.callerCandidates.isNotEmpty) {
      if (q.isEmpty) {
        for (final u in header.callerCandidates) {
          options.add(u.fullNameWithDepartment);
        }
      } else {
        for (final u in header.callerCandidates) {
          if (SearchTextNormalizer.matchesNormalizedQuery(
            u.fullNameWithDepartment,
            q,
          )) {
            options.add(u.fullNameWithDepartment);
          }
        }
      }
    } else {
      final users = q.isEmpty
          ? <UserModel>[]
          : (lookupService?.searchUsersByQuery(rawQuery.trim()) ?? []);
      for (final u in users) {
        options.add(u.fullNameWithDepartment);
      }
    }
    return options.where((option) {
      return SearchTextNormalizer.matchesNormalizedQuery(option, q);
    }).toList();
  }

  void _setControllerText(TextEditingController controller, String value) {
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _commitCallerSelection({
    required String selection,
    required TextEditingController controller,
    required FocusNode nextFocusNode,
    required SmartEntitySelectorState header,
    required LookupService? lookupService,
    required SmartEntitySelectorNotifier notifier,
    required String Function() getPhoneFieldDigits,
  }) {
    _keyboardOptionIndex = -1;
    _lastAutoScrollIndex = -1;
    _isKeyboardPreview = false;
    if (selection == 'Άγνωστος') {
      notifier.updateSelectedCaller(null);
      notifier.updateCallerDisplayText('Άγνωστος');
      _setControllerText(controller, 'Άγνωστος');
      _onSuggestionSelected();
    } else {
      final foundUser = _resolveSelectedUser(selection, header, lookupService);
      final displayName = foundUser?.name?.trim().isNotEmpty == true
          ? foundUser!.name!.trim()
          : _extractDisplayName(selection);
      if (foundUser != null) {
        notifier.updateSelectedCaller(foundUser);
      } else {
        notifier.clearCaller();
      }
      notifier.updateCallerDisplayText(displayName);
      _setControllerText(controller, displayName);
      notifier.performCallerLookup(
        displayName,
        phoneFieldDigits: getPhoneFieldDigits(),
      );
      _onSuggestionSelected();
    }
    widget.onContentChecked();
    nextFocusNode.requestFocus();
  }

  @override
  void didUpdateWidget(covariant SmartEntityCallerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onCallerFocusChange);
      widget.focusNode.addListener(_onCallerFocusChange);
    }
    final displayText = widget.header.callerDisplayText;
    if (!widget.focusNode.hasFocus &&
        displayText.isNotEmpty &&
        widget.controller.text != displayText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.controller.value = TextEditingValue(
            text: displayText,
            selection: TextSelection.collapsed(offset: displayText.length),
          );
        }
      });
    }
    if (!widget.focusNode.hasFocus &&
        displayText.isEmpty &&
        oldWidget.header.callerDisplayText.isNotEmpty &&
        widget.header.selectedCaller == null) {
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
    final textDirection = Directionality.of(context);

    final hintText = header.callerNoMatch ? 'Καμία αντιστοιχία' : null;

    final showCallerSuggestionOverlay =
        _showSuggestionList &&
        (controller.text.trim().isEmpty || _isKeyboardPreview);
    scheduleOverlayPortalVisibility(
      _suggestionOverlayController,
      showCallerSuggestionOverlay,
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
                  Icons.person_outline,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Καλούντας',
                    style: theme.textTheme.labelMedium,
                    softWrap: true,
                  ),
                ),
                ConflictBadge(
                  severity:
                      widget.header.conflictSeverityFor(SelectorField.caller),
                  message:
                      widget.header.conflictTooltipFor(SelectorField.caller),
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
                    link: _callerLayerLink,
                    showWhenUnlinked: false,
                    targetAnchor: Alignment.bottomLeft,
                    followerAnchor: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      child: SmartEntityCallerSuggestionList(
                        header: header,
                        notifier: notifier,
                        controller: controller,
                        theme: theme,
                        showUnknownOption: controller.text.trim().isEmpty,
                        getPhoneFieldDigits: widget.getPhoneFieldDigits,
                        highlightedIndex: _keyboardOptionIndex,
                        onSelectionCommitted: _onSuggestionSelected,
                      ),
                    ),
                  ),
                );
              },
              child: CompositedTransformTarget(
                link: _callerLayerLink,
                child: Autocomplete<String>(
                  displayStringForOption: (String option) => option,
                  focusNode: focusNode,
                  textEditingController: controller,
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    final effectiveText = _isKeyboardPreview
                        ? _typedQuery
                        : textEditingValue.text;
                    final q = SearchTextNormalizer.normalizeForSearch(
                      effectiveText,
                    );
                    final options = <String>[];
                    if (header.callerCandidates.isNotEmpty) {
                      // Σε κατάσταση πολλαπλών candidate από lookup (κενό query),
                      // χρησιμοποιούμε μόνο την inline λίστα για αποφυγή διπλού μηχανισμού λίστας.
                      if (q.isEmpty) {
                        return const <String>[];
                      }
                      for (final u in header.callerCandidates) {
                        if (SearchTextNormalizer.matchesNormalizedQuery(
                          u.fullNameWithDepartment,
                          q,
                        )) {
                          options.add(u.fullNameWithDepartment);
                        }
                      }
                    } else {
                      final users = q.isEmpty
                          ? <UserModel>[]
                          : (lookupService?.searchUsersByQuery(
                                  effectiveText.trim(),
                                ) ??
                                []);
                      for (final u in users) {
                        options.add(u.fullNameWithDepartment);
                      }
                    }
                    return options
                        .where(
                          (option) =>
                              SearchTextNormalizer.matchesNormalizedQuery(
                                option,
                                q,
                              ),
                        )
                        .toList();
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
                  onSelected: (String selection) {
                    _commitCallerSelection(
                      selection: selection,
                      controller: controller,
                      nextFocusNode: nextFocusNode,
                      header: header,
                      lookupService: lookupService,
                      notifier: notifier,
                      getPhoneFieldDigits: widget.getPhoneFieldDigits,
                    );
                  },
                  fieldViewBuilder:
                      (
                        context,
                        textController,
                        focusNodeParam,
                        onFieldSubmitted,
                      ) {
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
                            final showUnknownOption = controller.text
                                .trim()
                                .isEmpty;
                            final callerOverlayVisible =
                                header.callerCandidates.isNotEmpty &&
                                _showSuggestionList &&
                                (controller.text.trim().isEmpty ||
                                    _isKeyboardPreview);
                            if (callerOverlayVisible) {
                              final overlayOptions =
                                  _callerOverlayKeyboardOptions(
                                    header,
                                    showUnknownOption: showUnknownOption,
                                  );
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowDown) {
                                if (overlayOptions.isEmpty) {
                                  return KeyEventResult.ignored;
                                }
                                setState(() {
                                  _keyboardOptionIndex =
                                      (_keyboardOptionIndex + 1).clamp(
                                        0,
                                        overlayOptions.length - 1,
                                      );
                                });
                                _isKeyboardPreview = true;
                                _setControllerText(
                                  textController,
                                  _callerPreviewTextForSelection(
                                    overlayOptions[_keyboardOptionIndex],
                                    header,
                                    lookupService,
                                  ),
                                );
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowUp) {
                                if (overlayOptions.isEmpty) {
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
                                  _callerPreviewTextForSelection(
                                    overlayOptions[_keyboardOptionIndex],
                                    header,
                                    lookupService,
                                  ),
                                );
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                      LogicalKeyboardKey.enter &&
                                  overlayOptions.isNotEmpty &&
                                  _keyboardOptionIndex >= 0 &&
                                  _keyboardOptionIndex <
                                      overlayOptions.length) {
                                _commitCallerSelection(
                                  selection:
                                      overlayOptions[_keyboardOptionIndex],
                                  controller: textController,
                                  nextFocusNode: nextFocusNode,
                                  header: header,
                                  lookupService: lookupService,
                                  notifier: notifier,
                                  getPhoneFieldDigits:
                                      widget.getPhoneFieldDigits,
                                );
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            }
                            final options = _callerAutocompleteOptions(
                              _typedQuery,
                              header,
                              lookupService,
                            );
                            final shouldHideInlineSuggestions =
                                event.logicalKey ==
                                    LogicalKeyboardKey.arrowDown ||
                                event.logicalKey ==
                                    LogicalKeyboardKey.arrowUp ||
                                event.logicalKey == LogicalKeyboardKey.enter;
                            if (_showSuggestionList &&
                                shouldHideInlineSuggestions &&
                                options.isNotEmpty) {
                              setState(() => _showSuggestionList = false);
                            }
                            if (event.logicalKey ==
                                LogicalKeyboardKey.arrowDown) {
                              if (options.isEmpty) {
                                return KeyEventResult.ignored;
                              }
                              _keyboardOptionIndex = (_keyboardOptionIndex + 1)
                                  .clamp(0, options.length - 1);
                              _isKeyboardPreview = true;
                              _setControllerText(
                                textController,
                                options[_keyboardOptionIndex],
                              );
                              return KeyEventResult.handled;
                            }
                            if (event.logicalKey ==
                                LogicalKeyboardKey.arrowUp) {
                              if (options.isEmpty) {
                                return KeyEventResult.ignored;
                              }
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
                              _commitCallerSelection(
                                selection: options[_keyboardOptionIndex],
                                controller: textController,
                                nextFocusNode: nextFocusNode,
                                header: header,
                                lookupService: lookupService,
                                notifier: notifier,
                                getPhoneFieldDigits: widget.getPhoneFieldDigits,
                              );
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: TextField(
                            controller: textController,
                            focusNode: focusNodeParam,
                            spellCheckConfiguration:
                                platformSpellCheckConfiguration,
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
                                      label: 'Καθαρισμός Καλούντα',
                                      child: IconButton(
                                        icon: const Icon(Icons.close, size: 20),
                                        onPressed: () {
                                          textController.clear();
                                          _typedQuery = '';
                                          _keyboardOptionIndex = -1;
                                          notifier.clearCaller();
                                          notifier.clearEquipment();
                                        },
                                        tooltip: 'Καθαρισμός Καλούντα',
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
                              if (value.trim().isEmpty) {
                                notifier.clearCaller();
                                notifier.clearEquipment();
                              } else {
                                notifier.updateCallerDisplayText(value);
                                if (header.selectedCaller != null) {
                                  final n = header.selectedCaller!.name;
                                  final f = header
                                      .selectedCaller!
                                      .fullNameWithDepartment;
                                  if (value.trim() != n && value.trim() != f) {
                                    notifier.updateSelectedCaller(null);
                                  }
                                }
                              }
                            },
                            onSubmitted: (_) {
                              final options = _callerAutocompleteOptions(
                                _typedQuery,
                                header,
                                lookupService,
                              );
                              if (options.isNotEmpty &&
                                  _keyboardOptionIndex >= 0 &&
                                  _keyboardOptionIndex < options.length) {
                                _commitCallerSelection(
                                  selection: options[_keyboardOptionIndex],
                                  controller: textController,
                                  nextFocusNode: nextFocusNode,
                                  header: header,
                                  lookupService: lookupService,
                                  notifier: notifier,
                                  getPhoneFieldDigits:
                                      widget.getPhoneFieldDigits,
                                );
                                return;
                              }
                              widget.onContentChecked();
                              nextFocusNode.requestFocus();
                              _scheduleCompletedLookup();
                            },
                          ),
                        );
                        return Semantics(
                          label: 'Όνομα καλούντος',
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
              ),
            ),
            caller_ui.CallerNameParseHint(header: header, theme: theme),
          ],
        ),
      ),
    );
  }
}

/// Μικρή λίστα κάτω από το πεδίο Καλούντας: επιλεγμένος χρήστης (αν υπάρχει) + πάντα "Άγνωστος".
/// Καλεί [onSelectionCommitted] όταν ο χρήστης επιλέγει κάτι, ώστε να εξαφανιστεί η λίστα.
class SmartEntityCallerSuggestionList extends StatelessWidget {
  const SmartEntityCallerSuggestionList({
    super.key,
    required this.header,
    required this.notifier,
    required this.controller,
    required this.theme,
    required this.showUnknownOption,
    required this.getPhoneFieldDigits,
    this.highlightedIndex = -1,
    this.onSelectionCommitted,
  });

  final SmartEntitySelectorState header;
  final SmartEntitySelectorNotifier notifier;
  final TextEditingController controller;
  final ThemeData theme;
  final bool showUnknownOption;
  final String Function() getPhoneFieldDigits;
  final int highlightedIndex;
  final VoidCallback? onSelectionCommitted;

  @override
  Widget build(BuildContext context) {
    // Για εμφάνιση στο πεδίο: μόνο ονοματεπόνυμο (name), fallback fullNameWithDepartment.
    final callerDisplayName =
        header.selectedCaller?.name ??
        header.selectedCaller?.fullNameWithDepartment ??
        '';
    final filteredCandidates = header.callerCandidates.where((u) {
      final candidateName = (u.name ?? u.fullNameWithDepartment).trim();
      return candidateName.isNotEmpty && candidateName != callerDisplayName;
    }).toList();
    final tiles = <Widget>[];
    var index = 0;
    for (final user in filteredCandidates) {
      final tileIndex = index++;
      tiles.add(
        ListTile(
          dense: true,
          selected: highlightedIndex == tileIndex,
          selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          title: Text(user.fullNameWithDepartment),
          onTap: () {
            final displayName = user.name ?? user.fullNameWithDepartment;
            controller.value = TextEditingValue(
              text: displayName,
              selection: TextSelection.collapsed(offset: displayName.length),
            );
            notifier.updateSelectedCaller(user);
            notifier.updateCallerDisplayText(displayName);
            notifier.performCallerLookup(
              displayName,
              phoneFieldDigits: getPhoneFieldDigits(),
            );
            onSelectionCommitted?.call();
          },
        ),
      );
    }
    if (callerDisplayName.isNotEmpty) {
      final tileIndex = index++;
      tiles.add(
        ListTile(
          dense: true,
          selected: highlightedIndex == tileIndex,
          selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          title: Text(callerDisplayName),
          onTap: () {
            // Στο πεδίο μόνο ονοματεπόνυμο.
            controller.value = TextEditingValue(
              text: callerDisplayName,
              selection: TextSelection.collapsed(
                offset: callerDisplayName.length,
              ),
            );
            notifier.updateCallerDisplayText(callerDisplayName);
            onSelectionCommitted?.call();
          },
        ),
      );
    }
    if (showUnknownOption) {
      final tileIndex = index++;
      tiles.add(
        ListTile(
          dense: true,
          selected: highlightedIndex == tileIndex,
          selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          title: Text(
            'Άγνωστος',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
          onTap: () {
            notifier.updateSelectedCaller(null);
            notifier.updateCallerDisplayText('Άγνωστος');
            controller.value = const TextEditingValue(
              text: 'Άγνωστος',
              selection: TextSelection.collapsed(offset: 9),
            );
            onSelectionCommitted?.call();
          },
        ),
      );
    }
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      elevation: 1,
      borderRadius: BorderRadius.circular(4),
      child: Column(mainAxisSize: MainAxisSize.min, children: tiles),
    );
  }
}
