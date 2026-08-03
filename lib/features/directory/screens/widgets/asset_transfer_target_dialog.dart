// Ο επιλογέας τμήματος προορισμού: ένα πεδίο autocomplete που δέχεται υπάρχον
// τμήμα ή προτείνει τη δημιουργία νέου με το κείμενο που πληκτρολογήθηκε.
//
// Χρησιμοποιείται και για ένα στοιχείο και για μαζική μεταφορά — η μόνη
// διαφορά είναι η επικεφαλίδα.

import 'package:flutter/material.dart';

import '../../../../core/utils/search_text_normalizer.dart';
import '../../models/department_model.dart';
import '../../services/asset_disconnect_models.dart';
import '../../services/asset_transfer_target_guard.dart';

/// Sentinel για την επιλογή «δημιουργία νέου τμήματος» στο autocomplete.
///
/// Γράφεται ως escape και όχι ως ο ίδιος ο χαρακτήρας: είναι από την περιοχή
/// ιδιωτικής χρήσης του Unicode, δηλαδή αόρατος σε κάθε επεξεργαστή κειμένου,
/// και ένα αθώο copy-paste τον εξαφανίζει — οπότε κάθε τμήμα θα εμφανιζόταν
/// ως «δημιουργία νέου».
const _kCreateDepartmentOptionPrefix = '\uE000';

bool _isCreateDepartmentOption(String option) =>
    option.startsWith(_kCreateDepartmentOptionPrefix);

String _createDepartmentOptionValue(String name) =>
    '$_kCreateDepartmentOptionPrefix$name';

String _departmentOptionLabel(String option) {
  if (_isCreateDepartmentOption(option)) {
    final name = option.substring(_kCreateDepartmentOptionPrefix.length);
    return 'Δημιουργία νέου τμήματος «$name»';
  }
  return option;
}

/// Επιλογή τμήματος προορισμού για ΕΝΑ στοιχείο (τηλέφωνο ή εξοπλισμό).
///
/// Το τμήμα-πηγή αποκλείεται: «μεταφορά εκεί που ήδη ανήκει» δεν είναι μεταφορά.
Future<SharedAssetTransferTarget?> showAssetTransferDialogForItem({
  required BuildContext context,
  required bool isPhone,
  required String value,
  int? sourceDepartmentId,
  required List<DepartmentModel> availableDepartments,
  List<String> blockedDepartmentNames = const [],
}) {
  return showDialog<SharedAssetTransferTarget>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _SharedAssetTransferDialog(
      isPhone: isPhone,
      value: value,
      departments: _selectableDepartments(
        availableDepartments,
        sourceDepartmentId: sourceDepartmentId,
      ),
      knownDepartments: _knownDepartments(availableDepartments),
      blockedDepartmentNames: blockedDepartmentNames,
    ),
  );
}

/// Επιλογή τμήματος προορισμού για ΠΟΛΛΑ στοιχεία, με δική της επικεφαλίδα.
///
/// Το [blockedDepartmentNames] κρατά τα τμήματα που διαγράφονται στην ίδια
/// πράξη: δεν αρκεί να λείπουν από τον κατάλογο, γιατί ο χρήστης μπορεί να
/// γράψει το όνομα με το χέρι και να ζητήσει «δημιουργία νέου».
Future<SharedAssetTransferTarget?> showAssetTransferTargetPicker({
  required BuildContext context,
  required String headerLabel,
  required List<DepartmentModel> availableDepartments,
  int? sourceDepartmentId,
  List<String> blockedDepartmentNames = const [],
}) {
  return showDialog<SharedAssetTransferTarget>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _SharedAssetTransferDialog(
      isPhone: true,
      value: '',
      departments: _selectableDepartments(
        availableDepartments,
        sourceDepartmentId: sourceDepartmentId,
      ),
      knownDepartments: _knownDepartments(availableDepartments),
      headerLabel: headerLabel,
      blockedDepartmentNames: blockedDepartmentNames,
    ),
  );
}

/// Τα τμήματα που μπορούν να επιλεγούν, αλφαβητικά — χωρίς διαγραμμένα,
/// χωρίς ανώνυμα και χωρίς το τμήμα-πηγή όταν δίνεται.
List<DepartmentModel> _selectableDepartments(
  List<DepartmentModel> availableDepartments, {
  int? sourceDepartmentId,
}) {
  return availableDepartments
      .where(
        (d) =>
            d.id != null &&
            (sourceDepartmentId == null || d.id != sourceDepartmentId) &&
            !d.isDeleted &&
            d.name.trim().isNotEmpty,
      )
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
}

