import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/settings_service.dart';
import '../../models/lamp_cross_check_finding.dart';
import '../../models/lamp_cross_check_rules.dart';
import '../../providers/lamp_cross_check_provider.dart';
import '../../services/catalog_scan_runner.dart';
import '../../services/lamp_cross_check_runner.dart';

/// Υπο-οθόνη «Διασταύρωση με Λάμπα» του hub «Διάφορα».
///
/// Δείχνει πού ο Κατάλογος και το μητρώο της Λάμπας λένε διαφορετικά
/// πράγματα. **Η Λάμπα διαβάζεται μόνο**: κάθε διόρθωση γίνεται στην καρτέλα
/// του Καταλόγου, με τον ίδιο μηχανισμό που χρησιμοποιεί ο «Έλεγχος
/// δεδομένων».
class LampCrossCheckView extends ConsumerStatefulWidget {
  const LampCrossCheckView({super.key});

  @override
  ConsumerState<LampCrossCheckView> createState() => _LampCrossCheckViewState();
}

class _LampCrossCheckViewState extends ConsumerState<LampCrossCheckView> {
  LampCrossCheckRules? _rules;

  /// `null` = δεν έχει τρέξει ακόμη διασταύρωση.
  LampCrossCheckResult? _result;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await ref.read(lampCrossCheckRulesProvider.future);
    if (!mounted) return;
    setState(() => _rules = rules);
  }

  /// Άμεση αποθήκευση του διακόπτη που άγγιξε ο χρήστης.
  ///
  /// Η [change] εφαρμόζεται πάνω στην **αποθηκευμένη** εικόνα, όχι σε αυτήν
  /// που φόρτωσε η οθόνη: και οι δεκαπέντε διακόπτες ζουν σε ένα κλειδί, οπότε
  /// η εγγραφή ολόκληρου του JSON από παλιά εικόνα θα επανέφερε τον διακόπτη
  /// που μόλις άλλαξε ο συνάδελφος.
  Future<void> _apply(
    LampCrossCheckRules Function(LampCrossCheckRules current) change,
  ) async {
    setState(() {
      // Τα ευρήματα προήλθαν από τους ΠΑΛΙΟΥΣ διακόπτες — παύουν να ισχύουν.
      _result = null;
      final shown = _rules;
      if (shown != null) _rules = change(shown);
    });
    final storedRaw = await SettingsService().catalogs
        .updateLampCrossCheckRulesRaw(
          (raw) => change(LampCrossCheckRules.fromRawJson(raw)).toRawJson(),
        );
    if (!mounted) return;
    if (storedRaw != null) {
      setState(() => _rules = LampCrossCheckRules.fromRawJson(storedRaw));
    }
    ref.invalidate(lampCrossCheckRulesProvider);
  }

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      final result = await LampCrossCheckRunner.run(ref);
      if (!mounted) return;
      setState(() => _result = result);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// Ανοίγει την καρτέλα του Καταλόγου και ξανατρέχει τη διασταύρωση, ώστε η
  /// λίστα να δείχνει την πραγματικότητα και όχι ό,τι μόλις διορθώθηκε.
  Future<void> _openRecord(LampCrossCheckFinding finding) async {
    await CatalogScanRunner.openEntity(
      context,
      ref,
      kind: finding.entityKind,
      entityId: finding.entityId,
      focusedField: finding.focusedField,
    );
    if (!mounted) return;
    await _run();
  }

  /// Η επεξήγηση του ελέγχου «δεν υπάρχει στη Λάμπα», με το σύνορο του
  /// μητρώου όταν είναι γνωστό.
  ///
  /// Χωρίς τον αριθμό, ο έλεγχος θα φαινόταν να σωπαίνει χωρίς λόγο για τα
  /// καινούργια μηχανήματα. Όταν η Λάμπα δεν διαβάζεται, μένει μόνο η πρώτη
  /// πρόταση: μια υπόσχεση για όριο που δεν ξέρουμε θα ήταν χειρότερη από
  /// καμία.
  String _missingCodeExample() {
    const base =
        'Λάθος πληκτρολόγηση, ή μηχάνημα που δεν καταγράφηκε ποτέ στο μητρώο.';
    final last = ref.watch(lampLastEquipmentCodeProvider).asData?.value;
    if (last == null) return base;
    return '$base Κωδικοί μεγαλύτεροι από το $last δεν ελέγχονται: '
        'καταγράφηκαν αφότου η Λάμπα έπαψε να ενημερώνεται.';
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
              const _ReadOnlyBanner(),
              const SizedBox(height: 12),
              _CheckCard(
                icon: Icons.people_outline,
                title: 'Υπάλληλοι',
                children: [
                  _CheckRow(
                    label: 'Διαφορετική γραφή ονόματος',
                    example: 'Ο ίδιος άνθρωπος, γραμμένος αλλιώς στις δύο '
                        'βάσεις: «Νατάσσα» και «Νατάσα».',
                    enabled: rules.userNameSpellingEnabled,
                    onToggle: (v) => _apply(
                      (c) => c.copyWith(userNameSpellingEnabled: v),
                    ),
                  ),
                  _CheckRow(
                    label: 'Αβέβαιη ταύτιση',
                    example: 'Μοιάζει με δύο ή περισσότερους της Λάμπας — οι '
                        'υπόλοιποι έλεγχοι σιωπούν για αυτόν τον άνθρωπο.',
                    enabled: rules.userAmbiguousMatchEnabled,
                    onToggle: (v) => _apply(
                      (c) => c.copyWith(userAmbiguousMatchEnabled: v),
                    ),
                  ),
                  _CheckRow(
                    label: 'Δεν βρέθηκε στη Λάμπα',
                    example: 'Θεμιτό για όσους προσλήφθηκαν αφότου πάγωσε η '
                        'Λάμπα. Βγάζει πολλές γραμμές.',
                    enabled: rules.userMissingInLampEnabled,
                    onToggle: (v) => _apply(
                      (c) => c.copyWith(userMissingInLampEnabled: v),
                    ),
                  ),
                  _CheckRow(
                    label: 'Άλλο τμήμα στις δύο βάσεις',
                    example: 'Πιάνει μετακινήσεις που έμειναν καταγραμμένες '
                        'μόνο στη μία πλευρά.',
                    enabled: rules.userDepartmentEnabled,
                    onToggle: (v) =>
                        _apply((c) => c.copyWith(userDepartmentEnabled: v)),
                  ),
                  _CheckRow(
                    label: 'Τηλέφωνο μόνο στη Λάμπα',
                    example: 'Συχνά παλιοί αριθμοί που δεν ισχύουν πια.',
                    enabled: rules.userPhoneOnlyInLampEnabled,
                    onToggle: (v) => _apply(
                      (c) => c.copyWith(userPhoneOnlyInLampEnabled: v),
                    ),
                  ),
                  _CheckRow(
                    label: 'Τηλέφωνο μόνο στον Κατάλογο',
                    example: 'Ο φρέσκος αριθμός που η Λάμπα δεν πρόλαβε.',
                    enabled: rules.userPhoneOnlyInCatalogEnabled,
                    onToggle: (v) => _apply(
                      (c) => c.copyWith(userPhoneOnlyInCatalogEnabled: v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _CheckCard(
                icon: Icons.apartment_outlined,
                title: 'Τμήματα',
                subtitle: 'Το τμήμα του Καταλόγου αντιστοιχεί στο γραφείο '
                    'της Λάμπας.',
                children: [
                  _CheckRow(
                    label: 'Διαφορετική ονομασία',
                    example: 'Το ίδιο γραφείο γραμμένο αλλιώς στα δύο '
                        'συστήματα.',
                    enabled: rules.departmentNameSpellingEnabled,
                    onToggle: (v) => _apply(
                      (c) => c.copyWith(departmentNameSpellingEnabled: v),
                    ),
                  ),
                  _CheckRow(
                    label: 'Δεν βρέθηκε στη Λάμπα',
                    example: 'Τμήματα που δημιουργήθηκαν ή μετονομάστηκαν '
                        'μετά. Βγάζει πολλές γραμμές.',
                    enabled: rules.departmentMissingInLampEnabled,
                    onToggle: (v) => _apply(
                      (c) => c.copyWith(departmentMissingInLampEnabled: v),
                    ),
                  ),
                  _CheckRow(
                    label: 'Τηλέφωνο μόνο στη Λάμπα',
                    example: 'Αριθμοί του γραφείου που λείπουν από το τμήμα.',
                    enabled: rules.departmentPhoneOnlyInLampEnabled,
                    onToggle: (v) => _apply(
                      (c) => c.copyWith(departmentPhoneOnlyInLampEnabled: v),
                    ),
                  ),
                  _CheckRow(
                    label: 'Τηλέφωνο μόνο στον Κατάλογο',
                    example: 'Αριθμοί του τμήματος που η Λάμπα δεν ξέρει.',
                    enabled: rules.departmentPhoneOnlyInCatalogEnabled,
                    onToggle: (v) => _apply(
                      (c) => c.copyWith(departmentPhoneOnlyInCatalogEnabled: v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _CheckCard(
                icon: Icons.desktop_windows_outlined,
                title: 'Εξοπλισμός',
                subtitle: 'Η ταύτιση γίνεται με τον κωδικό.',
                children: [
                  _CheckRow(
                    label: 'Ο κωδικός δεν υπάρχει στη Λάμπα',
                    example: _missingCodeExample(),
                    enabled: rules.equipmentMissingInLampEnabled,
                    onToggle: (v) => _apply(
                      (c) => c.copyWith(equipmentMissingInLampEnabled: v),
                    ),
                  ),
                  _CheckRow(
                    label: 'Εκτός χρήσης στη Λάμπα',
                    example: 'Καταστραμμένο, αποσυρμένο ή χαμένο, ενώ ο '
                        'Κατάλογος το δείχνει ζωντανό.',
                    enabled: rules.equipmentRetiredInLampEnabled,
                    onToggle: (v) => _apply(
                      (c) => c.copyWith(equipmentRetiredInLampEnabled: v),
                    ),
                  ),
                  _CheckRow(
                    label: 'Διαφορετικό είδος',
                    example: 'Ο Κατάλογος λέει «Εκτυπωτής» και η Λάμπα '
                        '«Υπολογιστής» — ο κωδικός δείχνει αλλού.',
                    enabled: rules.equipmentTypeEnabled,
                    onToggle: (v) =>
                        _apply((c) => c.copyWith(equipmentTypeEnabled: v)),
                  ),
                  _CheckRow(
                    label: 'Άλλος κάτοχος',
                    example: 'Χρεωμένο σε διαφορετικό άνθρωπο στις δύο '
                        'βάσεις.',
                    enabled: rules.equipmentOwnerEnabled,
                    onToggle: (v) =>
                        _apply((c) => c.copyWith(equipmentOwnerEnabled: v)),
                  ),
                  _CheckRow(
                    label: 'Άλλο τμήμα',
                    example: 'Βρίσκεται σε διαφορετικό τμήμα στις δύο βάσεις.',
                    enabled: rules.equipmentDepartmentEnabled,
                    onToggle: (v) => _apply(
                      (c) => c.copyWith(equipmentDepartmentEnabled: v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Center(
                child: FilledButton.icon(
                  onPressed: _running ? null : _run,
                  icon: _running
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.compare_arrows),
                  label: Text(
                    _running ? 'Γίνεται διασταύρωση…' : 'Διασταύρωση με Λάμπα',
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'Συγκρίνει τον Κατάλογο με το μητρώο της Λάμπας.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              if (_result != null) ...[
                const SizedBox(height: 16),
                _ResultSection(
                  result: _result!,
                  onOpenRecord: _openRecord,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// «Η Λάμπα διαβάζεται μόνο» — το λέει πριν από κάθε εύρημα, ώστε ο χρήστης
/// να μην ψάχνει κουμπί διόρθωσης που δεν υπάρχει.
class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Η Λάμπα διαβάζεται μόνο. Κάθε διόρθωση γίνεται στην καρτέλα '
              'του Καταλόγου.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ομάδα ελέγχων μιας οντότητας.
class _CheckCard extends StatelessWidget {
  const _CheckCard({
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
            for (final child in children) ...[
              const Divider(height: 12),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

/// Μία γραμμή ελέγχου: ονομασία και παράδειγμα αριστερά, διακόπτης δεξιά.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.example,
    required this.enabled,
    required this.onToggle,
  });

  final String label;
  final String example;
  final bool enabled;
  final ValueChanged<bool> onToggle;

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
                Text(label, style: theme.textTheme.bodyMedium),
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

/// Τα αποτελέσματα της τελευταίας διασταύρωσης.
class _ResultSection extends StatelessWidget {
  const _ResultSection({required this.result, required this.onOpenRecord});

  final LampCrossCheckResult result;
  final Future<void> Function(LampCrossCheckFinding finding) onOpenRecord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!result.isAvailable) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.report_problem_outlined,
              size: 20,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                result.unavailableReason!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final findings = result.findings;
    if (findings.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 20,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Καμία απόκλιση στους ενεργούς ελέγχους.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          findings.length == 1
              ? 'Βρέθηκε 1 απόκλιση'
              : 'Βρέθηκαν ${findings.length} αποκλίσεις',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Επιλέξτε μια γραμμή για να ανοίξει η καρτέλα του Καταλόγου.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 8),
        for (final finding in findings)
          _FindingCard(
            finding: finding,
            onTap: () => onOpenRecord(finding),
          ),
      ],
    );
  }
}

/// Μία απόκλιση, με τις δύο πλευρές δίπλα-δίπλα.
class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.finding, required this.onTap});

  final LampCrossCheckFinding finding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _iconFor(finding.kind),
                    size: 18,
                    color: theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      finding.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    finding.entityLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _SideBox(
                      label: 'Κατάλογος',
                      value: finding.catalogValue,
                    ),
                  ),
                  if (finding.lampValue != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SideBox(
                        label: 'Λάμπα',
                        value: finding.lampValue!,
                      ),
                    ),
                  ],
                ],
              ),
              if (finding.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    finding.note,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(LampCrossCheckKind kind) {
    return switch (kind) {
      LampCrossCheckKind.userNameSpelling ||
      LampCrossCheckKind.departmentNameSpelling => Icons.spellcheck,
      LampCrossCheckKind.userAmbiguousMatch => Icons.help_outline,
      LampCrossCheckKind.userMissing ||
      LampCrossCheckKind.departmentMissing ||
      LampCrossCheckKind.equipmentMissing => Icons.search_off,
      LampCrossCheckKind.userDepartment ||
      LampCrossCheckKind.equipmentDepartment => Icons.apartment_outlined,
      LampCrossCheckKind.userPhoneOnlyInLamp ||
      LampCrossCheckKind.userPhoneOnlyInCatalog ||
      LampCrossCheckKind.departmentPhoneOnlyInLamp ||
      LampCrossCheckKind.departmentPhoneOnlyInCatalog => Icons.phone_outlined,
      LampCrossCheckKind.equipmentRetired => Icons.delete_outline,
      LampCrossCheckKind.equipmentType => Icons.category_outlined,
      LampCrossCheckKind.equipmentOwner => Icons.person_outline,
    };
  }
}

/// Η μία πλευρά μιας απόκλισης.
class _SideBox extends StatelessWidget {
  const _SideBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
