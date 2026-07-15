// Καρτέλα και widgets προβλημάτων ETL: ομαδοποίηση, λίστες, αντιγραφή.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/old_database/lamp_data_issue_type_labels.dart';
import '../../../core/database/old_database/lamp_issue_resolution_service.dart';
import '../../../core/database/old_database/lamp_old_db_validator.dart';
import '../controllers/lamp_issue_resolution_controller.dart';
import '../controllers/lamp_path_management.dart';
import '../controllers/lamp_search_controller.dart';
import '../controllers/lamp_screen_host.dart';

class LampIssuesController {
  LampIssuesController({
    required this.host,
    required this.path,
    required this.search,
  });

  final LampScreenHost host;
  final LampPathController path;
  final LampSearchController search;

  List<Map<String, Object?>> issues = const <Map<String, Object?>>[];
  List<Map<String, Object?>> deferredIssues = const <Map<String, Object?>>[];
  final Set<String> expandedIssueGroupKeys = <String>{};
  final Set<String> expandedDeferredIssueGroupKeys = <String>{};
  bool deferredSectionExpanded = false;

  Future<void> loadIssues() async {
    final dbPath = path.readDbController.text.trim();
    if (dbPath.isEmpty) return;
    if (host.readPathCheck?.status != LampOldDbStatus.ok) {
      if (host.mounted) {
        issues = const <Map<String, Object?>>[];
        deferredIssues = const <Map<String, Object?>>[];
        expandedIssueGroupKeys.clear();
        expandedDeferredIssueGroupKeys.clear();
        deferredSectionExpanded = false;
        host.notifyState();
      }
      return;
    }
    try {
      final loaded = await host.shared.repository.dataIssues(dbPath);
      final deferred = await host.shared.repository.deferredDataIssues(dbPath);
      if (!host.mounted) return;
      issues = loaded;
      deferredIssues = deferred;
      host.notifyState();
    } catch (e) {
      if (!host.mounted) return;
      issues = const <Map<String, Object?>>[];
      deferredIssues = const <Map<String, Object?>>[];
      expandedIssueGroupKeys.clear();
      expandedDeferredIssueGroupKeys.clear();
      deferredSectionExpanded = false;
      host.notifyState();
      host.showSnack('Δεν φορτώθηκαν τα προβλήματα ETL: $e', isError: true);
    }
  }

  Future<void> reopenDeferredGroup(String rawIssueType) async {
    final dbPath = path.readDbController.text.trim();
    if (dbPath.isEmpty) return;
    try {
      final count = await host.shared.repository.reopenDeferredDataIssuesByType(
        dbPath,
        rawIssueType,
      );
      await loadIssues();
      if (!host.mounted) return;
      host.showSnack(
        count > 0
            ? 'Επαναφέρθηκαν $count αναβληθέντα προβλήματα σε ανοιχτά.'
            : 'Δεν βρέθηκαν αναβληθέντα προβλήματα για επαναφορά.',
      );
    } catch (e) {
      if (!host.mounted) return;
      host.showSnack('Αποτυχία επαναφοράς αναβληθέντων: $e', isError: true);
    }
  }

  void clearIssues() {
    issues = const <Map<String, Object?>>[];
    deferredIssues = const <Map<String, Object?>>[];
    expandedIssueGroupKeys.clear();
    expandedDeferredIssueGroupKeys.clear();
    deferredSectionExpanded = false;
  }

  int issueCountFor(LampIssueType issueType) {
    return issues
        .where(
          (issue) => issue['issue_type']?.toString() == issueType.issueType,
        )
        .length;
  }
}

class LampIssueHelpers {
  LampIssueHelpers._();

  static String categoryDisplayLabel(String rawIssueType) {
    final t = rawIssueType.trim();
    if (t.isEmpty) return 'Χωρίς κατηγορία';
    return lampDataIssueTypeDisplayLabel(t);
  }

