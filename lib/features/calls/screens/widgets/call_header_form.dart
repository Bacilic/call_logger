import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/lookup_service.dart';
import '../../../../core/utils/name_parser.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import '../../../../features/directory/models/department_model.dart';
import '../../models/equipment_model.dart';
import '../../models/user_model.dart';
import '../../provider/call_entry_provider.dart';
import '../../provider/call_header_provider.dart';
import '../../provider/lookup_provider.dart';

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

/// Header φόρμα εισαγωγής κλήσης: Τηλέφωνο, Καλούντας, Τμήμα, Κωδικός Εξοπλισμού.
class CallHeaderForm extends ConsumerStatefulWidget {
  const CallHeaderForm({super.key});

  @override
  ConsumerState<CallHeaderForm> createState() => _CallHeaderFormState();
}

class _CallHeaderFormState extends ConsumerState<CallHeaderForm> {
  late final TextEditingController _phoneController;
  late final TextEditingController _callerController;
  late final TextEditingController _departmentController;
  late final TextEditingController _equipmentController;
  late final FocusNode _phoneFocusNode;
  late final FocusNode _callerFocusNode;
  late final FocusNode _departmentFocusNode;
  late final FocusNode _equipmentFocusNode;
  late final CallHeaderNotifier _notifier;
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
      final digits = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isNotEmpty) {
        ref.read(callEntryProvider.notifier).startTimerOnce();
      } else {
        ref.read(callEntryProvider.notifier).resetTimerToStandby();
      }
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
    _notifier = ref.read(callHeaderProvider.notifier);
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

  static List<String> _sortPhonesByRecent(
    List<String> phones,
    List<String> recentPhones,
  ) {
    if (recentPhones.isEmpty) return phones;
    final recentLower = recentPhones
        .map((e) => e.trim().toLowerCase())
        .toList();
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

  @override
  Widget build(BuildContext context) {
    final header = ref.watch(callHeaderProvider);
    final lookupAsync = ref.watch(lookupServiceProvider);
    final lookupService = lookupAsync.value;

    final hasAnyContent = ref.watch(
      callHeaderProvider.select((s) => s.hasAnyContent),
    );
    final theme = Theme.of(context);

    ref.listen(callHeaderProvider, (previous, next) {
      final prevPhone = previous?.selectedPhone?.trim() ?? '';
      final nextPhone = next.selectedPhone?.trim() ?? '';
      if (prevPhone.isEmpty &&
          nextPhone.isNotEmpty &&
          !_phoneFocusNode.hasFocus) {
        final timerNotifier = ref.read(callEntryProvider.notifier);
        if (!timerNotifier.isTimerRunning) {
          timerNotifier.startTimerOnce();
        }
      }
      // Ενημέρωση Phone
      if (next.selectedPhone != null &&
          next.selectedPhone != _phoneController.text) {
        _phoneController.value = TextEditingValue(
          text: next.selectedPhone!,
          selection: TextSelection.collapsed(
            offset: next.selectedPhone!.length,
          ),
        );
      }

      // Ενημέρωση Caller (callerDisplayText)
      if (next.callerDisplayText != _callerController.text) {
        _callerController.value = TextEditingValue(
          text: next.callerDisplayText,
          selection: TextSelection.collapsed(
            offset: next.callerDisplayText.length,
          ),
        );
      }

      // Ενημέρωση Department (departmentText)
      if (next.departmentText != _departmentController.text) {
        _departmentController.value = TextEditingValue(
          text: next.departmentText,
          selection: TextSelection.collapsed(
            offset: next.departmentText.length,
          ),
        );
      }

      // Ενημέρωση Equipment (equipmentText)
      if (next.equipmentText != _equipmentController.text) {
        _equipmentController.value = TextEditingValue(
          text: next.equipmentText,
          selection: TextSelection.collapsed(offset: next.equipmentText.length),
        );
      }
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final mw = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        // Κρατάμε ανώτατα όρια στα πλάτη ώστε το ×/+ να μένει πάντα κοντά
        // στο πεδίο εξοπλισμού και να μην "φεύγει" δεξιά σε πολύ φαρδιά οθόνη.
        final w1 = (mw * 0.18).clamp(120.0, 170.0);
        final w2 = (mw * 0.34).clamp(220.0, 300.0);
        final wDept = (mw * 0.24).clamp(160.0, 240.0);
        final w3 = (mw * 0.20).clamp(130.0, 185.0);
        final headerFields = ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            scrollbars: true,
            physics: const ClampingScrollPhysics(),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
                onClearAll: () {
                  _phoneController.clear();
                  _callerController.clear();
                  _departmentController.clear();
                  _equipmentController.clear();
                  _notifier.clearAll();
                  ref.read(callEntryProvider.notifier).resetTimerToStandby();
                  _phoneFocusNode.requestFocus();
                },
                onContentChecked: () => _notifier.checkContent(
                  phoneText: _phoneController.text,
                  callerText: _callerController.text,
                  departmentText: _departmentController.text,
                  equipmentText: _equipmentController.text,
                ),
                onPhoneSubmitted: () {
                  final digits = _phoneController.text.replaceAll(
                    RegExp(r'[^0-9]'),
                    '',
                  );
                  if (digits.isNotEmpty) {
                    ref.read(callEntryProvider.notifier).startTimerOnce();
                  } else {
                    ref.read(callEntryProvider.notifier).resetTimerToStandby();
                  }
                },
                onPhoneBecameEmpty: () =>
                    ref.read(callEntryProvider.notifier).resetTimerToStandby(),
                onPhoneSelectedFromList: (value) {
                  setState(() => _isSelectingFromList = true);
                  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
                  if (digits.isNotEmpty) {
                    ref.read(callEntryProvider.notifier).startTimerOnce();
                  } else {
                    ref.read(callEntryProvider.notifier).resetTimerToStandby();
                  }
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
                  const SizedBox(width: 4),
                  IgnorePointer(
                    ignoring: !hasAnyContent,
                    child: AnimatedOpacity(
                      opacity: hasAnyContent ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 180),
                      child: AnimatedScale(
                        scale: hasAnyContent ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 180),
                        child: IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: theme.colorScheme.error,
                          ),
                          tooltip: 'Καθαρισμός όλων των πεδίων',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                          onPressed: () {
                            _phoneController.clear();
                            _callerController.clear();
                            _departmentController.clear();
                            _equipmentController.clear();
                            _notifier.clearAll();
                            ref
                                .read(callEntryProvider.notifier)
                                .resetTimerToStandby();
                            _phoneFocusNode.requestFocus();
                          },
                        ),
                      ),
                    ),
                  ),
                  if (header.needsAssociation)
                    IconButton(
                      icon: Icon(Icons.add, color: header.associationColor),
                      tooltip: header.associationTooltip ?? '',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final currentHeader = ref.read(callHeaderProvider);
                        final caller = currentHeader.selectedCaller;
                        final departmentText =
                            currentHeader.departmentText.trim();
                        final selectedDepartment = departmentText.isNotEmpty
                            ? lookupService
                                ?.findDepartmentByName(departmentText)
                            : null;
                        var updatePrimaryDepartment = false;

                        if (caller?.id != null &&
                            selectedDepartment?.id != null &&
                            selectedDepartment!.id != caller!.departmentId) {
                          final askUpdate = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) {
                              return AlertDialog(
                                title: const Text('Αλλαγή κύριου τμήματος'),
                                content: Text(
                                  'Ο χρήστης έχει κύριο τμήμα "${caller.departmentName ?? 'Χωρίς τμήμα'}". '
                                  'Να γίνει νέο κύριο τμήμα του χρήστη το "${selectedDepartment.name}";',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(false),
                                    child: const Text('Όχι'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(true),
                                    child: const Text('Ναι'),
                                  ),
                                ],
                              );
                            },
                          );
                          updatePrimaryDepartment = askUpdate ?? false;
                        }

                        final msg = await _notifier.associateCurrentIfNeeded(
                          updatePrimaryDepartment: updatePrimaryDepartment,
                        );
                        if (mounted && msg != null) {
                          messenger.showSnackBar(SnackBar(content: Text(msg)));
                        }
                      },
                    ),
              ],
            ),
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            headerFields,
            const SizedBox(height: 4),
            _PhoneHelperAndError(
              header: header,
              lookupService: lookupService,
              notifier: _notifier,
            ),
          ],
        );
      },
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
  final CallHeaderState header;
  final LookupService? lookupService;
  final CallHeaderNotifier notifier;
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

  /// Κρατά τη λίστα πολλαπλών τηλεφώνων ορατή λίγο μετά το blur, ώστε να
  /// προλαβαίνει το tap (ίδια ιδέα με το πεδίο Καλούντας).
  bool _showSuggestionList = false;
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
    _debounce?.cancel();
    if (value == widget.header.selectedPhone) return;
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    widget.notifier.updatePhone(digits.isEmpty ? null : digits);
    widget.notifier.markPhoneAsManual();
    if (digits.isEmpty) {
      widget.onPhoneBecameEmpty();
    }
  }

  void _onPhoneTextChange() {
    if (widget.focusNode.hasFocus) {
      setState(() => _showSuggestionList = true);
    }
  }

  @override
  void initState() {
    super.initState();
    _showSuggestionList = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onPhoneTextChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
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
                final text = value.text.replaceAll(RegExp(r'[^0-9]'), '');
                if (header.phoneCandidates.isNotEmpty) {
                  // Κενό πεδίο: η λίστα κάτω (_PhoneSuggestionList) δείχνει τα candidates.
                  if (text.isEmpty) return const Iterable<String>.empty();

                  final candidates = _CallHeaderFormState._sortPhonesByRecent(
                    List<String>.from(header.phoneCandidates),
                    header.recentPhones,
                  );
                  return candidates.where((p) {
                    final digits = p.replaceAll(RegExp(r'[^0-9]'), '');
                    return digits.contains(text) || digits.startsWith(text);
                  });
                }
                if (text.length < 2) return const Iterable<String>.empty();
                final list = lookupService?.searchPhonesByPrefix(text) ?? [];
                return _CallHeaderFormState._sortPhonesByRecent(
                  list,
                  header.recentPhones,
                );
              },
              onSelected: (value) {
                setState(() {
                  _isSelectingFromList = true;
                  _showSuggestionList = false;
                });
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  controller.text = value;
                  notifier.setPhone(value);
                  // Από `phoneCandidates`: διατηρούμε caller / εξοπλισμό χωρίς νέο lookup.
                  final fromCandidates = header.phoneCandidates.contains(value);
                  if (fromCandidates) {
                    notifier.selectPhoneFromCandidates(value);
                  } else {
                    notifier.markPhoneUsed(value);
                    notifier.performPhoneLookup(
                      value.replaceAll(RegExp(r'[^0-9]'), ''),
                    );
                  }
                  widget.onPhoneSelectedFromList(value);
                  if (!focusNode.hasFocus) {
                    focusNode.requestFocus();
                  }
                  Future.delayed(const Duration(milliseconds: 250), () {
                    if (mounted) setState(() => _isSelectingFromList = false);
                  });
                });
              },
              fieldViewBuilder:
                  (context, textController, focusNodeParam, onFieldSubmitted) {
                    return Semantics(
                      label: 'Αριθμός τηλεφώνου',
                      child: TextField(
                        controller: textController,
                        focusNode: focusNodeParam,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'π.χ. 2345',
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
                    );
                  },
            ),
            if (showPhoneCandidates)
              _PhoneSuggestionList(
                phones: _CallHeaderFormState._sortPhonesByRecent(
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
    required this.onContentChecked,
    this.onCallerFocusOut,
  });

  final double width;
  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode nextFocusNode;
  final CallHeaderState header;
  final LookupService? lookupService;
  final CallHeaderNotifier notifier;
  final VoidCallback onContentChecked;
  final VoidCallback? onCallerFocusOut;

  @override
  State<_CallerField> createState() => _CallerFieldState();
}

