import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/settings_service.dart';
import '../../../../core/utils/greek_date_format.dart';
import '../../models/catalog_validation_finding.dart';
import '../../models/catalog_validation_rules.dart';
import '../../providers/catalog_validation_provider.dart';
import '../../services/catalog_scan_runner.dart';

/// Υπο-οθόνη «Κανόνες επικύρωσης» του hub «Διάφορα».
///
/// Όλοι οι κανόνες είναι προειδοποιήσεις — δεν εμποδίζουν ποτέ την
/// αποθήκευση. Κάθε αλλαγή αποθηκεύεται αμέσως στο app_settings της
/// ενεργής βάσης και ακυρώνει την cache των κανόνων.
class ValidationRulesView extends ConsumerStatefulWidget {
  const ValidationRulesView({super.key});

  @override
  ConsumerState<ValidationRulesView> createState() =>
      _ValidationRulesViewState();
}

class _ValidationRulesViewState extends ConsumerState<ValidationRulesView> {
  CatalogValidationRules? _rules;

  /// Αποτελέσματα του τελευταίου ελέγχου· `null` = δεν έχει τρέξει ακόμη.
  List<CatalogValidationFinding>? _findings;
  bool _scanning = false;

  late final TextEditingController _internalDigitsController;
  late final TextEditingController _externalDigitsController;
  late final TextEditingController _prefixFromController;
  late final TextEditingController _prefixToController;
  late final TextEditingController _equipmentMinController;
  late final TextEditingController _equipmentMaxController;
  late final TextEditingController _allowedSymbolsController;