  static LampIssueType? lampIssueTypeForRaw(String rawIssueType) {
    final raw = rawIssueType.trim();
    if (raw.isEmpty) return null;
    for (final v in LampIssueType.values) {
      if (v.issueType == raw) return v;
    }
    return null;
  }

  static IconData resolveIssueIcon(LampIssueType issueType) {
    return switch (issueType) {
      LampIssueType.nonNumericFk => Icons.link_outlined,
      LampIssueType.unknownId => Icons.tag_outlined,
      LampIssueType.duplicateAssetNo => Icons.badge_outlined,
      LampIssueType.duplicateModelSerial => Icons.memory_outlined,
      LampIssueType.scientificSerial => Icons.functions_outlined,
      LampIssueType.setMasterSelfReference => Icons.link_off_outlined,
      LampIssueType.setMasterCycle => Icons.account_tree_outlined,
      LampIssueType.setMasterMissingTarget => Icons.gps_off_outlined,
    };
  }

  static IconData resolveNetworkIssueIcon(String rawIssueType) {
    return switch (rawIssueType.trim()) {
      'network_invalid_ip' => Icons.wrong_location_outlined,
      'network_duplicate_ip' => Icons.difference_outlined,
      'network_duplicate_name' => Icons.content_copy_outlined,
      'network_duplicate_hostname' => Icons.file_copy_outlined,
      'network_name_code_mismatch' => Icons.sync_problem_outlined,
      'network_no_hostname' => Icons.label_off_outlined,
      'network_hostname_unmatched' => Icons.link_off_outlined,
      'network_code_not_found' => Icons.search_off_outlined,
      'network_ip_in_comments' => Icons.comment_outlined,
      'network_model_mismatch' => Icons.devices_other_outlined,
      'network_sheet_invalid' => Icons.grid_off_outlined,
      _ => Icons.hub_outlined,
    };
  }

  static String issueField(Map<String, Object?> issue, String key) {
    final raw = issue[key];
    if (raw == null) return '-';
    final text = raw.toString().trim();
    return text.isEmpty ? '-' : text;
  }

  static String issueEntityTypeValue(Map<String, Object?> issue) {
    final explicit = issueField(issue, 'entity_type');
    if (explicit != '-') return explicit;
    final legacySheet = issueField(issue, 'sheet').toLowerCase();
    if (legacySheet == '-' || legacySheet.isEmpty) return 'equipment';
    if (legacySheet == 'integrity_scan') return 'equipment';
    return legacySheet;
  }

  static String issueOriginValue(Map<String, Object?> issue) {
    final explicit = issueField(issue, 'origin');
    if (explicit != '-') return explicit;
    final legacySheet = issueField(issue, 'sheet').toLowerCase();
    if (legacySheet == 'integrity_scan') return 'integrity_scan';
    return 'manual';
  }

  static String issueEntityTypeDisplayLabel(String value) {
    switch (value.trim().toLowerCase()) {
      case 'equipment':
        return 'Εξοπλισμός';
      default:
        return value;
    }
  }

  static String issueRowNumberLabel(Map<String, Object?> issue) {
    final entity = issueEntityTypeValue(issue).trim().toLowerCase();
    if (entity == 'equipment') {
      return 'Κωδικός εξοπλισμού';
    }
    return 'Γραμμή';
  }

  static String issueOriginDisplayLabel(String value) {
    switch (value.trim().toLowerCase()) {
      case 'integrity_scan':
        return 'Έλεγχος ακεραιότητας';
      case 'manual':
        return 'Χειροκίνητη καταχώρηση';
      default:
        return value;
    }
  }