class _CallerFieldState extends State<_CallerField> {
  /// Όταν true, η λίστα προτάσεων εμφανίζεται. Γίνεται false μόλις ο χρήστης επιλέξει από τη λίστα.
  bool _showSuggestionList = false;
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
    CallHeaderState header,
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
    widget.focusNode.addListener(_onCallerFocusChange);
    widget.controller.addListener(_onCallerTextChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.focusNode.removeListener(_onCallerFocusChange);
    widget.controller.removeListener(_onCallerTextChange);
    super.dispose();
  }

  void _onCallerTextChange() {
    if (widget.focusNode.hasFocus) {
      setState(() => _showSuggestionList = true);
    }
  }

  void _onCallerFocusChange() {
    if (widget.focusNode.hasFocus) {
      setState(() => _showSuggestionList = true);
    } else {
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
                final q = SearchTextNormalizer.normalizeForSearch(
                  textEditingValue.text,
                );
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
                      : (lookupService?.searchUsersByQuery(
                              textEditingValue.text.trim(),
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
              onSelected: (String selection) {
                if (selection == 'Άγνωστος') {
                  notifier.updateSelectedCaller(null);
                  notifier.updateCallerDisplayText('Άγνωστος');
                  notifier.markCallerAsManual();
                  controller.text = 'Άγνωστος';
                  _onSuggestionSelected();
                } else {
                  final foundUser = _resolveSelectedUser(
                    selection,
                    header,
                    lookupService,
                  );
                  final displayName = foundUser?.name?.trim().isNotEmpty == true
                      ? foundUser!.name!.trim()
                      : _extractDisplayName(selection);
                  if (foundUser != null) {
                    notifier.updateSelectedCaller(foundUser);
                  } else {
                    notifier.clearCaller();
                  }
                  notifier.updateCallerDisplayText(displayName);
                  controller.text = displayName;
                  notifier.performCallerLookup(displayName);
                  _onSuggestionSelected();
                }
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
                    final field = TextField(
                      controller: textController,
                      focusNode: focusNodeParam,
                      decoration: InputDecoration(
                        hintText: hintText,
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: Semantics(
                          label: 'Καθαρισμός Καλούντα',
                          child: IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () {
                              textController.clear();
                              notifier.clearCaller();
                              notifier.clearEquipment();
                            },
                            tooltip: 'Καθαρισμός Καλούντα',
                          ),
                        ),
                      ),
                      onChanged: (value) {
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
                        widget.onContentChecked();
                        nextFocusNode.requestFocus();
                        _scheduleCompletedLookup();
                      },
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
            if (showSuggestions && _showSuggestionList)
              _CallerSuggestionList(
                header: header,
                notifier: notifier,
                controller: controller,
                theme: theme,
                showUnknownOption: controller.text.trim().isEmpty,
                onSelectionCommitted: _onSuggestionSelected,
              ),
            _CallerParseHint(header: header, theme: theme),
          ],
        ),
      ),
    );
  }
}

