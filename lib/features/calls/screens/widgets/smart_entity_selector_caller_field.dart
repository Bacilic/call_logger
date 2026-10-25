// ΔΙΑΣΠΑΣΤΗΚΕ ΜΕΡΙΚΩΣ (21/10/2026) — ό,τι έμεινε, μένει επίτηδες.
//
// Ρόλος: ένας — το πεδίο «Καλούντας» της φόρμας κλήσης: ζωγραφική, ποια
// λίστα φαίνεται, βελάκια/Enter με προεπισκόπηση, επιλογή, αναζήτηση στο
// φευγιό της εστίασης.
//
// Τι βγήκε: οι λίστες (μικρή λίστα, προτάσεις) και ο κανόνας «ποιος υπάλληλος
// είναι αυτή η επιλογή» ζουν στο `caller_field_options.dart`, ως καθαρή λογική
// κοινή για ζωγραφική και πληκτρολόγιο. Τα βοηθητικά (υπόδειξη ονόματος,
// σήμανση σύγκρουσης, πλαίσιο άγκυρας, αναδυόμενη λίστα) ζουν χωριστά.
//
// Γιατί δεν βγήκε ο χειρισμός πλήκτρων: βελάκια, προεπισκόπηση, «τι έγραψε
// πραγματικά ο χρήστης» και ορατότητα λιστών είναι μία κατάσταση που την
// αγγίζει κάθε πλήκτρο· σε άλλη κλάση θα χρειαζόταν όλη αυτή την κατάσταση.
// Γι' αυτό μένει εδώ, σε ένα σημείο για τις δύο λίστες.
//
// Τι θα το άλλαζε: κανόνας λιστών ή ταύτισης γραμμένος ξανά εδώ (αντί στο
// `caller_field_options.dart`), ερώτημα βάσης, ή δεύτερο πεδίο/διάλογος με
// δική του κατάσταση — τότε ξαναξετάζεται από την αρχή.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/lookup_service.dart';
import '../../../../core/utils/autocomplete_highlight_scroll.dart';
import '../../../../core/utils/spell_check.dart';
import '../../models/user_model.dart';
import '../../provider/smart_entity_selector_provider.dart';
import '../../utils/caller_field_options.dart';
import 'smart_entity_selector_anchor_frame.dart';
import 'smart_entity_selector_caller_presentational.dart' as caller_ui;
import 'smart_entity_selector_conflict_badge.dart';
import 'smart_entity_selector_overlay_utils.dart';
import '../../../../core/utils/text_layout_utils.dart';
import 'inline_field_clear_button.dart';

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
  final OverlayPortalController _suggestionOverlayController =
      OverlayPortalController();
  final LayerLink _callerLayerLink = LayerLink();

  void _performLookup() {
    final query = widget.controller.text.trim();
    if (query.isEmpty || query == kCallerUnknownOption) return;
    widget.notifier.performCallerLookup(query);
  }

  /// Η αναζήτηση στον κατάλογο για τον κανόνα ταύτισης· `null` χωρίς κατάλογο.
  List<UserModel> Function(String query)? get _catalogSearch {
    return widget.lookupService?.searchUsersByQuery;
  }

  UserModel? _resolveSelectedUser(String selection) => resolveCallerSelection(
    selection,
    candidates: widget.header.callerCandidates,
    searchUsers: _catalogSearch,
  );

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
      // Entity lookup σε focus-out (commit). Μόνο για ελεύθερο κείμενο
      // που δεν έχει ήδη επιλεγμένο καλούντα — ώστε να μη χαλάει ρητή επιλογή.
      if (widget.controller.text.trim().isNotEmpty &&
          widget.header.selectedCaller == null) {
        _performLookup();
      }
      widget.onCallerFocusOut?.call();
    }
  }

  void _onSuggestionSelected() {
    setState(() => _showSuggestionList = false);
  }

  /// Ό,τι διαλέγουν βελάκια και Enter στη μικρή λίστα — οι ίδιες γραμμές που
  /// ζωγραφίζει η [SmartEntityCallerSuggestionList].
  List<String> _callerOverlayKeyboardOptions(
    SmartEntitySelectorState header, {
    required bool showUnknownOption,
  }) {
    return [
      for (final row in callerOverlayRows(
        selectedCaller: header.selectedCaller,
        candidates: header.callerCandidates,
        showUnknownOption: showUnknownOption,
      ))
        row.label,
    ];
  }

  /// Το κείμενο με το οποίο ψάχνουν οι προτάσεις — **το ίδιο** για την ορατή
  /// λίστα και για τα βελάκια. Όσο τα βελάκια δείχνουν μια πρόταση μέσα στο
  /// πεδίο, μετρά ό,τι είχε πληκτρολογηθεί· αλλιώς ό,τι γράφει το πεδίο.
  String get _effectiveQuery =>
      _isKeyboardPreview ? _typedQuery : widget.controller.text;

  /// Ο χρήστης δεν έχει γράψει τίποτα — κρίνεται από ό,τι **έγραψε**, όχι από
  /// την προεπισκόπηση των βελακιών, που γεμίζει το πεδίο. Από αυτό εξαρτάται
  /// η γραμμή «Άγνωστος»: ένα σημείο για τη λίστα που φαίνεται και για τα
  /// βελάκια, ώστε η γραμμή να μη χάνεται στη μέση της κατάβασης.
  bool get _nothingTyped => _effectiveQuery.trim().isEmpty;

  /// Οι προτάσεις καθώς γράφεις — οι ίδιες για την ορατή λίστα και για τα
  /// βελάκια, με το ίδιο κείμενο αναζήτησης ([_effectiveQuery]).
  List<String> _callerAutocompleteOptions(
    SmartEntitySelectorState header,
    LookupService? lookupService,
  ) {
    return callerAutocompleteOptions(
      query: _effectiveQuery,
      candidates: header.callerCandidates,
      searchUsers: (query) =>
          lookupService?.searchUsersByQuery(query) ?? const <UserModel>[],
    );
  }

  void _setControllerText(TextEditingController controller, String value) {
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  /// Η επιλογή μιας γραμμής από το πληκτρολόγιο ή από τις προτάσεις: δένει
  /// τον καλούντα, γράφει το όνομά του στο πεδίο και περνά στο επόμενο πεδίο.
  void _commitCallerSelection(String selection) {
    final controller = widget.controller;
    final notifier = widget.notifier;
    _keyboardOptionIndex = -1;
    _lastAutoScrollIndex = -1;
    _isKeyboardPreview = false;
    if (selection == kCallerUnknownOption) {
      notifier.updateSelectedCaller(null);
      notifier.updateCallerDisplayText(kCallerUnknownOption);
      _setControllerText(controller, kCallerUnknownOption);
      _onSuggestionSelected();
    } else {
      final foundUser = _resolveSelectedUser(selection);
      final displayName = foundUser?.name?.trim().isNotEmpty == true
          ? foundUser!.name!.trim()
          : callerSelectionDisplayName(selection);
      if (foundUser != null) {
        notifier.updateSelectedCaller(foundUser);
      } else {
        notifier.clearCaller();
      }
      notifier.updateCallerDisplayText(displayName);
      _setControllerText(controller, displayName);
      notifier.performCallerLookup(
        displayName,
        phoneFieldDigits: widget.getPhoneFieldDigits(),
      );
      _onSuggestionSelected();
    }
    widget.onContentChecked();
    widget.nextFocusNode.requestFocus();
  }

  /// Τα βελάκια και το Enter του πεδίου — **ένας** χειρισμός για τις δύο
  /// λίστες. Ποια λίστα διαβάζεται το κρίνει το τι φαίνεται: η μικρή λίστα
  /// όσο είναι ανοιχτή, αλλιώς οι προτάσεις καθώς γράφεις.
  KeyEventResult _onCallerKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final header = widget.header;
    final key = event.logicalKey;
    final nothingTyped = _nothingTyped;
    final smallListVisible =
        header.callerCandidates.isNotEmpty &&
        _showSuggestionList &&
        (nothingTyped || _isKeyboardPreview);
    if (smallListVisible) {
      return _navigateOptions(
        key,
        _callerOverlayKeyboardOptions(header, showUnknownOption: nothingTyped),
        // Στη μικρή λίστα το πεδίο δείχνει μόνο το όνομα, όχι το τμήμα.
        previewText: (option) => callerPreviewText(
          option,
          candidates: header.callerCandidates,
          searchUsers: _catalogSearch,
        ),
      );
    }
    final options = _callerAutocompleteOptions(header, widget.lookupService);
    final isNavigationKey =
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.enter;
    // Με προτάσεις στη σειρά, η μικρή λίστα κλείνει για να μη μιλούν δύο.
    if (_showSuggestionList && isNavigationKey && options.isNotEmpty) {
      setState(() => _showSuggestionList = false);
    }
    // Στις προτάσεις το πεδίο δείχνει ολόκληρη τη γραμμή, με το τμήμα.
    return _navigateOptions(key, options, previewText: (option) => option);
  }

  /// ↓ και ↑ μετακινούν την επισήμανση χωρίς να τυλίγονται στα άκρα και
  /// γράφουν την προεπισκόπηση στο πεδίο· το Enter επιλέγει την επισημασμένη.
  KeyEventResult _navigateOptions(
    LogicalKeyboardKey key,
    List<String> options, {
    required String Function(String option) previewText,
  }) {
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      if (options.isEmpty) return KeyEventResult.ignored;
      setState(() {
        _keyboardOptionIndex = key == LogicalKeyboardKey.arrowDown
            ? (_keyboardOptionIndex + 1).clamp(0, options.length - 1)
            : (_keyboardOptionIndex <= 0 ? 0 : _keyboardOptionIndex - 1);
      });
      _isKeyboardPreview = true;
      _setControllerText(
        widget.controller,
        previewText(options[_keyboardOptionIndex]),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter &&
        options.isNotEmpty &&
        _keyboardOptionIndex >= 0 &&
        _keyboardOptionIndex < options.length) {
      _commitCallerSelection(options[_keyboardOptionIndex]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
        child: AnchorFrame(
          isAnchor: widget.header.isAnchorHighlighted(SelectorField.caller),
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
                    severity: widget.header.conflictSeverityFor(
                      SelectorField.caller,
                    ),
                    message: widget.header.conflictTooltipFor(
                      SelectorField.caller,
                    ),
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
                          showUnknownOption: _nothingTyped,
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
                    // Το πεδίο έχει ήδη το νέο κείμενο όταν καλείται αυτό: το
                    // Autocomplete ακούει τον ίδιο controller.
                    optionsBuilder: (_) =>
                        _callerAutocompleteOptions(header, lookupService),
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
                    onSelected: _commitCallerSelection,
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
                            onKeyEvent: (node, event) =>
                                _onCallerKeyEvent(event),
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
                                suffixIcon:
                                    showInlineFieldClearButton(
                                      textController.text,
                                    )
                                    ? Semantics(
                                        label: 'Καθαρισμός Καλούντα',
                                        child: IconButton(
                                          icon: const Icon(
                                            Icons.close,
                                            size: 20,
                                          ),
                                          onPressed: () {
                                            textController.clear();
                                            _typedQuery = '';
                                            _keyboardOptionIndex = -1;
                                            notifier.clearCaller();
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
                                } else {
                                  notifier.updateCallerDisplayText(value);
                                }
                              },
                              onSubmitted: (_) {
                                final options = _callerAutocompleteOptions(
                                  header,
                                  lookupService,
                                );
                                if (options.isNotEmpty &&
                                    _keyboardOptionIndex >= 0 &&
                                    _keyboardOptionIndex < options.length) {
                                  _commitCallerSelection(
                                    options[_keyboardOptionIndex],
                                  );
                                  return;
                                }
                                widget.onContentChecked();
                                nextFocusNode.requestFocus();
                                if (widget.controller.text.trim().isNotEmpty &&
                                    header.selectedCaller == null) {
                                  _performLookup();
                                }
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

  static const double _phoneOwnerIconSize = 18;

  @override
  Widget build(BuildContext context) {
    // Οι ίδιες γραμμές, με την ίδια σειρά, που διαλέγουν βελάκια και Enter:
    // ο αριθμός της επισημασμένης γραμμής δείχνει την ίδια επιλογή και στα δύο.
    final rows = callerOverlayRows(
      selectedCaller: header.selectedCaller,
      candidates: header.callerCandidates,
      showUnknownOption: showUnknownOption,
      phone: header.selectedPhone,
    );
    // Τα ονόματα μένουν στοιχισμένα: όταν σημαδεύεται έστω ένας κάτοχος, οι
    // υπόλοιπες γραμμές κρατούν κενή θέση στο ίδιο πλάτος.
    final anyPhoneOwner = rows.any((row) => row.isPhoneOwner);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      elevation: 1,
      borderRadius: BorderRadius.circular(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, row) in rows.indexed)
            ListTile(
              dense: true,
              selected: highlightedIndex == index,
              selectedTileColor: theme.colorScheme.primary.withValues(
                alpha: 0.12,
              ),
              minLeadingWidth: _phoneOwnerIconSize,
              horizontalTitleGap: 8,
              leading: !anyPhoneOwner
                  ? null
                  : row.isPhoneOwner
                  ? Icon(
                      Icons.call,
                      key: const ValueKey('caller-row-phone-owner'),
                      size: _phoneOwnerIconSize,
                      color: theme.colorScheme.primary,
                      semanticLabel: 'Κάτοχος του τηλεφώνου',
                    )
                  : const SizedBox(width: _phoneOwnerIconSize),
              title: row.kind == CallerOverlayRowKind.unknown
                  ? Text(
                      row.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    )
                  : Text(row.label),
              onTap: () => _onRowTap(row),
            ),
        ],
      ),
    );
  }

  void _setFieldText(String text) {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _onRowTap(CallerOverlayRow row) {
    switch (row.kind) {
      case CallerOverlayRowKind.candidate:
        final user = row.user!;
        // Στο πεδίο μόνο ονοματεπώνυμο, όχι και το τμήμα της γραμμής.
        final displayName = user.name ?? user.fullNameWithDepartment;
        _setFieldText(displayName);
        notifier.updateSelectedCaller(user);
        notifier.updateCallerDisplayText(displayName);
        notifier.performCallerLookup(
          displayName,
          phoneFieldDigits: getPhoneFieldDigits(),
        );
      case CallerOverlayRowKind.selected:
        _setFieldText(row.label);
        notifier.updateCallerDisplayText(row.label);
      case CallerOverlayRowKind.unknown:
        notifier.updateSelectedCaller(null);
        notifier.updateCallerDisplayText(kCallerUnknownOption);
        _setFieldText(kCallerUnknownOption);
    }
    onSelectionCommitted?.call();
  }
}