  static int issueResolutionPriority(String rawIssueType) {
    final raw = rawIssueType.trim();
    if (raw.isEmpty) return 10000;
    const order = <String>[
      'non_numeric_fk',
      'unknown_id',
      'duplicate_asset_no',
      'duplicate_model_serial',
      'serial_scientific_notation',
      'set_master_self_reference',
      'set_master_missing_target',
      'set_master_cycle',
      'network_invalid_ip',
      'network_duplicate_ip',
      'network_duplicate_name',
      'network_name_code_mismatch',
      'network_code_not_found',
      'network_duplicate_hostname',
      'network_hostname_unmatched',
      'network_no_hostname',
      'network_ip_in_comments',
      'network_model_mismatch',
      'missing_sheet',
      'missing_primary_key',
      'duplicate_code_discarded',
      'xls_conversion_failed',
      'network_sheet_invalid',
    ];
    final i = order.indexOf(raw);
    return i >= 0 ? i : 999;
  }

  /// Χρώμα οικογένειας επίλυσης για κεφαλίδες ομάδων (ΓΕΝ-4).
  static Color issueFamilyColor(String rawIssueType) {
    final raw = rawIssueType.trim();
    if (LampIssueResolutionController.isInformationalIssueType(raw)) {
      return Colors.blueGrey;
    }
    switch (raw) {
      case 'non_numeric_fk':
      case 'unknown_id':
        return Colors.indigo;
      case 'duplicate_asset_no':
      case 'duplicate_model_serial':
      case 'serial_scientific_notation':
        return Colors.orange;
      case 'set_master_self_reference':
      case 'set_master_missing_target':
      case 'set_master_cycle':
        return Colors.deepPurple;
      default:
        if (raw.startsWith('network_')) return Colors.teal;
        return Colors.blueGrey;
    }
  }

  static Map<String, List<Map<String, Object?>>> groupedIssuesByType(
    List<Map<String, Object?>> issues,
  ) {
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final issue in issues) {
      final raw = issue['issue_type']?.toString().trim() ?? '';
      grouped.putIfAbsent(raw, () => <Map<String, Object?>>[]).add(issue);
    }
    return grouped;
  }

  static List<MapEntry<String, List<Map<String, Object?>>>> sortedIssueGroupEntries(
    List<Map<String, Object?>> issues,
  ) {
    final grouped = groupedIssuesByType(issues);
    final entries = grouped.entries.toList();
    entries.sort((a, b) {
      final pa = issueResolutionPriority(a.key);
      final pb = issueResolutionPriority(b.key);
      if (pa != pb) return pa.compareTo(pb);
      return a.key.compareTo(b.key);
    });
    return entries;
  }

  static int flatIssuesItemCount(
    List<MapEntry<String, List<Map<String, Object?>>>> groups,
    Set<String> expandedKeys,
  ) {
    var count = 0;
    for (final group in groups) {
      count++;
      if (expandedKeys.contains(group.key)) {
        count += group.value.length;
      }
    }
    return count;
  }

  static ({int groupIndex, bool isHeader, int? issueIndex})? flatIssueRefAt(
    List<MapEntry<String, List<Map<String, Object?>>>> groups,
    Set<String> expandedKeys,
    int flatIndex,
  ) {
    var i = 0;
    for (var g = 0; g < groups.length; g++) {
      if (i == flatIndex) {
        return (groupIndex: g, isHeader: true, issueIndex: null);
      }
      i++;
      if (expandedKeys.contains(groups[g].key)) {
        final groupIssues = groups[g].value;
        for (var j = 0; j < groupIssues.length; j++) {
          if (i == flatIndex) {
            return (groupIndex: g, isHeader: false, issueIndex: j);
          }
          i++;
        }
      }
    }
    return null;
  }

  static String buildIssuesClipboardText(
    List<Map<String, Object?>> issues, {
    Set<String>? categoryKeys,
  }) {
    final entries = sortedIssueGroupEntries(issues);
    final filtered = categoryKeys == null
        ? entries
        : entries.where((entry) => categoryKeys.contains(entry.key)).toList();
    final filteredIssues = filtered.expand((entry) => entry.value).toList();
    final lines = <String>[
      '# LAMP ETL Issues',
      'Σύνολο προβλημάτων: ${filteredIssues.length}',
      if (categoryKeys != null) 'Κατηγορίες: ${filtered.length}',
      '',
      'Οδηγία προς Πράκτορα ΤΝ: Ανάλυσε τα προβλήματα ανά κατηγορία, πρότεινε αιτίες, '
          'βήματα επιδιόρθωσης και προτεραιότητες.',
      '',
    ];
    for (final entry in filtered) {
      lines.add(
        '## ${categoryDisplayLabel(entry.key)} (${entry.value.length})',
      );
      for (final issue in entry.value) {
        final entityType = issueEntityTypeDisplayLabel(
          issueEntityTypeValue(issue),
        );
        final origin = issueOriginDisplayLabel(issueOriginValue(issue));
        lines.add(
          '- Entity type: $entityType | Origin: $origin | Row: ${issueField(issue, 'row_number')} | '
          'Column: ${issueField(issue, 'column_name')}',
        );
        lines.add('  Value: ${issueField(issue, 'raw_value')}');
        lines.add('  Message: ${issueField(issue, 'message')}');
      }
      lines.add('');
    }
    return lines.join('\n');
  }
}

