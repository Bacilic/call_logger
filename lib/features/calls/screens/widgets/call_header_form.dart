import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/lookup_service.dart';
import '../../../../core/utils/name_parser.dart';
import '../../../../core/utils/search_text_normalizer.dart';
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

  void _onFocusOut() {
    _notifier.checkContent();
  }

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
    _notifier.registerControllers(
      phone: _phoneController,
      caller: _callerController,
      equipment: _equipmentController,
    );
    _phoneFocusNode.addListener(_onFocusOut);
    _callerFocusNode.addListener(_onFocusOut);
    _equipmentFocusNode.addListener(_onFocusOut);
  }

  @override
  void dispose() {
    _phoneFocusNode.removeListener(_onFocusOut);
    _callerFocusNode.removeListener(_onFocusOut);
    _equipmentFocusNode.removeListener(_onFocusOut);
    _notifier.unregisterFocusNodes();
    _notifier.unregisterControllers();
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
    final w2 = (screenWidth * 0.35).clamp(220.0, 250.0); // Πιο φαρδύ για μεγάλα ονόματα καλούντος
    final w3 = (screenWidth / 5).clamp(0.0, 200.0);

    final hasAnyContent = ref.watch(
      callHeaderProvider.select((s) => s.hasAnyContent),
    );
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
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
                  _equipmentController.clear();
                  _notifier.clearAll();
                  _phoneFocusNode.requestFocus();
                },
                onContentChecked: () => _notifier.checkContent(),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              flex: 2,
              child: _CallerField(
                width: w2,
                controller: _callerController,
                focusNode: _callerFocusNode,
                nextFocusNode: _equipmentFocusNode,
                header: header,
                lookupService: lookupService,
                notifier: _notifier,
                onContentChecked: () => _notifier.checkContent(),
                onCallerFocusOut: () => _notifier.checkContent(),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: _EquipmentField(
                width: w3,
                controller: _equipmentController,
                focusNode: _equipmentFocusNode,
                nextFocusNode: _phoneFocusNode,
                header: header,
                lookupService: lookupService,
                notifier: _notifier,
                onContentChecked: () => _notifier.checkContent(),
              ),
            ),
            const SizedBox(width: 8),
            IgnorePointer(
              ignoring: !hasAnyContent,
              child: AnimatedOpacity(
                opacity: hasAnyContent ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 180),
                child: AnimatedScale(
                  scale: hasAnyContent ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: IconButton(
                    icon: Icon(Icons.clear, color: theme.colorScheme.error),
                    tooltip: 'Καθαρισμός όλων των πεδίων',
                    onPressed: () {
                      _phoneController.clear();
                      _callerController.clear();
                      _equipmentController.clear();
                      _notifier.clearAll();
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
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final msg =
                      await _notifier.associateCurrentIfNeeded();
                  if (mounted && msg != null) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(msg)),
                    );
                  }
                },
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
    required this.onContentChecked,
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

  @override
  State<_PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<_PhoneField> {
  /// Lookup τηλεφώνου: χρήση performPhoneLookup για 0/1/πολλά αποτελέσματα.
  void _performLookup() {
    final digits = widget.controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 3) {
      widget.notifier.performPhoneLookup(digits);
      widget.notifier.markPhoneUsed(digits);
    }
  }

  void _scheduleCompletedLookup() {
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _performLookup();
    });
  }

  void _onFocusChange() {
    if (widget.focusNode.hasFocus) {
      return;
    }
    _scheduleCompletedLookup();
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
    final onContentChecked = widget.onContentChecked;

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
                notifier.markPhoneUsed(value);
                notifier.performPhoneLookup(value.replaceAll(RegExp(r'[^0-9]'), ''));
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
                      hintStyle: TextStyle(
                        color: Theme.of(context).hintColor, // χρησιμοποιεί το system "αγνό γκρι" hint
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
                    onChanged: (value) {
                    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
                    notifier.updatePhone(digits.isEmpty ? null : digits);
                  },
                  onSubmitted: (value) {
                    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
                    if (digits.length < 2) {
                      onLessThan2DigitsSubmit();
                      return;
                    }
                    onContentChecked();
                    nextFocusNode.requestFocus();
                    _scheduleCompletedLookup();
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

  String _extractDisplayName(String selection) {
    if (selection == 'Άγνωστος') {
      return selection;
    }
    final idx = selection.indexOf(' (');
    if (idx <= 0) {
      return selection.trim();
    }
    return selection.substring(0, idx).trim();
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
      return user.fullNameWithDepartment == selection || user.name == displayName;
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
      // Καθυστέρηση κλεισίματος για να προλάβει το onTap αν ο χρήστης πατήσει στη λίστα
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
            Text('Καλούντας', style: theme.textTheme.labelMedium),
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
                      : (lookupService?.searchUsersByQuery(textEditingValue.text.trim()) ?? []);
                  for (final u in users) {
                    options.add(u.fullNameWithDepartment);
                  }
                }
                return options
                    .where((option) =>
                        SearchTextNormalizer.matchesNormalizedQuery(option, q))
                    .toList();
              },
              onSelected: (String selection) {
                if (selection == 'Άγνωστος') {
                  notifier.updateSelectedCaller(null);
                  notifier.updateCallerDisplayText('Άγνωστος');
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
                  if (foundUser?.id != null) {
                    notifier.performEquipmentLookup(foundUser!.id!);
                  }
                  _onSuggestionSelected();
                }
              },
              fieldViewBuilder: (
                context,
                textController,
                focusNodeParam,
                onFieldSubmitted,
              ) {
                return Semantics(
                  label: 'Όνομα καλούντος',
                  child: SizedBox(
                    width: width,
                    child: TextField(
                      controller: textController,
                      focusNode: focusNodeParam,
                      decoration: InputDecoration(
                        hintText: hintText,
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
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
                        if (header.selectedCaller != null) {
                          final n = header.selectedCaller!.name;
                          final f = header.selectedCaller!.fullNameWithDepartment;
                          if (value.trim() != n && value.trim() != f) {
                            notifier.updateSelectedCaller(null);
                          }
                        }
                      }
                    },
                    onSubmitted: (_) {
                      widget.onContentChecked();
                      nextFocusNode.requestFocus();
                    },
                  ),
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
  const _CallerParseHint({
    required this.header,
    required this.theme,
  });

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
              style: style.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
    final callerDisplayName = header.selectedCaller?.name ??
        header.selectedCaller?.fullNameWithDepartment ??
        '';
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      elevation: 1,
      borderRadius: BorderRadius.circular(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
              onTap: () {
                notifier.updateSelectedCaller(null);
                notifier.updateCallerDisplayText('Άγνωστος');
                controller.text = 'Άγνωστος';
                onSelectionCommitted?.call();
              },
            ),
        ],
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

  @override
  void initState() {
    super.initState();
    _showInitialList = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_onEquipmentFocusChange);
    widget.controller.addListener(_onEquipmentTextChange);
  }

  @override
  void dispose() {
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
      // Καθυστέρηση κλεισίματος για να προλάβει το onTap αν ο χρήστης πατήσει στη λίστα
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
          _EquipmentSuggestion(
            equipment: equipment,
            sourceLabel: 'Τηλέφωνο',
          ),
        );
      }
    }

    for (final equipment in callerEquipments) {
      final key = _equipmentKey(equipment);
      if (!phoneKeys.contains(key) && seen.add(key)) {
        combined.add(
          _EquipmentSuggestion(
            equipment: equipment,
            sourceLabel: 'Όνομα',
          ),
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
    final q = SearchTextNormalizer.normalizeForSearch(query);
    if (q.isEmpty) {
      return const [];
    }
    final base = _initialSuggestions(header, lookupService)
        .map((entry) => entry.equipment)
        .toList();
    return _dedupeEquipments(
      base.where((equipment) {
        final normalizedLabel = SearchTextNormalizer.normalizeForSearch(
          equipment.displayLabel,
        );
        final normalizedCode = SearchTextNormalizer.normalizeForSearch(
          equipment.code ?? '',
        );
        return normalizedLabel.contains(q) || normalizedCode.contains(q);
      }),
    );
  }

  /// Κείμενο για το πλαίσιο εισαγωγής: μόνο κωδικός (η λίστα δείχνει κωδικός + τύπο).
  static String _equipmentFieldText(EquipmentModel e) =>
      e.code?.trim().isNotEmpty == true ? e.code!.trim() : e.displayLabel;

  void _selectEquipment(EquipmentModel equipment) {
    _isSelectingEquipment = true;
    widget.controller.text = _equipmentFieldText(equipment);
    widget.notifier.setEquipment(equipment);
    widget.notifier.checkContent();
    setState(() {
      _showInitialList = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _isSelectingEquipment = false;
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
    if (sel != null && widget.controller.text != _equipmentFieldText(sel)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.controller.text = _equipmentFieldText(sel);
        }
      });
    }
    if (sel == null &&
        oldWidget.header.selectedEquipment != null &&
        !_isSelectingEquipment &&
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
            Text(
              'Κωδικός Εξοπλισμού',
              style: theme.textTheme.labelMedium,
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
                        hintText: hintText,
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
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
                          notifier.checkContent();
                          return;
                        }
                        final selected = header.selectedEquipment;
                        if (selected != null &&
                            value != _equipmentFieldText(selected)) {
                          notifier.clearEquipment();
                        }
                        // Θέλουμε να ενημερωθεί το equipmentText για να μπορεί να εμφανιστεί ο σταυρός άμεσα ή στο checkContent
                        notifier.checkContent();
                      },
                      onSubmitted: (_) {
                        widget.onContentChecked();
                        nextFocusNode.requestFocus();
                      },
                    ),
                  );
                },
              ),
            if (showInitialSuggestionList)
              _EquipmentSuggestionList(
                suggestions: initialSuggestions,
                theme: theme,
                onSelected: _selectEquipment,
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