  @override
  void initState() {
    super.initState();
    _internalDigitsController = TextEditingController();
    _externalDigitsController = TextEditingController();
    _prefixFromController = TextEditingController();
    _prefixToController = TextEditingController();
    _equipmentMinController = TextEditingController();
    _equipmentMaxController = TextEditingController();
    _allowedSymbolsController = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    final rules = await ref.read(catalogValidationRulesProvider.future);
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _internalDigitsController.text = '${rules.internalPhoneDigits}';
      _externalDigitsController.text = '${rules.externalPhoneDigits}';
      _prefixFromController.text = '${rules.internalPrefixFrom}';
      _prefixToController.text = '${rules.internalPrefixTo}';
      _equipmentMinController.text = '${rules.equipmentMinDigits}';
      _equipmentMaxController.text = '${rules.equipmentMaxDigits}';
      _allowedSymbolsController.text = rules.personNameAllowedSymbols;
    });
  }

  @override
  void dispose() {
    _internalDigitsController.dispose();
    _externalDigitsController.dispose();
    _prefixFromController.dispose();
    _prefixToController.dispose();
    _equipmentMinController.dispose();
    _equipmentMaxController.dispose();
    _allowedSymbolsController.dispose();
    super.dispose();
  }

  /// Άμεση αποθήκευση + ακύρωση cache, ώστε οι φόρμες να δουν τους νέους
  /// κανόνες χωρίς επανεκκίνηση.
  void _apply(CatalogValidationRules next) {
    setState(() {
      _rules = next;
      // Τα ευρήματα προήλθαν από τους ΠΑΛΙΟΥΣ κανόνες — παύουν να ισχύουν.
      _findings = null;
    });
    SettingsService().catalogs.setCatalogValidationRulesRaw(next.toRawJson());
    ref.invalidate(catalogValidationRulesProvider);
    // Ο service παρακολουθεί τους κανόνες με watch: χωρίς άμεσο ξέπλυμα η
    // αλυσίδα μένει «dirty» (καμία φόρμα ανοιχτή εδώ) και ξεπλένεται σύγχρονα
    // μέσα στο build της επόμενης φόρμας καταλόγου → «setState during build».
    flushCatalogValidationProviderChain(ref);
  }

  Future<void> _runScan() async {
    setState(() => _scanning = true);
    try {
      final findings = await CatalogScanRunner.scan(ref);
      if (!mounted) return;
      setState(() => _findings = findings);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// Άνοιγμα της καρτέλας μιας εγγραφής ευρήματος· μετά το κλείσιμο ο
  /// έλεγχος ξανατρέχει, ώστε η λίστα να δείχνει την πραγματικότητα και
  /// όχι ευρήματα που μόλις διορθώθηκαν.
  Future<void> _openRecord(CatalogFindingRecord record) async {
    await CatalogScanRunner.openRecord(context, ref, record);
    if (!mounted) return;
    await _runScan();
  }

  int? _parseInRange(String text, int min, int max) {
    final value = int.tryParse(text.trim());
    if (value == null || value < min || value > max) return null;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final rules = _rules;
    if (rules == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WarningBanner(theme: theme),
              const SizedBox(height: 12),
              _RuleCard(
                icon: Icons.phone_outlined,
                title: 'Τηλέφωνα',
                children: [
                  _RuleRow(
                    enabled: rules.internalPhoneDigitsEnabled,
                    onToggle: (v) =>
                        _apply(rules.copyWith(internalPhoneDigitsEnabled: v)),
                    example:
                        'Παράδειγμα υπόδειξης: «Το 253 έχει 3 ψηφία — '
                        'τα εσωτερικά έχουν ${rules.internalPhoneDigits}»',
                    child: _InlineNumberField(
                      label: 'Ψηφία εσωτερικών τηλεφώνων:',
                      controller: _internalDigitsController,
                      maxLength: 2,
                      onCommitted: (text) {
                        final v = _parseInRange(text, 1, 15);
                        if (v != null) {
                          _apply(rules.copyWith(internalPhoneDigits: v));
                        }
                      },
                    ),
                  ),
                  _RuleRow(
                    enabled: rules.externalPhoneDigitsEnabled,
                    onToggle: (v) =>
                        _apply(rules.copyWith(externalPhoneDigitsEnabled: v)),
                    example:
                        'Παράδειγμα υπόδειξης: «Το 210123456 έχει 9 ψηφία — '
                        'αναμένονται ${rules.internalPhoneDigits} (εσωτερικό) '
                        'ή ${rules.externalPhoneDigits} (εξωτερικό)»',
                    child: _InlineNumberField(
                      label: 'Ψηφία εξωτερικών τηλεφώνων:',
                      controller: _externalDigitsController,
                      maxLength: 2,
                      onCommitted: (text) {
                        final v = _parseInRange(text, 1, 15);
                        if (v != null) {
                          _apply(rules.copyWith(externalPhoneDigits: v));
                        }
                      },
                    ),
                  ),
                  _RuleRow(
                    enabled: rules.internalPrefixEnabled,
                    onToggle: (v) =>
                        _apply(rules.copyWith(internalPrefixEnabled: v)),
                    note:
                        'Ελέγχεται μόνο σε αριθμούς με '
                        '${rules.internalPhoneDigits} ψηφία — τα εξωτερικά '
                        'δεν εξετάζονται',
                    example:
                        'Παράδειγμα υπόδειξης: «Το 3122 δεν ξεκινά από '
                        '${rules.internalPrefixFrom}–${rules.internalPrefixTo}»',
                    child: _InlineRangeFields(
                      label: 'Πρόθεμα εσωτερικών: από',
                      fromController: _prefixFromController,
                      toController: _prefixToController,
                      onCommitted: (fromText, toText) {
                        final from = _parseInRange(fromText, 10, 99);
                        final to = _parseInRange(toText, 10, 99);
                        if (from != null && to != null && from <= to) {
                          _apply(
                            rules.copyWith(
                              internalPrefixFrom: from,
                              internalPrefixTo: to,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _RuleCard(
                icon: Icons.computer_outlined,
                title: 'Εξοπλισμός',
                children: [
                  _RuleRow(
                    enabled: rules.equipmentDigitsEnabled,
                    onToggle: (v) =>
                        _apply(rules.copyWith(equipmentDigitsEnabled: v)),
                    example:
                        'Παράδειγμα υπόδειξης: «Το 25067 έχει 5 ψηφία — '
                        'αναμένονται ${rules.equipmentMinDigits} έως '
                        '${rules.equipmentMaxDigits}»',
                    child: _InlineRangeFields(
                      label: 'Ψηφία κωδικού: από',
                      fromController: _equipmentMinController,
                      toController: _equipmentMaxController,
                      onCommitted: (fromText, toText) {
                        final min = _parseInRange(fromText, 1, 15);
                        final max = _parseInRange(toText, 1, 15);
                        if (min != null && max != null && min <= max) {
                          _apply(
                            rules.copyWith(
                              equipmentMinDigits: min,
                              equipmentMaxDigits: max,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _RuleCard(
                icon: Icons.apartment_outlined,
                title: 'Τμήματα',
                children: [
                  _RuleRow(
                    enabled: rules.departmentNameEnabled,
                    onToggle: (v) =>
                        _apply(rules.copyWith(departmentNameEnabled: v)),
                    example:
                        'Παράδειγμα υπόδειξης: «Το 2545 μοιάζει με τηλέφωνο, '
                        'όχι με όνομα τμήματος»',
                    child: Text(
                      'Το όνομα να μη μοιάζει με αριθμό ή τηλέφωνο',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _RuleCard(
                icon: Icons.person_outline,
                title: 'Υπάλληλοι',
                children: [
                  _RuleRow(
                    enabled: rules.personNameEnabled,
                    onToggle: (v) =>
                        _apply(rules.copyWith(personNameEnabled: v)),
                    example:
                        'Παράδειγμα υπόδειξης: «Το 3π ξεκινά από ψηφίο — '
                        'σωστό μόνο αν είναι εταιρεία»',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Όνομα και επώνυμο να μην ξεκινούν από ψηφίο '
                          'ή σύμβολο',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              'Εξαιρούνται τα σύμβολα:',
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 140,
                              child: TextField(
                                controller: _allowedSymbolsController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  hintText: '(, -',
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (text) => _apply(
                                  rules.copyWith(
                                    personNameAllowedSymbols: text,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Χωρισμένα με κόμμα. Τα ψηφία δεν εξαιρούνται ποτέ. '
                          'Η ανοιχτή παρένθεση επιτρέπει το «(Γωγώ) Γεωργία».',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _RuleCard(
                icon: Icons.compare_arrows_outlined,
                title: 'Διασταυρώσεις',
                subtitle:
                    'Κοιτούν ολόκληρο τον κατάλογο — τρέχουν μόνο στον '
                    '«Έλεγχο δεδομένων», όχι στις φόρμες.',
                children: [
                  _RuleRow(
                    enabled: rules.emptyDepartmentEnabled,
                    onToggle: (v) =>
                        _apply(rules.copyWith(emptyDepartmentEnabled: v)),
                    note:
                        'Δεν είναι σφάλμα — ένα τμήμα μπορεί να αδειάσει '
                        'θεμιτά· η υπόδειξη θυμίζει να αποφασίσετε τι το κάνετε',
                    example:
                        'Παράδειγμα υπόδειξης: «Δεν έχει κανέναν υπάλληλο, '
                        'κοινόχρηστο τηλέφωνο ή εξοπλισμό»',
                    child: Text(
                      'Τμήματα χωρίς κανένα εξάρτημα',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  _RuleRow(
                    enabled: rules.phoneEquipmentCodeEnabled,
                    onToggle: (v) =>
                        _apply(rules.copyWith(phoneEquipmentCodeEnabled: v)),
                    example:
                        'Παράδειγμα υπόδειξης: «Το 3685 είναι καταχωρημένος '
                        'κωδικός εξοπλισμού — ίσως γράφτηκε σε λάθος πεδίο»',
                    child: Text(
                      'Τηλέφωνο που ταυτίζεται με κωδικό εξοπλισμού',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  _RuleRow(
                    enabled: rules.swappedNamesEnabled,
                    onToggle: (v) =>
                        _apply(rules.copyWith(swappedNamesEnabled: v)),
                    example:
                        'Παράδειγμα υπόδειξης: «Πιθανό ίδιο πρόσωπο με '
                        'αντεστραμμένα πεδία»',
                    child: Text(
                      'Υπάλληλοι με αντεστραμμένο όνομα/επώνυμο',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  _RuleRow(
                    enabled: rules.duplicateNamesEnabled,
                    onToggle: (v) =>
                        _apply(rules.copyWith(duplicateNamesEnabled: v)),
                    example:
                        'Παράδειγμα υπόδειξης: «Ίδιο ονοματεπώνυμο σε 2 '
                        'εγγραφές — πιθανό διπλότυπο»',
                    child: Text(
                      'Υπάλληλοι με ολόιδιο ονοματεπώνυμο',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  _RuleRow(
                    enabled: rules.crossDepartmentPhoneEnabled,
                    onToggle: (v) =>
                        _apply(rules.copyWith(crossDepartmentPhoneEnabled: v)),
                    note:
                        'Στο ίδιο τμήμα το κοινό τηλέφωνο βάρδιας είναι '
                        'θεμιτό και δεν ελέγχεται',
                    example:
                        'Παράδειγμα υπόδειξης: «Το 2534 είναι καταχωρημένο '
                        'σε 2 υπαλλήλους σε 2 τμήματα»',
                    child: Text(
                      'Ίδιο τηλέφωνο σε υπαλλήλους διαφορετικών τμημάτων',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  _RuleRow(
                    enabled: rules.equipmentOwnerDepartmentEnabled,
                    onToggle: (v) => _apply(
                      rules.copyWith(equipmentOwnerDepartmentEnabled: v),
                    ),
                    example:
                        'Παράδειγμα υπόδειξης: «Χρεωμένος στην εγγραφή '
                        '«Ψαρρά Σοφία» (Γραμματεία ΤΕΠ), ενώ ανήκει στο '
                        '«Χειρουργική»»',
                    child: Text(
                      'Εξοπλισμός χρεωμένος σε υπάλληλο άλλου τμήματος',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _ScanSection(
                scanning: _scanning,
                findings: _findings,
                onScan: _runScan,
                onOpenRecord: _openRecord,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Τμήμα «Έλεγχος δεδομένων»: κουμπί εκκίνησης και αποτελέσματα.
class _ScanSection extends StatelessWidget {
  const _ScanSection({
    required this.scanning,
    required this.findings,
    required this.onScan,
    required this.onOpenRecord,
  });

  final bool scanning;
  final List<CatalogValidationFinding>? findings;
  final Future<void> Function() onScan;
  final Future<void> Function(CatalogFindingRecord record) onOpenRecord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = findings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: FilledButton.icon(
            onPressed: scanning ? null : () => onScan(),
            icon: scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fact_check_outlined),
            label: Text(scanning ? 'Γίνεται έλεγχος…' : 'Έλεγχος δεδομένων'),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Σαρώνει τις υπάρχουσες εγγραφές του καταλόγου με τους '
            'ενεργούς κανόνες.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
        if (results != null) ...[
          const SizedBox(height: 16),
          if (results.isEmpty)
            _CleanResultBanner(theme: theme)
          else ...[
            Text(
              results.length == 1
                  ? 'Βρέθηκε 1 παρατυπία'
                  : 'Βρέθηκαν ${results.length} παρατυπίες',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Επιλέξτε μια γραμμή για να ανοίξει η καρτέλα της.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            for (final finding in results)
              if (finding.isConflict)
                _ConflictCard(finding: finding, onOpenRecord: onOpenRecord)
              else
                _FindingTile(
                  finding: finding,
                  onTap: () => onOpenRecord(finding.primary),
                ),
          ],
        ],
      ],
    );
  }
}

class _CleanResultBanner extends StatelessWidget {
  const _CleanResultBanner({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final color = Colors.green.shade800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Καμία παρατυπία — όλες οι εγγραφές τηρούν τους ενεργούς '
              'κανόνες.',
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Μία γραμμή ευρήματος: ποια εγγραφή, ποιο πεδίο, τι φταίει.
class _FindingTile extends StatelessWidget {
  const _FindingTile({required this.finding, required this.onTap});

  final CatalogValidationFinding finding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning = Colors.orange.shade800;
    final record = finding.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          _entityIcons[record.kind],
          color: theme.colorScheme.primary,
        ),
        title: Text(
          '${_entityKindLabels[record.kind]}: ${record.label}',
          style: theme.textTheme.bodyLarge,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              '${finding.fieldLabel} — ${finding.message}',
              style: theme.textTheme.bodySmall?.copyWith(color: warning),
            ),
          ],
        ),
        trailing: const Icon(Icons.edit_outlined, size: 20),
        onTap: onTap,
      ),
    );
  }
}

const _entityIcons = {
  CatalogEntityKind.user: Icons.person_outline,
  CatalogEntityKind.department: Icons.apartment_outlined,
  CatalogEntityKind.equipment: Icons.computer_outlined,
};

const _entityKindLabels = {
  CatalogEntityKind.user: 'Υπάλληλος',
  CatalogEntityKind.department: 'Τμήμα',
  CatalogEntityKind.equipment: 'Εξοπλισμός',
};

/// Κάρτα διένεξης: κεφαλίδα κανόνα + όλες οι εμπλεκόμενες εγγραφές ως
/// επιλέξιμα chips. Ο χρήστης αποφασίζει ΠΟΙΑ εγγραφή θα διορθώσει
/// βλέποντας τα στοιχεία και τις χρονοσφραγίδες όλων μαζί.
class _ConflictCard extends StatelessWidget {
  const _ConflictCard({required this.finding, required this.onOpenRecord});

  final CatalogValidationFinding finding;
  final Future<void> Function(CatalogFindingRecord record) onOpenRecord;

  static const _ruleIcons = {
    CatalogFindingType.phoneEquipmentCode: Icons.phonelink_erase_outlined,
    CatalogFindingType.nameConflict: Icons.swap_horiz_outlined,
    CatalogFindingType.crossDepartmentPhone: Icons.phone_forwarded_outlined,
    CatalogFindingType.equipmentOwnerDepartment: Icons.computer_outlined,
  };

  static const _ruleTitles = {
    CatalogFindingType.phoneEquipmentCode: 'Τηλέφωνο = κωδικός εξοπλισμού',
    CatalogFindingType.nameConflict: 'Πιθανό ίδιο πρόσωπο',
    CatalogFindingType.crossDepartmentPhone:
        'Ίδιο τηλέφωνο σε διαφορετικά τμήματα',
    CatalogFindingType.equipmentOwnerDepartment:
        'Εξοπλισμός σε υπάλληλο άλλου τμήματος',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning = Colors.orange.shade800;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _ruleIcons[finding.type],
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _ruleTitles[finding.type] ?? '',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        finding.message,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: warning,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Επιλέξτε εγγραφή για επεξεργασία:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 6),
            for (final record in finding.records)
              _RecordChip(record: record, onTap: () => onOpenRecord(record)),
          ],
        ),
      ),
    );
  }
}

/// Chip μίας εμπλεκόμενης εγγραφής: στοιχεία + χρονοσφραγίδες από το
/// Ιστορικό Εφαρμογής. Κλικ = άνοιγμα της καρτέλας της.
class _RecordChip extends StatelessWidget {
  const _RecordChip({required this.record, required this.onTap});

  final CatalogFindingRecord record;
  final VoidCallback onTap;

  /// Η γραμμή χρονοσφραγίδων — τίμια όταν το Ιστορικό δεν έχει ίχνος:
  /// οι πίνακες του καταλόγου δεν κρατούν δικές τους ημερομηνίες.
  String get _stampLine {
    final created = record.createdAt;
    final changed = record.lastChangedAt;
    if (created == null && changed == null) {
      return 'Χωρίς ίχνος στο Ιστορικό Εφαρμογής';
    }
    final parts = <String>[
      created == null
          ? 'Δημιουργία άγνωστη'
          : 'Δημιουργία ${formatGreekShortDate(created)}',
      if (changed != null) 'Τελευταία αλλαγή ${formatGreekShortDate(changed)}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(
                _entityIcons[record.kind],
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${_entityKindLabels[record.kind]} · '
                            '${record.label}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (record.isNewest)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              'νεότερη',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (record.details.isNotEmpty)
                      Text(record.details, style: theme.textTheme.bodySmall),
                    Text(
                      _stampLine,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.edit_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final color = Colors.orange.shade800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Όλοι οι κανόνες είναι προειδοποιήσεις — δεν εμποδίζουν ποτέ '
              'την αποθήκευση.',
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Κάρτα οντότητας (Τηλέφωνα/Εξοπλισμός/Τμήματα/Υπάλληλοι) με τους
/// κανόνες της σε γραμμές.
class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.icon,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            for (var i = 0; i < children.length; i++) ...[
              const Divider(height: 12),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Μία γραμμή κανόνα: περιεχόμενο αριστερά, διακόπτης δεξιά,
/// προαιρετική σημείωση + παράδειγμα υπόδειξης από κάτω.
class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.enabled,
    required this.onToggle,
    required this.child,
    required this.example,
    this.note,
  });

  final bool enabled;
  final ValueChanged<bool> onToggle;
  final Widget child;
  final String example;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                child,
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.subdirectory_arrow_right,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            note!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    example,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(value: enabled, onChanged: onToggle),
        ],
      ),
    );
  }
}

/// «Ετικέτα: [αριθμός]» σε μία γραμμή.
class _InlineNumberField extends StatelessWidget {
  const _InlineNumberField({
    required this.label,
    required this.controller,
    required this.maxLength,
    required this.onCommitted,
  });

  final String label;
  final TextEditingController controller;
  final int maxLength;
  final ValueChanged<String> onCommitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        const SizedBox(width: 8),
        _NumberBox(
          controller: controller,
          maxLength: maxLength,
          onCommitted: onCommitted,
        ),
      ],
    );
  }
}

/// «Ετικέτα: [από] έως [έως]» σε μία γραμμή.
class _InlineRangeFields extends StatelessWidget {
  const _InlineRangeFields({
    required this.label,
    required this.fromController,
    required this.toController,
    required this.onCommitted,
  });

  final String label;
  final TextEditingController fromController;
  final TextEditingController toController;
  final void Function(String fromText, String toText) onCommitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void commit() => onCommitted(fromController.text, toController.text);
    return Row(
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        const SizedBox(width: 8),
        _NumberBox(
          controller: fromController,
          maxLength: 2,
          onCommitted: (_) => commit(),
        ),
        const SizedBox(width: 8),
        Text('έως', style: theme.textTheme.bodyMedium),
        const SizedBox(width: 8),
        _NumberBox(
          controller: toController,
          maxLength: 2,
          onCommitted: (_) => commit(),
        ),
      ],
    );
  }
}

class _NumberBox extends StatelessWidget {
  const _NumberBox({
    required this.controller,
    required this.maxLength,
    required this.onCommitted,
  });

  final TextEditingController controller;
  final int maxLength;
  final ValueChanged<String> onCommitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(maxLength),
        ],
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(),
        ),
        onChanged: onCommitted,
      ),
    );
  }
}