class LampIssueEntryListTile extends StatelessWidget {
  const LampIssueEntryListTile({super.key, required this.issue});

  final Map<String, Object?> issue;

  @override
  Widget build(BuildContext context) {
    final entityType = LampIssueHelpers.issueEntityTypeDisplayLabel(
      LampIssueHelpers.issueEntityTypeValue(issue),
    );
    final origin = LampIssueHelpers.issueOriginDisplayLabel(
      LampIssueHelpers.issueOriginValue(issue),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.warning_amber),
          title: SelectableText(
            'Οντότητα: $entityType | '
            'Προέλευση: $origin | '
            '${LampIssueHelpers.issueRowNumberLabel(issue)}: ${LampIssueHelpers.issueField(issue, 'row_number')}',
          ),
          subtitle: SelectableText(
            'Στήλη: ${LampIssueHelpers.issueField(issue, 'column_name')}\n'
            'Τιμή: ${LampIssueHelpers.issueField(issue, 'raw_value')}\n'
            '${LampIssueHelpers.issueField(issue, 'message')}',
          ),
        ),
      ],
    );
  }
}

class LampIssueGroupHeaderCard extends StatelessWidget {
  const LampIssueGroupHeaderCard({
    super.key,
    required this.rawIssueType,
    required this.categoryLabel,
    required this.issues,
    required this.lampIssueType,
    required this.expanded,
    required this.onToggleExpanded,
    required this.resolvingIssueType,
    required this.canResolve,
    required this.onResolve,
    this.isNetworkCategory = false,
    this.resolvingNetworkIssueType,
    this.canResolveNetwork = false,
    this.onResolveNetwork,
    this.copySelectionMode = false,
    this.copySelected = false,
    this.onCopySelectionChanged,
    this.onClearGroup,
  });

  final String rawIssueType;
  final String categoryLabel;
  final List<Map<String, Object?>> issues;
  final LampIssueType? lampIssueType;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final LampIssueType? resolvingIssueType;
  final bool canResolve;
  final VoidCallback? onResolve;
  final bool isNetworkCategory;
  final String? resolvingNetworkIssueType;
  final bool canResolveNetwork;
  final VoidCallback? onResolveNetwork;
  final bool copySelectionMode;
  final bool copySelected;
  final ValueChanged<bool>? onCopySelectionChanged;

  /// Εκκαθάριση ολόκληρης της ομάδας — μόνο για πληροφοριακούς τύπους
  /// χωρίς οδηγό επίλυσης (ΓΕΝ-2).
  final VoidCallback? onClearGroup;

