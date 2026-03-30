import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/lookup_service.dart';
import '../../../../core/utils/spell_check.dart';
import '../../../../core/utils/name_parser.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import '../../../../features/directory/models/department_model.dart';
import '../../models/equipment_model.dart';
import '../../models/user_model.dart';
import '../../provider/lookup_provider.dart';
import '../../provider/smart_entity_selector_provider.dart';
import '../../utils/vnc_remote_target.dart';

part 'smart_entity_selector_caller_presentational.dart';
part 'smart_entity_selector_phone_presentational.dart';

bool _textOverflowsSingleLine({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required TextDirection textDirection,
}) {
  if (text.trim().isEmpty || maxWidth <= 0) return false;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: textDirection,
  )..layout(maxWidth: double.infinity);
  return painter.width > maxWidth;
}

void _syncHighlightedListScroll({
  required ScrollController controller,
  required int highlightedIndex,
  required double itemExtent,
  required double viewportExtent,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!controller.hasClients) return;
    final currentOffset = controller.offset;
    final firstVisible = (currentOffset / itemExtent).floor();
    final lastVisible =
        ((currentOffset + viewportExtent - itemExtent) / itemExtent).floor();
    double targetOffset = currentOffset;
    if (highlightedIndex < firstVisible) {
      targetOffset = highlightedIndex * itemExtent;
    } else if (highlightedIndex > lastVisible) {
      targetOffset = (highlightedIndex + 1) * itemExtent - viewportExtent;
    }
    final maxExtent = controller.position.maxScrollExtent;
    targetOffset = targetOffset.clamp(0.0, maxExtent);
    if ((targetOffset - currentOffset).abs() > 0.5) {
      controller.jumpTo(targetOffset);
    }
  });
}

List<String> _sortPhonesByRecent(
  List<String> phones,
  List<String> recentPhones,
) {
  if (recentPhones.isEmpty) return phones;
  final recentLower = recentPhones.map((e) => e.trim().toLowerCase()).toList();
  final order = <String>[];
  for (final r in recentLower) {
    for (final p in phones) {
      if (p.trim().toLowerCase() == r) {
        order.add(p);
        break;
      }
    }
  }
  for (final p in phones) {
    if (!order.contains(p)) order.add(p);
  }
  return order;
}

/// Προαιρετικές γέφυρες προς χρονόμετρο κλήσης (call entry) — null = no-op για επαναχρήση αλλού.
class SmartEntityCallEntryHooks {
  const SmartEntityCallEntryHooks({
    this.syncTimerFromPhoneText,
    this.startTimerOnceIfNotRunningWhenAutofill,
    this.resetTimerToStandby,
  });

  final void Function(String rawPhoneText)? syncTimerFromPhoneText;
  final VoidCallback? startTimerOnceIfNotRunningWhenAutofill;
  final VoidCallback? resetTimerToStandby;
}

/// Τηλέφωνο, Καλών, Τμήμα, Εξοπλισμός — ακούει τον εγχυτό [provider] (ξεχωριστό ανά φόρμα).
class SmartEntitySelectorWidget extends ConsumerStatefulWidget {
  const SmartEntitySelectorWidget({
    super.key,
    required this.provider,
    required this.w1,
    required this.w2,
    required this.wDept,
    required this.w3,
    required this.trailingRowChildren,
    this.callEntryHooks = const SmartEntityCallEntryHooks(),
  });

  final NotifierProvider<SmartEntitySelectorNotifier, SmartEntitySelectorState>
  provider;
  final double w1;
  final double w2;
  final double wDept;
  final double w3;
  final List<Widget> trailingRowChildren;
  final SmartEntityCallEntryHooks callEntryHooks;

  @override
  ConsumerState<SmartEntitySelectorWidget> createState() =>
      SmartEntitySelectorWidgetState();
}