/// Οπτική ανατροφοδότηση: πώς θα ερμηνευτεί το κείμενο Καλούντα (Όνομα / Επώνυμο).
class _CallerParseHint extends StatelessWidget {
  const _CallerParseHint({required this.header, required this.theme});

  final CallHeaderState header;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (header.selectedCaller != null) return const SizedBox.shrink();
    if (header.isUnknownCaller) return const SizedBox.shrink();
    final text = header.callerDisplayText.trim();
    if (text.isEmpty) return const SizedBox.shrink();

    final parsed = NameParserUtility.parse(text);
    final style = theme.textTheme.bodySmall ?? const TextStyle();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: RichText(
        textScaler: TextScaler.noScaling,
        text: TextSpan(
          style: style.copyWith(color: theme.colorScheme.onSurface),
          children: [
            TextSpan(
              text: 'Όνομα: ${parsed.firstName} ',
              style: style.copyWith(color: theme.colorScheme.primary),
            ),
            TextSpan(
              text: '- Επώνυμο: ${parsed.lastName}',
              style: style.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
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
    this.onSelectionCommitted,
  });

  final CallHeaderState header;
  final CallHeaderNotifier notifier;
  final TextEditingController controller;
  final ThemeData theme;
  final bool showUnknownOption;
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
                controller.text = displayName;
                notifier.updateSelectedCaller(user);
                notifier.updateCallerDisplayText(displayName);
                notifier.performCallerLookup(displayName);
                onSelectionCommitted?.call();
              },
            ),
          if (callerDisplayName.isNotEmpty)
            ListTile(
              dense: true,
              title: Text(callerDisplayName),
              onTap: () {
                // Στο πεδίο μόνο ονοματεπόνυμο.
                controller.text = callerDisplayName;
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
                controller.text = 'Άγνωστος';
                onSelectionCommitted?.call();
              },
            ),
        ],
      ),
    );
  }
}