  @override
  Widget build(BuildContext context) {
    final familyColor = LampIssueHelpers.issueFamilyColor(rawIssueType);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: copySelectionMode ? null : onToggleExpanded,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: familyColor, width: 4),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (copySelectionMode) ...[
                  Checkbox(
                    value: copySelected,
                    onChanged: onCopySelectionChanged == null
                        ? null
                        : (value) => onCopySelectionChanged!(value ?? false),
                  ),
                ] else ...[
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                ],
                Icon(Icons.category_outlined, color: familyColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    categoryLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${issues.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (lampIssueType != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '${lampIssueType!.label} (${issues.length})',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    onPressed: canResolve ? onResolve : null,
                    icon: resolvingIssueType == lampIssueType
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(LampIssueHelpers.resolveIssueIcon(lampIssueType!)),
                  ),
                ] else if (isNetworkCategory) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: categoryLabel,
                    child: Icon(
                      LampIssueHelpers.resolveNetworkIssueIcon(rawIssueType),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Επίλυση · $categoryLabel (${issues.length})',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    onPressed: canResolveNetwork ? onResolveNetwork : null,
                    icon: resolvingNetworkIssueType == rawIssueType
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lan_outlined),
                  ),
                ] else if (onClearGroup != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip:
                        'Εκκαθάριση ομάδας (${issues.length} πληροφοριακές '
                        'εγγραφές)',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    onPressed: onClearGroup,
                    icon: Icon(
                      Icons.delete_sweep_outlined,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showIssueResolutionOrderInfo(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Σειρά επίλυσης προβλημάτων'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: SelectableText(
            'Μη αριθμητικό κλειδί αναφοράς και ασύμβατο αναγνωριστικό\n'
            'Στόχος: έγκυρα κλειδιά αναφοράς προς γραφεία, κατόχους, συμβόλαια και '
            'μοντέλα. Έτσι κάθε γραμμή εξοπλισμού αποκτά σαφή νόημα πριν '
            'συγκρίνεις γραφεία, κατόχους ή διπλότυπα.\n\n'
            'Διπλότυποι αριθμοί παγίου και διπλότυποι συνδυασμοί μοντέλου / σειριακού\n'
            'Στόχος: ένας ρόλος ανά παγίο και ανά συνδυασμό (μοντέλο, σειριακός)· '
            'συχνά συγχώνευση ή διαγραφή διπλών γραμμών. Κατά τη διαγραφή, οι '
            'δείκτες κύριου εξοπλισμού αναδρομολογούνται προς την εγγραφή που '
            'διατηρείται.\n\n'
            'Σειριακοί σε επιστημονική μορφή\n'
            'Στόχος: αποκατάσταση σειριακών που το Excel μετέτρεψε σε αριθμητική '
            'μορφή (π.χ. 4,9E+11), με αναζήτηση στην παλιά Λάμπα και καταχώρηση '
            'του σωστού.\n\n'
            'Κύριος εξοπλισμός που δείχνει στον ίδιο εξοπλισμό\n'
            'Στόχος: αφαίρεση αυτοαναφορών (ο δείκτης κύριου εξοπλισμού δείχνει '
            'στον ίδιο κωδικό εξοπλισμού).\n\n'
            'Κύριος εξοπλισμός χωρίς υπαρκτό στόχο\n'
            'Στόχος: σύνδεση του δείκτη με υπαρκτό εξοπλισμό ή εκκαθάρισή του.\n\n'
            'Κύκλοι ιεραρχίας κύριου εξοπλισμού\n'
            'Στόχος: σπάσιμο κύκλων στην ιεραρχία (συχνά με καθαρισμό του δείκτη '
            'κύριου εξοπλισμού σε επιλεγμένες γραμμές).\n\n'
            'Προβλήματα δικτύου\n'
            'Στόχος: πρώτα διόρθωση στοιχείων δικτύου πάνω στη βάση (μη έγκυρη/διπλή '
            'IP, διπλό ή αναντίστοιχο όνομα), έπειτα αντιστοίχιση των εγγραφών της '
            'ουράς import σε εξοπλισμό, και τέλος οι περιπτώσεις προς επιβεβαίωση '
            '(IP μέσα στα σχόλια, ασυμφωνία μοντέλου).\n\n'
            'Πληροφοριακές ομάδες\n'
            'Στόχος: δεν απαιτούν επίλυση — καθαρίζονται με το κουμπί «Εκκαθάριση '
            'ομάδας» αφού ενημερωθείς.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Κλείσιμο'),
        ),
      ],
    ),
  );
}

