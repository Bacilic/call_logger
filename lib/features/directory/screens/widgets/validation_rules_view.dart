import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/settings_service.dart';
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

  /// Άνοιγμα της καρτέλας του ευρήματος· μετά το κλείσιμο ο έλεγχος
  /// ξανατρέχει, ώστε η λίστα να δείχνει την πραγματικότητα και όχι
  /// ευρήματα που μόλις διορθώθηκαν.
  Future<void> _openFinding(CatalogValidationFinding finding) async {
    await CatalogScanRunner.openEditorFor(context, ref, finding);
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
              const SizedBox(height: 20),
              _ScanSection(
                scanning: _scanning,
                findings: _findings,
                onScan: _runScan,
                onOpenFinding: _openFinding,
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
    required this.onOpenFinding,
  });

  final bool scanning;
  final List<CatalogValidationFinding>? findings;
  final Future<void> Function() onScan;
  final Future<void> Function(CatalogValidationFinding finding) onOpenFinding;

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
            label: Text(
              scanning ? 'Γίνεται έλεγχος…' : 'Έλεγχος δεδομένων',
            ),
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
              _FindingTile(
                finding: finding,
                onTap: () => onOpenFinding(finding),
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

  static const _icons = {
    CatalogEntityKind.user: Icons.person_outline,
    CatalogEntityKind.department: Icons.apartment_outlined,
    CatalogEntityKind.equipment: Icons.computer_outlined,
  };

  static const _kindLabels = {
    CatalogEntityKind.user: 'Υπάλληλος',
    CatalogEntityKind.department: 'Τμήμα',
    CatalogEntityKind.equipment: 'Εξοπλισμός',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning = Colors.orange.shade800;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          _icons[finding.kind],
          color: theme.colorScheme.primary,
        ),
        title: Text(
          '${_kindLabels[finding.kind]}: ${finding.entityLabel}',
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
  });

  final IconData icon;
  final String title;
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