class SmartEntitySelectorWidgetState
    extends ConsumerState<SmartEntitySelectorWidget> {
  late final TextEditingController _phoneController;
  late final TextEditingController _callerController;
  late final TextEditingController _departmentController;
  late final TextEditingController _equipmentController;
  late final FocusNode _phoneFocusNode;
  late final FocusNode _callerFocusNode;
  late final FocusNode _departmentFocusNode;
  late final FocusNode _equipmentFocusNode;
  late final SmartEntitySelectorNotifier _notifier;
  bool _isSelectingFromList = false;

  void _onFocusOut() {
    if (_isSelectingFromList) return;
    _notifier.checkContent(
      phoneText: _phoneController.text,
      callerText: _callerController.text,
      departmentText: _departmentController.text,
      equipmentText: _equipmentController.text,
    );
  }

  void _onPhoneFocusOut() {
    if (_isSelectingFromList) return;
    _notifier.checkContent(
      phoneText: _phoneController.text,
      callerText: _callerController.text,
      departmentText: _departmentController.text,
      equipmentText: _equipmentController.text,
    );
    if (!_phoneFocusNode.hasFocus) {
      widget.callEntryHooks.syncTimerFromPhoneText?.call(_phoneController.text);
    }
  }

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();
    _callerController = TextEditingController();
    _departmentController = TextEditingController();
    _equipmentController = TextEditingController();
    _phoneFocusNode = FocusNode();
    _callerFocusNode = FocusNode();
    _departmentFocusNode = FocusNode();
    _equipmentFocusNode = FocusNode();
    _notifier = ref.read(widget.provider.notifier);
    _phoneFocusNode.addListener(_onPhoneFocusOut);
    _callerFocusNode.addListener(_onFocusOut);
    _departmentFocusNode.addListener(_onFocusOut);
    _equipmentFocusNode.addListener(_onFocusOut);
  }

  @override
  void dispose() {
    _phoneFocusNode.removeListener(_onPhoneFocusOut);
    _callerFocusNode.removeListener(_onFocusOut);
    _departmentFocusNode.removeListener(_onFocusOut);
    _equipmentFocusNode.removeListener(_onFocusOut);
    _phoneFocusNode.dispose();
    _callerFocusNode.dispose();
    _departmentFocusNode.dispose();
    _equipmentFocusNode.dispose();
    _phoneController.dispose();
    _callerController.dispose();
    _departmentController.dispose();
    _equipmentController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SmartEntitySelectorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) {
      _notifier = ref.read(widget.provider.notifier);
    }
  }

  void requestPhoneFocus() => _phoneFocusNode.requestFocus();

  /// Ίδια συμπεριφορά με το προηγούμενο κουμπί «Καθαρισμός όλων»: controllers + state + timer.
  void performClearAllFields() {
    _phoneController.clear();
    _callerController.clear();
    _departmentController.clear();
    _equipmentController.clear();
    _notifier.clearAll();
    widget.callEntryHooks.resetTimerToStandby?.call();
    _phoneFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final header = ref.watch(widget.provider);
    final lookupAsync = ref.watch(lookupServiceProvider);
    final lookupService = lookupAsync.value?.service;
    final hooks = widget.callEntryHooks;

    ref.listen(widget.provider, (previous, next) {
      final prevPhone = previous?.selectedPhone?.trim() ?? '';
      final nextPhone = next.selectedPhone?.trim() ?? '';
      if (prevPhone.isEmpty &&
          nextPhone.isNotEmpty &&
          !_phoneFocusNode.hasFocus) {
        hooks.startTimerOnceIfNotRunningWhenAutofill?.call();
      }
      if (next.selectedPhone != null &&
          next.selectedPhone != _phoneController.text) {
        _phoneController.value = TextEditingValue(
          text: next.selectedPhone!,
          selection: TextSelection.collapsed(
            offset: next.selectedPhone!.length,
          ),
        );
      }
      if (next.callerDisplayText != _callerController.text) {
        _callerController.value = TextEditingValue(
          text: next.callerDisplayText,
          selection: TextSelection.collapsed(
            offset: next.callerDisplayText.length,
          ),
        );
      }
      if (next.departmentText != _departmentController.text) {
        _departmentController.value = TextEditingValue(
          text: next.departmentText,
          selection: TextSelection.collapsed(
            offset: next.departmentText.length,
          ),
        );
      }
      if (next.equipmentText != _equipmentController.text) {
        _equipmentController.value = TextEditingValue(
          text: next.equipmentText,
          selection: TextSelection.collapsed(offset: next.equipmentText.length),
        );
      }
    });

    final w1 = widget.w1;
    final w2 = widget.w2;
    final wDept = widget.wDept;
    final w3 = widget.w3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: w1,
              child: _PhoneField(
                width: w1,
                controller: _phoneController,
                focusNode: _phoneFocusNode,
                nextFocusNode: _callerFocusNode,
                header: header,
                lookupService: lookupService,
                notifier: _notifier,
                onLessThan2DigitsSubmit: () {},
                onClearAll: performClearAllFields,
                onContentChecked: () => _notifier.checkContent(
                  phoneText: _phoneController.text,
                  callerText: _callerController.text,
                  departmentText: _departmentController.text,
                  equipmentText: _equipmentController.text,
                ),
                onPhoneSubmitted: () =>
                    hooks.syncTimerFromPhoneText?.call(_phoneController.text),
                onPhoneBecameEmpty: () => hooks.resetTimerToStandby?.call(),
                onPhoneSelectedFromList: (value) {
                  setState(() => _isSelectingFromList = true);
                  hooks.syncTimerFromPhoneText?.call(value);
                  Future.delayed(const Duration(milliseconds: 150), () {
                    if (mounted) setState(() => _isSelectingFromList = false);
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: w2,
              child: _CallerField(
                width: w2,
                controller: _callerController,
                focusNode: _callerFocusNode,
                nextFocusNode: _departmentFocusNode,
                header: header,
                lookupService: lookupService,
                notifier: _notifier,
                getPhoneFieldDigits: () =>
                    _phoneController.text.replaceAll(RegExp(r'[^0-9]'), ''),
                onContentChecked: () => _notifier.checkContent(
                  phoneText: _phoneController.text,
                  callerText: _callerController.text,
                  departmentText: _departmentController.text,
                  equipmentText: _equipmentController.text,
                ),
                onCallerFocusOut: () => _notifier.checkContent(
                  phoneText: _phoneController.text,
                  callerText: _callerController.text,
                  departmentText: _departmentController.text,
                  equipmentText: _equipmentController.text,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: wDept,
              child: _DepartmentField(
                width: wDept,
                controller: _departmentController,
                focusNode: _departmentFocusNode,
                nextFocusNode: _equipmentFocusNode,
                header: header,
                lookupService: lookupService,
                notifier: _notifier,
                onContentChecked: () => _notifier.checkContent(
                  phoneText: _phoneController.text,
                  callerText: _callerController.text,
                  departmentText: _departmentController.text,
                  equipmentText: _equipmentController.text,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: w3,
              child: _EquipmentField(
                width: w3,
                controller: _equipmentController,
                focusNode: _equipmentFocusNode,
                nextFocusNode: _phoneFocusNode,
                header: header,
                lookupService: lookupService,
                notifier: _notifier,
                onContentChecked: () => _notifier.checkContent(
                  phoneText: _phoneController.text,
                  callerText: _callerController.text,
                  departmentText: _departmentController.text,
                  equipmentText: _equipmentController.text,
                ),
              ),
            ),
            ...widget.trailingRowChildren,
          ],
        ),
        const SizedBox(height: 4),
        _PhoneHelperAndError(
          header: header,
          lookupService: lookupService,
          notifier: _notifier,
        ),
      ],
    );
  }
}

class _PhoneField extends StatefulWidget {
  const _PhoneField({
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
  State<_PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<_PhoneField> {
  bool _isSelectingFromList = false;
  bool _isKeyboardPreview = false;
  int _keyboardOptionIndex = -1;
  int _lastAutoScrollIndex = -1;
  String _typedQuery = '';

  /// Κρατά τη λίστα πολλαπλών τηλεφώνων ορατή λίγο μετά το blur, ώστε να
  /// προλαβαίνει το tap (ίδια ιδέα με το πεδίο Καλούντας).
  bool _showSuggestionList = false;
  final ScrollController _optionsScrollController = ScrollController();
  Timer? _debounce;

  /// Αναζήτηση τηλεφώνου: `performPhoneLookup` για 0 / 1 / πολλαπλά αποτελέσματα.
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
    // Καθυστέρηση κλεισίματος λίστας ώστε να προλάβει το onTap (blur πριν το tap).
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
    // Μην κάνουμε return όταν value == selectedPhone: μετά από sync controller↔state
    // το onChanged μπορεί να ξανακληθεί χωρίς αλλαγή κειμένου· το lookup (≥3 ψηφία) πρέπει να προγραμματίζεται.
    if (digits != headerPhone) {
      widget.notifier.updatePhone(digits.isEmpty ? null : digits);
      widget.notifier.markPhoneAsManual();
    }
    if (digits.isEmpty) {
      widget.onPhoneBecameEmpty();
    } else if (digits.length >= 3) {
      _scheduleCompletedLookup();
    }
  }

  void _onPhoneTextChange() {
    if (_isKeyboardPreview) {
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
    if (widget.focusNode.hasFocus) {
      setState(() => _showSuggestionList = true);
    }
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
      final candidates = _sortPhonesByRecent(
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
    return _sortPhonesByRecent(list, header.recentPhones);
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
  void dispose() {
    _debounce?.cancel();
    _optionsScrollController.dispose();
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
        !_isKeyboardPreview &&
        controller.text.trim().isEmpty;

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
              ],
            ),
            const SizedBox(height: 4),
            Autocomplete<String>(
              focusNode: focusNode,
              textEditingController: controller,
              optionsBuilder: (value) {
                final effectiveText = _isKeyboardPreview
                    ? _typedQuery
                    : value.text;
                final text = effectiveText.replaceAll(RegExp(r'[^0-9]'), '');
                if (header.phoneCandidates.isNotEmpty) {
                  final candidates = _sortPhonesByRecent(
                    List<String>.from(header.phoneCandidates),
                    header.recentPhones,
                  );
                  if (text.isEmpty) return candidates;
                  return candidates.where((p) {
                    final digits = p.replaceAll(RegExp(r'[^0-9]'), '');
                    return digits.contains(text) || digits.startsWith(text);
                  });
                }
                if (text.length < 2) return const Iterable<String>.empty();
                final list = lookupService?.searchPhonesByPrefix(text) ?? [];
                return _sortPhonesByRecent(list, header.recentPhones);
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
                              _syncHighlightedListScroll(
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
              fieldViewBuilder:
                  (context, textController, focusNodeParam, onFieldSubmitted) {
                    return Semantics(
                      label: 'Αριθμός τηλεφώνου',
                      child: Focus(
                        onKeyEvent: (node, event) {
                          if (event is! KeyDownEvent) {
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
                          spellCheckConfiguration: platformSpellCheckConfiguration,
                          decoration: InputDecoration(
                            hintStyle: TextStyle(
                              color: Theme.of(context).hintColor,
                            ),
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: Semantics(
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
                            ),
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
            if (showPhoneCandidates)
              _PhoneSuggestionList(
                phones: _sortPhonesByRecent(
                  List<String>.from(header.phoneCandidates),
                  header.recentPhones,
                ),
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
          ],
        ),
      ),
    );
  }
}

class _PhoneSuggestionList extends StatelessWidget {
  const _PhoneSuggestionList({required this.phones, required this.onSelected});

  final List<String> phones;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      elevation: 1,
      borderRadius: BorderRadius.circular(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final phone in phones)
            ListTile(
              dense: true,
              title: Text(phone),
              onTap: () => onSelected(phone),
            ),
        ],
      ),
    );
  }
}

class _CallerField extends StatefulWidget {
  const _CallerField({
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
  State<_CallerField> createState() => _CallerFieldState();
}

class _CallerFieldState extends State<_CallerField> {
  /// Όταν true, η λίστα προτάσεων εμφανίζεται. Γίνεται false μόλις ο χρήστης επιλέξει από τη λίστα.
  bool _showSuggestionList = false;
  bool _isKeyboardPreview = false;
  int _keyboardOptionIndex = -1;
  int _lastAutoScrollIndex = -1;
  String _typedQuery = '';
  final ScrollController _optionsScrollController = ScrollController();
  Timer? _debounce;

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
  void dispose() {
    _debounce?.cancel();
    _optionsScrollController.dispose();
    widget.focusNode.removeListener(_onCallerFocusChange);
    widget.controller.removeListener(_onCallerTextChange);
    super.dispose();
  }

  void _onCallerTextChange() {
    if (_isKeyboardPreview) {
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
    if (widget.focusNode.hasFocus) {
      setState(() => _showSuggestionList = true);
    }
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
      widget.onCallerFocusOut?.call();
    }
  }

  void _onSuggestionSelected() {
    setState(() => _showSuggestionList = false);
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
      notifier.markCallerAsManual();
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
  void didUpdateWidget(covariant _CallerField oldWidget) {
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

    // Η βοηθητική λίστα εμφανίζεται με βάση το εσωτερικό state (για να προλαβαίνει το onTap)
    final showSuggestions = _showSuggestionList;

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
              ],
            ),
            const SizedBox(height: 4),
            Autocomplete<String>(
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
                      (option) => SearchTextNormalizer.matchesNormalizedQuery(
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
                              _syncHighlightedListScroll(
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
                  (context, textController, focusNodeParam, onFieldSubmitted) {
                    final style =
                        theme.textTheme.bodyLarge ?? const TextStyle();
                    final showTooltip =
                        !focusNodeParam.hasFocus &&
                        _textOverflowsSingleLine(
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
                        final options = _callerAutocompleteOptions(
                          _typedQuery,
                          header,
                          lookupService,
                        );
                        final shouldHideInlineSuggestions =
                            event.logicalKey == LogicalKeyboardKey.arrowDown ||
                            event.logicalKey == LogicalKeyboardKey.arrowUp ||
                            event.logicalKey == LogicalKeyboardKey.enter;
                        if (_showSuggestionList &&
                            shouldHideInlineSuggestions &&
                            options.isNotEmpty) {
                          setState(() => _showSuggestionList = false);
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
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
                        spellCheckConfiguration: platformSpellCheckConfiguration,
                        decoration: InputDecoration(
                          hintText: hintText,
                          hintStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: Semantics(
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
                          ),
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
                            notifier.markCallerAsManual();
                            if (header.selectedCaller != null) {
                              final n = header.selectedCaller!.name;
                              final f =
                                  header.selectedCaller!.fullNameWithDepartment;
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
                              getPhoneFieldDigits: widget.getPhoneFieldDigits,
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
            if (showSuggestions && _showSuggestionList && !_isKeyboardPreview)
              Builder(
                builder: (context) {
                  return _CallerSuggestionList(
                    header: header,
                    notifier: notifier,
                    controller: controller,
                    theme: theme,
                    showUnknownOption: controller.text.trim().isEmpty,
                    getPhoneFieldDigits: widget.getPhoneFieldDigits,
                    onSelectionCommitted: _onSuggestionSelected,
                  );
                },
              ),
            _CallerParseHint(header: header, theme: theme),
          ],
        ),
      ),
    );
  }
}

/// Μικρή λίστα κάτω από το πεδίο Καλούντας: επιλεγμένος χρήστης (αν υπάρχει) + πάντα "Άγνωστος".
/// Καλεί [onSelectionCommitted] όταν ο χρήστης επιλέγει κάτι, ώστε να εξαφανιστεί η λίστα.
class _CallerSuggestionList extends StatelessWidget {
  const _CallerSuggestionList({
    required this.header,
    required this.notifier,
    required this.controller,
    required this.theme,
    required this.showUnknownOption,
    required this.getPhoneFieldDigits,
    this.onSelectionCommitted,
  });

  final SmartEntitySelectorState header;
  final SmartEntitySelectorNotifier notifier;
  final TextEditingController controller;
  final ThemeData theme;
  final bool showUnknownOption;
  final String Function() getPhoneFieldDigits;
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
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      elevation: 1,
      borderRadius: BorderRadius.circular(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final user in filteredCandidates)
            ListTile(
              dense: true,
              title: Text(user.fullNameWithDepartment),
              onTap: () {
                final displayName = user.name ?? user.fullNameWithDepartment;
                controller.value = TextEditingValue(
                  text: displayName,
                  selection: TextSelection.collapsed(
                    offset: displayName.length,
                  ),
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
          if (callerDisplayName.isNotEmpty)
            ListTile(
              dense: true,
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
          if (showUnknownOption)
            ListTile(
              dense: true,
              title: Text(
                'Άγνωστος',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.8,
                  ),
                ),
              ),
              onTap: () {
                notifier.updateSelectedCaller(null);
                notifier.updateCallerDisplayText('Άγνωστος');
                notifier.markCallerAsManual();
                controller.value = const TextEditingValue(
                  text: 'Άγνωστος',
                  selection: TextSelection.collapsed(offset: 9),
                );
                onSelectionCommitted?.call();
              },
            ),
        ],
      ),
    );
  }
}

/// Πεδίο Τμήμα: `Autocomplete<DepartmentModel>` ανάμεσα σε Καλούντας και Εξοπλισμό.
class _DepartmentField extends StatefulWidget {
  const _DepartmentField({
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
  State<_DepartmentField> createState() => _DepartmentFieldState();
}

class _DepartmentFieldState extends State<_DepartmentField> {
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
                              _syncHighlightedListScroll(
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
                        _textOverflowsSingleLine(
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
                          suffixIcon: Semantics(
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
                          ),
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

class _EquipmentSuggestion {
  const _EquipmentSuggestion({
    required this.equipment,
    required this.sourceLabel,
  });

  final EquipmentModel equipment;
  final String sourceLabel;
}

class _EquipmentField extends StatefulWidget {
  const _EquipmentField({
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
  State<_EquipmentField> createState() => _EquipmentFieldState();
}

class _EquipmentFieldState extends State<_EquipmentField> {
  bool _isSelectingEquipment = false;
  bool _showInitialList = false;
  bool _isKeyboardPreview = false;
  int _keyboardOptionIndex = -1;
  int _lastAutoScrollIndex = -1;
  String _typedQuery = '';
  final ScrollController _optionsScrollController = ScrollController();

  /// True μόνο αμέσως μετά επιλογή από _EquipmentSuggestionList· αποτρέπει το didUpdateWidget από clear.
  bool _justSelectedFromCustomList = false;
  Timer? _debounce;

  void _performLookup() {
    final query = widget.controller.text.trim();
    if (query.isEmpty) return;
    widget.notifier.performEquipmentLookupByCode(query);
  }

  void _scheduleCompletedLookup() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _performLookup();
    });
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
  void dispose() {
    _debounce?.cancel();
    _optionsScrollController.dispose();
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
      _scheduleCompletedLookup();
      // Καθυστέρηση κλεισίματος ώστε να προλάβει το onTap στη λίστα.
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
    if (widget.focusNode.hasFocus) {
      setState(() {
        _showInitialList = true;
      });
    }
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

  List<EquipmentModel> _phoneEquipments(
    SmartEntitySelectorState header,
    LookupService? lookupService,
  ) {
    final phone = header.selectedPhone?.trim() ?? '';
    if (phone.isEmpty || lookupService == null) {
      return const [];
    }
    final users = lookupService.findUsersByPhone(phone);
    final result = <EquipmentModel>[];
    for (final user in users) {
      if (user.id != null) {
        result.addAll(lookupService.findEquipmentsForUser(user.id!));
      }
    }
    return _dedupeEquipments(result);
  }

  List<EquipmentModel> _callerEquipments(
    SmartEntitySelectorState header,
    LookupService? lookupService,
  ) {
    if (lookupService == null) {
      return _dedupeEquipments(header.equipmentCandidates);
    }
    final callerId = header.selectedCaller?.id;
    if (callerId == null) {
      return _dedupeEquipments(header.equipmentCandidates);
    }
    final direct = lookupService.findEquipmentsForUser(callerId);
    if (direct.isNotEmpty) {
      return _dedupeEquipments(direct);
    }
    return _dedupeEquipments(header.equipmentCandidates);
  }

  List<_EquipmentSuggestion> _initialSuggestions(
    SmartEntitySelectorState header,
    LookupService? lookupService,
  ) {
    final phoneEquipments = _phoneEquipments(header, lookupService);
    final callerEquipments = _callerEquipments(header, lookupService);
    final phoneKeys = phoneEquipments.map(_equipmentKey).toSet();
    final callerKeys = callerEquipments.map(_equipmentKey).toSet();

    final combined = <_EquipmentSuggestion>[];
    final seen = <String>{};

    for (final equipment in phoneEquipments) {
      final key = _equipmentKey(equipment);
      if (callerKeys.contains(key) && seen.add(key)) {
        combined.add(
          _EquipmentSuggestion(
            equipment: equipment,
            sourceLabel: 'Τηλ. + Όνομα',
          ),
        );
      }
    }

    for (final equipment in phoneEquipments) {
      final key = _equipmentKey(equipment);
      if (!callerKeys.contains(key) && seen.add(key)) {
        combined.add(
          _EquipmentSuggestion(equipment: equipment, sourceLabel: 'Τηλέφωνο'),
        );
      }
    }

    for (final equipment in callerEquipments) {
      final key = _equipmentKey(equipment);
      if (!phoneKeys.contains(key) && seen.add(key)) {
        combined.add(
          _EquipmentSuggestion(equipment: equipment, sourceLabel: 'Όνομα'),
        );
      }
    }

    return combined;
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
    // Σε typing mode θέλουμε global προτάσεις από όλη τη βάση (όχι μόνο context-based list).
    return _dedupeEquipments(lookupService.findEquipmentsByCode(query));
  }

  /// Κείμενο για το πλαίσιο εισαγωγής: μόνο κωδικός (η λίστα δείχνει κωδικός + τύπο).
  static String _equipmentFieldText(EquipmentModel e) =>
      e.code?.trim().isNotEmpty == true ? e.code!.trim() : e.displayLabel;

  void _selectEquipment(
    EquipmentModel equipment, {
    bool fromCustomList = false,
  }) {
    _isSelectingEquipment = true;
    if (fromCustomList) _justSelectedFromCustomList = true;
    _setControllerText(widget.controller, _equipmentFieldText(equipment));
    widget.notifier.setEquipment(equipment);
    widget.notifier.markEquipmentAsManual();
    widget.notifier.performEquipmentLookupByCode(
      _equipmentFieldText(equipment),
    );
    widget.notifier.checkContent(equipmentText: widget.controller.text);
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
  void didUpdateWidget(covariant _EquipmentField oldWidget) {
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
    if (!widget.header.equipmentIsManual &&
        sel != null &&
        widget.controller.text != _equipmentFieldText(sel)) {
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
    final showInitialSuggestionList =
        _showInitialList &&
        controller.text.trim().isEmpty &&
        initialSuggestions.isNotEmpty;

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
                  Icons.computer_outlined,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Κωδικός Εξοπλισμού',
                    style: theme.textTheme.labelMedium,
                    softWrap: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Autocomplete<EquipmentModel>(
              displayStringForOption: (e) => e.displayLabel,
              focusNode: focusNode,
              textEditingController: controller,
              optionsBuilder: (value) {
                final effectiveText = _isKeyboardPreview
                    ? _typedQuery
                    : value.text;
                return _querySuggestions(header, lookupService, effectiveText);
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
                              _syncHighlightedListScroll(
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
                            selectedTileColor: theme.colorScheme.primary
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
              fieldViewBuilder:
                  (context, textController, focusNodeParam, onFieldSubmitted) {
                    return Semantics(
                      label: 'Κωδικός εξοπλισμού',
                      child: Focus(
                        onKeyEvent: (node, event) {
                          if (event is! KeyDownEvent) {
                            return KeyEventResult.ignored;
                          }
                          final options = _querySuggestions(
                            header,
                            lookupService,
                            _typedQuery,
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
                          spellCheckConfiguration: platformSpellCheckConfiguration,
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
                            suffixIcon: Semantics(
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
                            ),
                          ),
                          onChanged: (value) {
                            if (_isKeyboardPreview) {
                              _isKeyboardPreview = false;
                              return;
                            }
                            _typedQuery = value;
                            _keyboardOptionIndex = -1;
                            _lastAutoScrollIndex = -1;
                            if (_isSelectingEquipment) {
                              notifier.checkContent(equipmentText: value);
                              return;
                            }
                            final selected = header.selectedEquipment;
                            if (selected != null &&
                                value != _equipmentFieldText(selected)) {
                              notifier.clearEquipment();
                            }
                            notifier.markEquipmentAsManual();
                            notifier.checkContent(equipmentText: value);
                          },
                          onSubmitted: (_) {
                            final options = _querySuggestions(
                              header,
                              lookupService,
                              _typedQuery,
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
                            _scheduleCompletedLookup();
                          },
                        ),
                      ),
                    );
                  },
            ),
            if (showInitialSuggestionList)
              _EquipmentSuggestionList(
                suggestions: initialSuggestions,
                theme: theme,
                onSelected: (e) => _selectEquipment(e, fromCustomList: true),
              ),
          ],
        ),
      ),
    );
  }
}

class _EquipmentSuggestionList extends StatelessWidget {
  const _EquipmentSuggestionList({
    required this.suggestions,
    required this.theme,
    required this.onSelected,
  });

  final List<_EquipmentSuggestion> suggestions;
  final ThemeData theme;
  final ValueChanged<EquipmentModel> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      elevation: 1,
      borderRadius: BorderRadius.circular(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final suggestion in suggestions)
            ListTile(
              dense: true,
              title: Text(suggestion.equipment.displayLabel),
              subtitle: Text(
                suggestion.sourceLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              onTap: () => onSelected(suggestion.equipment),
            ),
        ],
      ),
    );
  }
}