class LampIssuesTab extends StatefulWidget {
  const LampIssuesTab({
    super.key,
    required this.issuesController,
    required this.resolutionController,
    required this.integrityChecking,
    required this.onRunIntegrityCheck,
    required this.onToggleGroup,
    required this.showSnack,
  });

  final LampIssuesController issuesController;
  final LampIssueResolutionController resolutionController;
  final bool integrityChecking;
  final VoidCallback onRunIntegrityCheck;
  final void Function(String rawIssueType, bool expanded) onToggleGroup;
  final void Function(String message) showSnack;

  @override
  State<LampIssuesTab> createState() => _LampIssuesTabState();
}

class _LampIssuesTabState extends State<LampIssuesTab> {
  bool _copySelectionMode = false;
  final Set<String> _selectedCategoryKeys = <String>{};

  void _enterCopySelectionMode(List<MapEntry<String, List<Map<String, Object?>>>> groups) {
    setState(() {
      _copySelectionMode = true;
      _selectedCategoryKeys
        ..clear()
        ..addAll(groups.map((group) => group.key));
    });
  }

  void _exitCopySelectionMode() {
    setState(() {
      _copySelectionMode = false;
      _selectedCategoryKeys.clear();
    });
  }

  void _toggleSelectAllCategories(
    List<MapEntry<String, List<Map<String, Object?>>>> groups,
  ) {
    setState(() {
      if (_selectedCategoryKeys.length == groups.length) {
        _selectedCategoryKeys.clear();
      } else {
        _selectedCategoryKeys
          ..clear()
          ..addAll(groups.map((group) => group.key));
      }
    });
  }

  Future<void> _copySelectedCategories(
    List<MapEntry<String, List<Map<String, Object?>>>> groups,
  ) async {
    if (_selectedCategoryKeys.isEmpty) {
      widget.showSnack('Επιλέξτε τουλάχιστον μία κατηγορία για αντιγραφή.');
      return;
    }
    final selectedIssues = groups
        .where((group) => _selectedCategoryKeys.contains(group.key))
        .expand((group) => group.value)
        .toList();
    await copyIssuesToClipboard(
      issues: widget.issuesController.issues,
      categoryKeys: Set<String>.from(_selectedCategoryKeys),
      showSnack: widget.showSnack,
      copiedCount: selectedIssues.length,
      categoryCount: _selectedCategoryKeys.length,
    );
    _exitCopySelectionMode();
  }