/// Πεδίο Τμήμα: `Autocomplete<DepartmentModel>` ανάμεσα σε Καλούντας και Εξοπλισμό.
class _DepartmentField extends StatelessWidget {
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
  final CallHeaderState header;
  final LookupService? lookupService;
  final CallHeaderNotifier notifier;
  final VoidCallback onContentChecked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textDirection = Directionality.of(context);
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
                final query = value.text.trim();
                if (lookupService == null) return const [];
                return lookupService!.searchDepartments(query);
              },
              onSelected: (DepartmentModel selection) {
                controller.text = selection.name;
                notifier.selectDepartment(selection);
                onContentChecked();
                nextFocusNode.requestFocus();
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
                    final field = TextField(
                      controller: textController,
                      focusNode: focusNodeParam,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: Semantics(
                          label: 'Καθαρισμός Τμήματος',
                          child: IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () {
                              textController.clear();
                              notifier.updateDepartmentText('');
                              onContentChecked();
                            },
                            tooltip: 'Καθαρισμός Τμήματος',
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        notifier.updateDepartmentText(value);
                        onContentChecked();
                      },
                      onSubmitted: (_) {
                        onContentChecked();
                        nextFocusNode.requestFocus();
                      },
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
  final CallHeaderState header;
  final LookupService? lookupService;
  final CallHeaderNotifier notifier;
  final VoidCallback onContentChecked;

  @override
  State<_EquipmentField> createState() => _EquipmentFieldState();
}

class _EquipmentFieldState extends State<_EquipmentField> {
  bool _isSelectingEquipment = false;
  bool _showInitialList = false;

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
    widget.focusNode.addListener(_onEquipmentFocusChange);
    widget.controller.addListener(_onEquipmentTextChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
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
    CallHeaderState header,
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
    CallHeaderState header,
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
    CallHeaderState header,
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
    CallHeaderState header,
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
    widget.controller.text = _equipmentFieldText(equipment);
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
          widget.controller.text = _equipmentFieldText(sel);
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
                return _querySuggestions(header, lookupService, value.text);
              },
              onSelected: (value) {
                _selectEquipment(value);
              },
              fieldViewBuilder:
                  (context, textController, focusNodeParam, onFieldSubmitted) {
                    return Semantics(
                      label: 'Κωδικός εξοπλισμού',
                      child: TextField(
                        controller: textController,
                        focusNode: focusNodeParam,
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
                                notifier.clearEquipment();
                              },
                              tooltip: 'Καθαρισμός Εξοπλισμού',
                            ),
                          ),
                        ),
                        onChanged: (value) {
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
                          // Θέλουμε να ενημερωθεί το equipmentText για να μπορεί να εμφανιστεί ο σταυρός άμεσα ή στο checkContent
                          notifier.checkContent(equipmentText: value);
                        },
                        onSubmitted: (_) {
                          widget.onContentChecked();
                          nextFocusNode.requestFocus();
                          _scheduleCompletedLookup();
                        },
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

class _PhoneHelperAndError extends StatelessWidget {
  const _PhoneHelperAndError({
    required this.header,
    required this.lookupService,
    required this.notifier,
  });

  final CallHeaderState header;
  final LookupService? lookupService;
  final CallHeaderNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final int? equipmentCount;
    if (header.selectedCaller != null &&
        header.selectedPhone != null &&
        lookupService != null) {
      equipmentCount = lookupService!
          .searchEquipmentsByPhone(header.selectedPhone!)
          .length;
    } else {
      equipmentCount = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (equipmentCount != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Βρέθηκαν $equipmentCount εξοπλισμοί',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (header.phoneError != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Προς υλοποίηση...')),
                );
              },
              child: Text(
                header.phoneError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
