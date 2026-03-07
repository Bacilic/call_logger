import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/lookup_service.dart';
import '../../models/equipment_model.dart';
import '../../models/user_model.dart';
import '../../provider/call_header_provider.dart';
import '../../provider/lookup_provider.dart';

/// Header φόρμα εισαγωγής κλήσης: τρία Autocomplete (Εσωτερικό, Καλούντας, Κωδικός Εξοπλισμού).
class CallHeaderForm extends ConsumerStatefulWidget {
  const CallHeaderForm({super.key});

  @override
  ConsumerState<CallHeaderForm> createState() => _CallHeaderFormState();
}

class _CallHeaderFormState extends ConsumerState<CallHeaderForm> {
  late final TextEditingController _phoneController;
  late final TextEditingController _callerController;
  late final TextEditingController _equipmentController;
  late final FocusNode _phoneFocusNode;
  late final FocusNode _callerFocusNode;
  late final FocusNode _equipmentFocusNode;
  late final CallHeaderNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();
    _callerController = TextEditingController();
    _equipmentController = TextEditingController();
    _phoneFocusNode = FocusNode();
    _callerFocusNode = FocusNode();
    _equipmentFocusNode = FocusNode();
    _notifier = ref.read(callHeaderProvider.notifier);
    _notifier.registerFocusNodes(
      phone: _phoneFocusNode,
      caller: _callerFocusNode,
      equipment: _equipmentFocusNode,
    );
  }

  @override
  void dispose() {
    _notifier.unregisterFocusNodes();
    _phoneFocusNode.dispose();
    _callerFocusNode.dispose();
    _equipmentFocusNode.dispose();
    _phoneController.dispose();
    _callerController.dispose();
    _equipmentController.dispose();
    super.dispose();
  }

  static List<String> _sortPhonesByRecent(
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

  @override
  Widget build(BuildContext context) {
    final header = ref.watch(callHeaderProvider);
    final lookupAsync = ref.watch(lookupServiceProvider);
    final lookupService = lookupAsync.value;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final w1 = (screenWidth / 5).clamp(0.0, 180.0);
    final w2 = (screenWidth / 5).clamp(0.0, 220.0);
    final w3 = (screenWidth / 5).clamp(0.0, 200.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PhoneField(
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
                _equipmentController.clear();
                _notifier.clearAll();
              },
            ),
            const SizedBox(width: 12),
            _CallerField(
              width: w2,
              controller: _callerController,
              focusNode: _callerFocusNode,
              nextFocusNode: _equipmentFocusNode,
              lookupService: lookupService,
              notifier: _notifier,
            ),
            const SizedBox(width: 12),
            _EquipmentField(
              width: w3,
              controller: _equipmentController,
              focusNode: _equipmentFocusNode,
              nextFocusNode: _phoneFocusNode,
              selectedPhone: header.selectedPhone,
              lookupService: lookupService,
              notifier: _notifier,
            ),
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

  @override
  State<_PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<_PhoneField> {
  /// Lookup τηλεφώνου: κάρτα/error εμφανίζεται μόνο εδώ.
  void _performLookup() {
    final digits = widget.controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 2 && widget.lookupService != null) {
      final result = widget.lookupService!.search(digits);
      if (result != null) {
        widget.notifier.setCaller(result.user);
        widget.notifier.setEquipment(
          result.equipment.isNotEmpty ? result.equipment.first : null,
        );
        widget.notifier.markPhoneUsed(digits);
        widget.notifier.clearPhoneError();
      } else {
        widget.notifier.setCaller(null);
        widget.notifier.setEquipment(null);
        widget.notifier.setPhoneError('Άγνωστο τηλέφωνο – Προσθήκη;');
      }
    } else {
      widget.notifier.setCaller(null);
      widget.notifier.setEquipment(null);
      widget.notifier.clearPhoneError();
    }
  }

  void _onFocusChange() {
    if (widget.focusNode.hasFocus) {
      return;
    }
    _performLookup();
  }

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
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

    return SizedBox(
      width: width,
      child: MergeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Τηλέφωνο', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Autocomplete<String>(
              focusNode: focusNode,
              textEditingController: controller,
              optionsBuilder: (value) {
                final text = value.text.replaceAll(RegExp(r'[^0-9]'), '');
                if (text.length < 2) return const Iterable<String>.empty();
                final list = lookupService?.searchPhonesByPrefix(text) ?? [];
                return _CallHeaderFormState._sortPhonesByRecent(
                  list,
                  header.recentPhones,
                );
              },
              onSelected: (value) {
                controller.text = value;
                notifier.updatePhone(value);
                final result = lookupService?.search(value.replaceAll(RegExp(r'[^0-9]'), ''));
                if (result != null) {
                  notifier.setCaller(result.user);
                  notifier.setEquipment(
                    result.equipment.isNotEmpty ? result.equipment.first : null,
                  );
                  notifier.markPhoneUsed(value);
                  notifier.clearPhoneError();
                }
              },
              fieldViewBuilder: (
                context,
                textController,
                focusNodeParam,
                onFieldSubmitted,
              ) {
                return Semantics(
                  label: 'Αριθμός τηλεφώνου',
                  child: TextField(
                    controller: textController,
                    focusNode: focusNodeParam,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'π.χ. 2345',
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
                    onChanged: (value) {
                    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
                    notifier.updatePhone(digits.isEmpty ? null : digits);
                    notifier.setCaller(null);
                    notifier.setEquipment(null);
                    notifier.clearPhoneError();
                  },
                  onSubmitted: (value) {
                    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
                    if (digits.length < 2) {
                      onLessThan2DigitsSubmit();
                      return;
                    }
                    nextFocusNode.requestFocus();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _performLookup();
                    });
                  },
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

class _CallerField extends StatelessWidget {
  const _CallerField({
    required this.width,
    required this.controller,
    required this.focusNode,
    required this.nextFocusNode,
    required this.lookupService,
    required this.notifier,
  });

  final double width;
  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode nextFocusNode;
  final LookupService? lookupService;
  final CallHeaderNotifier notifier;

  static String _displayStringForOption(UserModel u) {
    return u.name ?? u.phone ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: MergeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Καλούντας', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Autocomplete<UserModel>(
              displayStringForOption: _displayStringForOption,
              focusNode: focusNode,
              textEditingController: controller,
              optionsBuilder: (value) {
                final q = value.text.trim();
                if (q.isEmpty) return const Iterable<UserModel>.empty();
                return lookupService?.searchUsersByQuery(q) ?? [];
              },
              onSelected: (value) {
                controller.text = _displayStringForOption(value);
                notifier.setCaller(value);
              },
              fieldViewBuilder: (
                context,
                textController,
                focusNodeParam,
                onFieldSubmitted,
              ) {
                return Semantics(
                  label: 'Όνομα καλούντος',
                  child: TextField(
                    controller: textController,
                    focusNode: focusNodeParam,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: Semantics(
                      label: 'Καθαρισμός Καλούντα',
                      child: IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          textController.clear();
                          notifier.clearCaller();
                        },
                        tooltip: 'Καθαρισμός Καλούντα',
                      ),
                    ),
                    ),
                    onSubmitted: (_) => nextFocusNode.requestFocus(),
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

class _EquipmentField extends StatelessWidget {
  const _EquipmentField({
    required this.width,
    required this.controller,
    required this.focusNode,
    required this.nextFocusNode,
    required this.selectedPhone,
    required this.lookupService,
    required this.notifier,
  });

  final double width;
  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode nextFocusNode;
  final String? selectedPhone;
  final LookupService? lookupService;
  final CallHeaderNotifier notifier;

  static String _displayStringForOption(EquipmentModel e) {
    return e.code ?? e.type ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: MergeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Κωδικός Εξοπλισμού',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Autocomplete<EquipmentModel>(
              displayStringForOption: _displayStringForOption,
              focusNode: focusNode,
              textEditingController: controller,
              optionsBuilder: (value) {
                if (selectedPhone == null || selectedPhone!.length < 3) {
                  return const Iterable<EquipmentModel>.empty();
                }
                return lookupService?.searchEquipmentsByPhone(selectedPhone!) ??
                    [];
              },
              onSelected: (value) {
                controller.text = _displayStringForOption(value);
                notifier.setEquipment(value);
              },
              fieldViewBuilder: (
                context,
                textController,
                focusNodeParam,
                onFieldSubmitted,
              ) {
                return Semantics(
                  label: 'Κωδικός εξοπλισμού',
                  child: TextField(
                    controller: textController,
                    focusNode: focusNodeParam,
                    decoration: InputDecoration(
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
                    onSubmitted: (_) => nextFocusNode.requestFocus(),
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
