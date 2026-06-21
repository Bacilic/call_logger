import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../provider/lookup_provider.dart';
import '../../provider/smart_entity_selector_provider.dart';
import 'smart_entity_selector_caller_field.dart';
import 'smart_entity_selector_department_field.dart';
import 'smart_entity_selector_equipment_field.dart';
import 'smart_entity_selector_phone_field.dart';
import 'smart_entity_selector_phone_presentational.dart';
import '../../layout/calls_field_groups_provider.dart';

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

/// Τηλέφωνο, Καλών, Τμήμα, Εξοπλισμός — Layout orchestrator για τα πεδία της φόρμας.
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
    _syncFieldConfirmations();
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
    final initial = ref.read(widget.provider);
    _phoneController = TextEditingController(text: initial.selectedPhone ?? '');
    _callerController = TextEditingController(text: initial.callerDisplayText);
    _departmentController = TextEditingController(text: initial.departmentText);
    _equipmentController = TextEditingController(text: initial.equipmentText);
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

  void _syncFieldConfirmations() {
    final conf = ref.read(callsFieldConfirmationsProvider.notifier);
    final header = ref.read(widget.provider);
    final phoneDigits =
        _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (phoneDigits.length >= 2) conf.confirmPhone();
    if (_equipmentController.text.trim().isNotEmpty) conf.confirmEquipment();
    if (header.selectedDepartmentId != null) conf.confirmDepartment();
    if (header.selectedCaller?.id != null) conf.confirmCaller();
  }

  void requestPhoneFocus() => _phoneFocusNode.requestFocus();

  /// Ίδια συμπεριφορά με το προηγούμενο κουμπί «Καθαρισμός όλων»: controllers + state + timer.
  void performClearAllFields() {
    ref.read(callsScreenExpandedLatchProvider.notifier).engage();
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
      final nextPhoneFromState = next.selectedPhone ?? '';
      if (nextPhoneFromState != _phoneController.text) {
        if (nextPhoneFromState.isEmpty &&
            _phoneController.text.isNotEmpty &&
            _phoneFocusNode.hasFocus) {
          // Κράτα preview πληκτρολογίου· το state είναι ακόμα κενό.
        } else {
          _phoneController.value = TextEditingValue(
            text: nextPhoneFromState,
            selection: TextSelection.collapsed(
              offset: nextPhoneFromState.length,
            ),
          );
        }
      }
      if (next.selectedCaller?.id != null &&
          next.selectedCaller?.id != previous?.selectedCaller?.id) {
        ref.read(callsFieldConfirmationsProvider.notifier).confirmCaller();
      }
      if (next.selectedDepartmentId != null &&
          next.selectedDepartmentId != previous?.selectedDepartmentId) {
        ref.read(callsFieldConfirmationsProvider.notifier).confirmDepartment();
      }
      if (next.selectedEquipment != null &&
          next.selectedEquipment?.id != previous?.selectedEquipment?.id) {
        ref.read(callsFieldConfirmationsProvider.notifier).confirmEquipment();
      }
      final phoneDigits =
          (next.selectedPhone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
      if (phoneDigits.length >= 2) {
        ref.read(callsFieldConfirmationsProvider.notifier).confirmPhone();
      }
      if (next.callerDisplayText != _callerController.text) {
        if (!(_callerFocusNode.hasFocus &&
            _callerController.text.trim().isNotEmpty &&
            next.callerDisplayText.trim() != _callerController.text.trim())) {
          _callerController.value = TextEditingValue(
            text: next.callerDisplayText,
            selection: TextSelection.collapsed(
              offset: next.callerDisplayText.length,
            ),
          );
        }
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
        final selectedCode = next.selectedEquipment?.code?.trim() ?? '';
        final controllerText = _equipmentController.text.trim();
        final skipEquipmentSync = _equipmentFocusNode.hasFocus &&
            controllerText.isNotEmpty &&
            next.equipmentText.trim() != controllerText;
        if (skipEquipmentSync) {
          // Κράτα preview πληκτρολογίου.
        } else if (selectedCode.isNotEmpty &&
            controllerText.isNotEmpty &&
            controllerText == selectedCode) {
          // controller είναι σωστό· το state θα συγχρονιστεί από setEquipment/checkContent.
        } else {
          _equipmentController.value = TextEditingValue(
            text: next.equipmentText,
            selection: TextSelection.collapsed(
              offset: next.equipmentText.length,
            ),
          );
        }
      }
    });

    final w1 = widget.w1;
    final w2 = widget.w2;
    final wDept = widget.wDept;
    final w3 = widget.w3;

    void contentChecked() {
      _notifier.checkContent(
        phoneText: _phoneController.text,
        callerText: _callerController.text,
        departmentText: _departmentController.text,
        equipmentText: _equipmentController.text,
      );
      _syncFieldConfirmations();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: w1,
              child: SmartEntityPhoneField(
                width: w1,
                controller: _phoneController,
                focusNode: _phoneFocusNode,
                nextFocusNode: _callerFocusNode,
                header: header,
                lookupService: lookupService,
                notifier: _notifier,
                onLessThan2DigitsSubmit: () {},
                onClearAll: performClearAllFields,
                onContentChecked: contentChecked,
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
              child: SmartEntityCallerField(
                width: w2,
                controller: _callerController,
                focusNode: _callerFocusNode,
                nextFocusNode: _departmentFocusNode,
                header: header,
                lookupService: lookupService,
                notifier: _notifier,
                getPhoneFieldDigits: () =>
                    _phoneController.text.replaceAll(RegExp(r'[^0-9]'), ''),
                onContentChecked: contentChecked,
                onCallerFocusOut: contentChecked,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: wDept,
              child: SmartEntityDepartmentField(
                width: wDept,
                controller: _departmentController,
                focusNode: _departmentFocusNode,
                nextFocusNode: _equipmentFocusNode,
                header: header,
                lookupService: lookupService,
                notifier: _notifier,
                onContentChecked: contentChecked,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: w3,
              child: SmartEntityEquipmentField(
                width: w3,
                controller: _equipmentController,
                focusNode: _equipmentFocusNode,
                nextFocusNode: _phoneFocusNode,
                header: header,
                lookupService: lookupService,
                notifier: _notifier,
                onContentChecked: contentChecked,
              ),
            ),
            ...widget.trailingRowChildren,
          ],
        ),
        const SizedBox(height: 4),
        SmartEntityPhoneHelperAndError(
          header: header,
          lookupService: lookupService,
          notifier: _notifier,
        ),
      ],
    );
  }
}