  @override
  Widget build(BuildContext context) {
    final groups = LampIssueHelpers.sortedIssueGroupEntries(
      widget.issuesController.issues,
    );
    final allCategoriesSelected =
        groups.isNotEmpty && _selectedCategoryKeys.length == groups.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                'Σύνολο προβλημάτων: ${widget.issuesController.issues.length} • Κατηγορίες: ${groups.length}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (_copySelectionMode) ...[
                TextButton(
                  onPressed: groups.isEmpty
                      ? null
                      : () => _toggleSelectAllCategories(groups),
                  child: Text(
                    allCategoriesSelected
                        ? 'Αποεπιλογή όλων'
                        : 'Επιλογή όλων',
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _selectedCategoryKeys.isEmpty
                      ? null
                      : () => _copySelectedCategories(groups),
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(
                    'Αντιγραφή (${_selectedCategoryKeys.length} κατηγορίες)',
                  ),
                ),
                TextButton(
                  onPressed: _exitCopySelectionMode,
                  child: const Text('Ακύρωση'),
                ),
              ] else
                FilledButton.tonalIcon(
                  onPressed: groups.isEmpty
                      ? null
                      : () => _enterCopySelectionMode(groups),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Αντιγραφή για ΤΝ'),
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: widget.integrityChecking
                        ? null
                        : widget.onRunIntegrityCheck,
                    icon: widget.integrityChecking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.rule_folder_outlined),
                    label: const Text('Έλεγχος για προβλήματα'),
                  ),
                  IconButton(
                    tooltip: 'Σειρά επίλυσης προβλημάτων',
                    onPressed: () => showIssueResolutionOrderInfo(context),
                    icon: const Icon(Icons.info_outline),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ..._buildOpenIssueWidgets(
                context: context,
                groups: groups,
              ),
              if (widget.issuesController.deferredIssues.isNotEmpty)
                LampDeferredIssuesSection(
                  issuesController: widget.issuesController,
                  showSnack: widget.showSnack,
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildOpenIssueWidgets({
    required BuildContext context,
    required List<MapEntry<String, List<Map<String, Object?>>>> groups,
  }) {
    final widgets = <Widget>[];
    final itemCount = LampIssueHelpers.flatIssuesItemCount(
      groups,
      widget.issuesController.expandedIssueGroupKeys,
    );
    for (var flatIndex = 0; flatIndex < itemCount; flatIndex++) {
      if (flatIndex > 0) {
        final next = LampIssueHelpers.flatIssueRefAt(
          groups,
          widget.issuesController.expandedIssueGroupKeys,
          flatIndex,
        );
        if (next != null && next.isHeader) {
          widgets.add(const SizedBox(height: 12));
        }
      }
      final ref = LampIssueHelpers.flatIssueRefAt(
        groups,
        widget.issuesController.expandedIssueGroupKeys,
        flatIndex,
      );
      if (ref == null) continue;
      final group = groups[ref.groupIndex];
      final rawIssueType = group.key;
      final groupIssues = group.value;
      if (ref.isHeader) {
        final lampIssueType =
            LampIssueHelpers.lampIssueTypeForRaw(rawIssueType);
        final isInformational =
            LampIssueResolutionController.isInformationalIssueType(
          rawIssueType,
        );
        // Οι πληροφοριακοί τύποι υπερισχύουν: το network_sheet_invalid δεν
        // πρέπει να πάρει κουμπί επίλυσης δικτύου (δεν έχει τίποτα να επιλύσει).
        final isNetworkCategory = !isInformational &&
            LampIssueResolutionController.isNetworkIssueType(rawIssueType);
        final expanded = widget.issuesController.expandedIssueGroupKeys
            .contains(rawIssueType);
        widgets.add(
          LampIssueGroupHeaderCard(
            rawIssueType: rawIssueType,
            categoryLabel: LampIssueHelpers.categoryDisplayLabel(rawIssueType),
            issues: groupIssues,
            lampIssueType: lampIssueType,
            expanded: expanded,
            onToggleExpanded: () =>
                widget.onToggleGroup(rawIssueType, expanded),
            resolvingIssueType: widget.resolutionController.resolvingIssueType,
            canResolve: lampIssueType != null &&
                widget.resolutionController.canResolveIssueType(lampIssueType),
            onResolve: lampIssueType == null
                ? null
                : () => widget.resolutionController.runIssueResolution(
                      lampIssueType,
                    ),
            isNetworkCategory: lampIssueType == null && isNetworkCategory,
            resolvingNetworkIssueType:
                widget.resolutionController.resolvingNetworkIssueType,
            canResolveNetwork: isNetworkCategory &&
                widget.resolutionController.canResolveNetworkIssueType(
                  rawIssueType,
                ),
            onResolveNetwork: isNetworkCategory
                ? () => widget.resolutionController.runNetworkIssueResolution(
                      rawIssueType,
                      groupIssues,
                    )
                : null,
            copySelectionMode: _copySelectionMode,
            copySelected: _selectedCategoryKeys.contains(rawIssueType),
            onCopySelectionChanged: _copySelectionMode
                ? (selected) {
                    setState(() {
                      if (selected) {
                        _selectedCategoryKeys.add(rawIssueType);
                      } else {
                        _selectedCategoryKeys.remove(rawIssueType);
                      }
                    });
                  }
                : null,
            onClearGroup: isInformational
                ? () => widget.resolutionController
                    .clearInformationalIssueGroup(rawIssueType)
                : null,
          ),
        );
      } else {
        final issue = groupIssues[ref.issueIndex!];
        widgets.add(
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: LampIssueEntryListTile(issue: issue),
          ),
        );
      }
    }
    return widgets;
  }
}

class LampDeferredIssuesSection extends StatefulWidget {
  const LampDeferredIssuesSection({
    super.key,
    required this.issuesController,
    required this.showSnack,
  });