/// Όλα τα ζωντανά τμήματα που ξέρει ο καλών — **μαζί** με το τμήμα-πηγή.
///
/// Χρειάζεται ξεχωριστά από τα επιλέξιμα: ένα όνομα που λείπει από τη λίστα
/// δεν σημαίνει ότι δεν υπάρχει, και «δημιουργία» θα ήταν ψέμα.
List<DepartmentModel> _knownDepartments(
  List<DepartmentModel> availableDepartments,
) {
  return availableDepartments
      .where((d) => d.id != null && !d.isDeleted && d.name.trim().isNotEmpty)
      .toList();
}

class _SharedAssetTransferDialog extends StatefulWidget {
  const _SharedAssetTransferDialog({
    required this.isPhone,
    required this.value,
    required this.departments,
    required this.knownDepartments,
    this.headerLabel,
    this.blockedDepartmentNames = const [],
  });

  final bool isPhone;
  final String value;

  /// Όσα προσφέρονται στη λίστα.
  final List<DepartmentModel> departments;

  /// Όσα υπάρχουν πραγματικά — υπερσύνολο των [departments].
  final List<DepartmentModel> knownDepartments;

  final String? headerLabel;
  final List<String> blockedDepartmentNames;

  @override
  State<_SharedAssetTransferDialog> createState() =>
      _SharedAssetTransferDialogState();
}

