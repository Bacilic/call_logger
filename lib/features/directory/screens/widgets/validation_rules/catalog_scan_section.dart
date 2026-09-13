/// Ενότητα «Έλεγχος δεδομένων» της οθόνης «Κανόνες επικύρωσης».
///
/// Το κουμπί που σαρώνει τον κατάλογο και οι κάρτες των ευρημάτων. Οι
/// κανόνες ορίζονται αλλού· εδώ μόνο παρουσιάζονται τα αποτελέσματα και
/// προωθείται το κλικ που ανοίγει την καρτέλα μιας εγγραφής.
library;

import 'package:flutter/material.dart';

import '../../../../../core/utils/greek_date_format.dart';
import '../../../models/catalog_validation_finding.dart';
import '../../../services/configured_path_scan_result.dart';
import 'configured_paths_section.dart';
import 'validation_rule_widgets.dart';

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

/// Τμήμα «Έλεγχος δεδομένων»: κουμπί εκκίνησης και αποτελέσματα.
class CatalogScanSection extends StatelessWidget {
  const CatalogScanSection({
    super.key,
    required this.scanning,
    required this.findings,
    required this.pathScan,
    required this.onScan,
    required this.onOpenRecord,
  });

  final bool scanning;

  /// `null` = δεν έχει τρέξει ακόμη σάρωση.
  final List<CatalogValidationFinding>? findings;
  final ConfiguredPathScanResult? pathScan;
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
            const StatusBanner(
              icon: Icons.check_circle_outline,
              tone: StatusBannerTone.success,
              message:
                  'Καμία παρατυπία — όλες οι εγγραφές τηρούν τους ενεργούς '
                  'κανόνες.',
            )
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
          if (pathScan != null) ...[
            const SizedBox(height: 16),
            ConfiguredPathsSection(scan: pathScan!),
          ],
        ],
      ],
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
    CatalogFindingType.equipmentInCompany: Icons.business_outlined,
    CatalogFindingType.duplicateRemoteTarget: Icons.cast_connected_outlined,
  };

  static const _ruleTitles = {
    CatalogFindingType.phoneEquipmentCode: 'Τηλέφωνο = κωδικός εξοπλισμού',
    CatalogFindingType.nameConflict: 'Πιθανό ίδιο πρόσωπο',
    CatalogFindingType.crossDepartmentPhone:
        'Ίδιο τηλέφωνο σε διαφορετικά τμήματα',
    CatalogFindingType.equipmentOwnerDepartment:
        'Εξοπλισμός σε υπάλληλο άλλου τμήματος',
    CatalogFindingType.equipmentInCompany: 'Εξοπλισμός σε εταιρεία',
    CatalogFindingType.duplicateRemoteTarget:
        'Ίδιος στόχος απομακρυσμένης σε δύο μηχανήματα',
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