  final LampIssuesController issuesController;
  final void Function(String message) showSnack;

  @override
  State<LampDeferredIssuesSection> createState() =>
      _LampDeferredIssuesSectionState();
}

class _LampDeferredIssuesSectionState extends State<LampDeferredIssuesSection> {
  @override
  Widget build(BuildContext context) {
    final deferredGroups = LampIssueHelpers.sortedIssueGroupEntries(
      widget.issuesController.deferredIssues,
    );
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        child: ExpansionTile(
          initiallyExpanded: widget.issuesController.deferredSectionExpanded,
          onExpansionChanged: (expanded) {
            setState(() {
              widget.issuesController.deferredSectionExpanded = expanded;
            });
          },
          title: Text(
            'Αναβληθέντα (${widget.issuesController.deferredIssues.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          subtitle: const Text(
            'Δεν προσμετρούνται στο σύνολο ανοιχτών προβλημάτων.',
          ),
          children: [
            for (final group in deferredGroups) ...[
              ListTile(
                dense: true,
                title: Text(
                  '${LampIssueHelpers.categoryDisplayLabel(group.key)} '
                  '(${group.value.length})',
                ),
                trailing: TextButton(
                  onPressed: () async {
                    await widget.issuesController.reopenDeferredGroup(group.key);
                    if (mounted) setState(() {});
                  },
                  child: const Text('Επαναφορά σε ανοιχτά'),
                ),
                onTap: () {
                  setState(() {
                    final key = group.key;
                    if (widget.issuesController.expandedDeferredIssueGroupKeys
                        .contains(key)) {
                      widget.issuesController.expandedDeferredIssueGroupKeys
                          .remove(key);
                    } else {
                      widget.issuesController.expandedDeferredIssueGroupKeys
                          .add(key);
                    }
                  });
                },
              ),
              if (widget.issuesController.expandedDeferredIssueGroupKeys
                  .contains(group.key))
                for (final issue in group.value)
                  Card(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    clipBehavior: Clip.antiAlias,
                    child: LampIssueEntryListTile(issue: issue),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> copyIssuesToClipboard({
  required List<Map<String, Object?>> issues,
  required void Function(String message) showSnack,
  Set<String>? categoryKeys,
  int? copiedCount,
  int? categoryCount,
}) async {
  if (issues.isEmpty) {
    showSnack('Δεν υπάρχουν προβλήματα για αντιγραφή.');
    return;
  }
  if (categoryKeys != null && categoryKeys.isEmpty) {
    showSnack('Επιλέξτε τουλάχιστον μία κατηγορία για αντιγραφή.');
    return;
  }
  final payload = LampIssueHelpers.buildIssuesClipboardText(
    issues,
    categoryKeys: categoryKeys,
  );
  await Clipboard.setData(ClipboardData(text: payload));
  if (categoryKeys != null) {
    final count = copiedCount ?? 0;
    final categories = categoryCount ?? categoryKeys.length;
    showSnack(
      'Αντιγράφηκαν $count προβλήματα από $categories κατηγορίες στο πρόχειρο.',
    );
  } else {
    showSnack('Αντιγράφηκαν ${issues.length} προβλήματα στο πρόχειρο.');
  }
}