class _SharedAssetTransferDialogState
    extends State<_SharedAssetTransferDialog> {
  final _departmentController = TextEditingController();
  final _departmentFocus = FocusNode();

  List<String> get _departmentNames => widget.departments
      .map((d) => d.name.trim())
      .where((n) => n.isNotEmpty)
      .toList();

  @override
  void initState() {
    super.initState();
    _departmentController.addListener(_onDepartmentTextChanged);
  }

  void _onDepartmentTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _departmentController.removeListener(_onDepartmentTextChanged);
    _departmentController.dispose();
    _departmentFocus.dispose();
    super.dispose();
  }

  DepartmentModel? _matchDepartment(String text) =>
      _matchIn(widget.departments, text);

  /// Ταίριασμα σε ό,τι **υπάρχει**, ακόμα κι αν δεν προσφέρεται στη λίστα.
  DepartmentModel? _matchKnownDepartment(String text) =>
      _matchIn(widget.knownDepartments, text);

  DepartmentModel? _matchIn(List<DepartmentModel> list, String text) {
    final q = SearchTextNormalizer.normalizeForSearch(text.trim());
    if (q.isEmpty) return null;
    for (final d in list) {
      if (SearchTextNormalizer.normalizeForSearch(d.name) == q) return d;
    }
    return null;
  }

  /// Μήνυμα εμποδίου για ό,τι είναι γραμμένο τώρα στο πεδίο.
  String? get _blockedMessage => blockedTransferTargetMessage(
    typedName: _departmentController.text,
    blockedNames: widget.blockedDepartmentNames,
  );

  Iterable<String> _departmentOptions(String query) {
    final q = SearchTextNormalizer.normalizeForSearch(query);
    final matches = q.isEmpty
        ? List<String>.from(_departmentNames)
        : _departmentNames
              .where(
                (name) => SearchTextNormalizer.matchesNormalizedQuery(name, q),
              )
              .toList();
    final typed = query.trim();
    final isBlocked =
        blockedTransferTargetMessage(
          typedName: typed,
          blockedNames: widget.blockedDepartmentNames,
        ) !=
        null;
    // Η πρόταση «δημιουργία νέου» δεν εμφανίζεται καν για απαγορευμένο όνομα
    // (θα κατέληγε στο υπάρχον τμήμα που διαγράφεται) ούτε για όνομα που
    // **υπάρχει ήδη** — εκεί δεν δημιουργείται τίποτα.
    if (typed.isNotEmpty &&
        !isBlocked &&
        _matchKnownDepartment(typed) == null) {
      matches.add(_createDepartmentOptionValue(typed));
    }
    return matches;
  }

  Future<bool> _confirmCreateDepartment(String newName) async {
    final String content;
    final customHeader = widget.headerLabel;
    if (customHeader != null) {
      content = 'Θα δημιουργηθεί νέο τμήμα: $newName.';
    } else if (widget.isPhone) {
      content =
          'Θα δημιουργηθεί νέο τμήμα: $newName με κοινόχρηστο τηλέφωνο: ${widget.value}.';
    } else {
      content =
          'Θα δημιουργηθεί νέο τμήμα: $newName με κοινόχρηστο εξοπλισμό: ${widget.value}.';
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (confirmCtx) => AlertDialog(
        title: const Text('Δημιουργία νέου τμήματος'),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(confirmCtx).pop(false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(confirmCtx).pop(true),
            child: const Text('Επιβεβαίωση'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// Επιβεβαίωση όταν το όνομα υπάρχει ήδη — δεν δημιουργείται τίποτα.
  Future<bool> _confirmUseExistingDepartment(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (confirmCtx) => AlertDialog(
        title: const Text('Υπάρχον τμήμα'),
        content: Text(existingTransferTargetQuestion(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(confirmCtx).pop(false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(confirmCtx).pop(true),
            child: const Text('Μεταφορά εκεί'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _submitNewDepartment(String newName) async {
    // Ό,τι υπάρχει ήδη ΔΕΝ δημιουργείται: ο επιλυτής προορισμού είναι
    // get-or-create και θα κατέληγε σιωπηλά στο υπάρχον τμήμα.
    final existing = _matchKnownDepartment(newName);
    final existingId = existing?.id;
    if (existingId != null) {
      if (!await _confirmUseExistingDepartment(existing!.name.trim())) return;
      if (!mounted) return;
      Navigator.of(context).pop(SharedAssetTransferTarget.existing(existingId));
      return;
    }
    if (!await _confirmCreateDepartment(newName)) return;
    if (!mounted) return;
    Navigator.of(context).pop(SharedAssetTransferTarget.createNew(newName));
  }

  Future<void> _submit() async {
    final text = _departmentController.text.trim();
    if (text.isEmpty) return;
    // Δεύτερη γραμμή άμυνας: το κουμπί είναι ήδη ανενεργό, αλλά το Enter στο
    // πεδίο φτάνει κι εκείνο εδώ.
    if (_blockedMessage != null) return;
    final matched = _matchDepartment(text);
    if (matched?.id != null) {
      Navigator.of(
        context,
      ).pop(SharedAssetTransferTarget.existing(matched!.id!));
      return;
    }
    await _submitNewDepartment(text);
  }

  Future<void> _onDepartmentOptionSelected(String selection) async {
    final text = _isCreateDepartmentOption(selection)
        ? selection.substring(_kCreateDepartmentOptionPrefix.length)
        : selection;
    _departmentController.text = text;
    _departmentController.selection = TextSelection.collapsed(
      offset: text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocked = _blockedMessage;
    return AlertDialog(
      title: const Text('Μεταφορά κοινόχρηστου'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.headerLabel ??
                  (widget.isPhone
                      ? 'Τηλέφωνο: ${widget.value}'
                      : 'Εξοπλισμός: ${widget.value}'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            RawAutocomplete<String>(
              textEditingController: _departmentController,
              focusNode: _departmentFocus,
              displayStringForOption: _departmentOptionLabel,
              optionsBuilder: (textEditingValue) =>
                  _departmentOptions(textEditingValue.text),
              onSelected: (selection) => _onDepartmentOptionSelected(selection),
              fieldViewBuilder: (context, controller, focusNode, _) {
                // Το μήνυμα ΔΕΝ μπαίνει ως `errorText`: το `InputDecorator`
                // το θεωρεί μέρος του πεδίου, οπότε ο δείκτης γίνεται κέρσορας
                // κειμένου πάνω του και το κλικ εστιάζει το πεδίο. Μπαίνει
                // χωριστά από κάτω· εδώ κοκκινίζει μόνο το περίγραμμα.
                final errorBorder = OutlineInputBorder(
                  borderSide: BorderSide(color: theme.colorScheme.error),
                );
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: 'Τμήμα προορισμού',
                    border: const OutlineInputBorder(),
                    enabledBorder: blocked == null ? null : errorBorder,
                    focusedBorder: blocked == null
                        ? null
                        : OutlineInputBorder(
                            borderSide: BorderSide(
                              color: theme.colorScheme.error,
                              width: 2,
                            ),
                          ),
                    labelStyle: blocked == null
                        ? null
                        : TextStyle(color: theme.colorScheme.error),
                  ),
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _submit(),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                final opts = options.toList();
                if (opts.isEmpty) return const SizedBox.shrink();
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 400,
                        maxHeight: 220,
                      ),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: opts.length,
                        itemBuilder: (context, index) {
                          final option = opts[index];
                          final isCreate = _isCreateDepartmentOption(option);
                          return ListTile(
                            dense: true,
                            leading: isCreate
                                ? Icon(
                                    Icons.add_circle_outline,
                                    color: theme.colorScheme.primary,
                                  )
                                : null,
                            title: Text(
                              _departmentOptionLabel(option),
                              style: isCreate
                                  ? TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    )
                                  : null,
                            ),
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            if (blocked != null) ...[
              const SizedBox(height: 8),
              Text(
                blocked,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed:
              _departmentController.text.trim().isEmpty || blocked != null
              ? null
              : _submit,
          child: const Text('Μεταφορά'),
        ),
      ],
    );
  }
}
