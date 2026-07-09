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
  final Set<String> expandedIssueGroupKeys = <String>{};

  Future<void> loadIssues() async {
    final dbPath = path.readDbController.text.trim();
    if (dbPath.isEmpty) return;
    if (host.readPathCheck?.status != LampOldDbStatus.ok) {
      if (host.mounted) {
        issues = const <Map<String, Object?>>[];
        expandedIssueGroupKeys.clear();
        host.notifyState();
      }
      return;
    }
    try {
      final loaded = await host.shared.repository.dataIssues(dbPath);
      if (!host.mounted) return;
      issues = loaded;
      host.notifyState();
    } catch (e) {
      if (!host.mounted) return;
      issues = const <Map<String, Object?>>[];
      expandedIssueGroupKeys.clear();
      host.notifyState();
      host.showSnack('Δεν φορτώθηκαν τα προβλήματα ETL: $e', isError: true);
    }
  }

  void clearIssues() {
    issues = const <Map<String, Object?>>[];
    expandedIssueGroupKeys.clear();
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
      LampIssueType.setMasterSelfReference => Icons.link_off_outlined,
      LampIssueType.setMasterCycle => Icons.account_tree_outlined,
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
      'set_master_self_reference',
      'set_master_missing_target',
      'set_master_cycle',
    ];
    final i = order.indexOf(raw);
    return i >= 0 ? i : 999;
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
          title: Text(
            'Οντότητα: $entityType | '
            'Προέλευση: $origin | '
            'Γραμμή: ${LampIssueHelpers.issueField(issue, 'row_number')}',
          ),
          subtitle: Text(
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

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: copySelectionMode ? null : onToggleExpanded,
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
              const Icon(Icons.category_outlined),
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
              ],
            ],
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
            'Κύριος εξοπλισμός που δείχνει στον ίδιο εξοπλισμό\n'
            'Στόχος: αφαίρεση αυτοαναφορών (ο δείκτης κύριου εξοπλισμού δείχνει '
            'στον ίδιο κωδικό εξοπλισμού).\n\n'
            'Κύκλοι ιεραρχίας κύριου εξοπλισμού\n'
            'Στόχος: σπάσιμο κύκλων στην ιεραρχία (συχνά με καθαρισμό του δείκτη '
            'κύριου εξοπλισμού σε επιλεγμένες γραμμές).',
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
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: LampIssueHelpers.flatIssuesItemCount(
              groups,
              widget.issuesController.expandedIssueGroupKeys,
            ),
            separatorBuilder: (context, index) {
              final next = LampIssueHelpers.flatIssueRefAt(
                groups,
                widget.issuesController.expandedIssueGroupKeys,
                index + 1,
              );
              if (next != null && next.isHeader) {
                return const SizedBox(height: 12);
              }
              return const SizedBox.shrink();
            },
            itemBuilder: (context, flatIndex) {
              final ref = LampIssueHelpers.flatIssueRefAt(
                groups,
                widget.issuesController.expandedIssueGroupKeys,
                flatIndex,
              );
              if (ref == null) return const SizedBox.shrink();
              final group = groups[ref.groupIndex];
              final rawIssueType = group.key;
              final groupIssues = group.value;
              if (ref.isHeader) {
                final lampIssueType =
                    LampIssueHelpers.lampIssueTypeForRaw(rawIssueType);
                final isNetworkCategory =
                    LampIssueResolutionController.isNetworkIssueType(
                  rawIssueType,
                );
                final expanded = widget.issuesController.expandedIssueGroupKeys
                    .contains(rawIssueType);
                return LampIssueGroupHeaderCard(
                  rawIssueType: rawIssueType,
                  categoryLabel: LampIssueHelpers.categoryDisplayLabel(
                    rawIssueType,
                  ),
                  issues: groupIssues,
                  lampIssueType: lampIssueType,
                  expanded: expanded,
                  onToggleExpanded: () =>
                      widget.onToggleGroup(rawIssueType, expanded),
                  resolvingIssueType: widget.resolutionController.resolvingIssueType,
                  canResolve: lampIssueType != null &&
                      widget.resolutionController.canResolveIssueType(
                        lampIssueType,
                      ),
                  onResolve: lampIssueType == null
                      ? null
                      : () => widget.resolutionController.runIssueResolution(
                          lampIssueType,
                        ),
                  isNetworkCategory:
                      lampIssueType == null && isNetworkCategory,
                  resolvingNetworkIssueType:
                      widget.resolutionController.resolvingNetworkIssueType,
                  canResolveNetwork: isNetworkCategory &&
                      widget.resolutionController.canResolveNetworkIssueType(
                        rawIssueType,
                      ),
                  onResolveNetwork: isNetworkCategory
                      ? () => widget.resolutionController
                          .runNetworkIssueResolution(
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
                );
              }
              final issue = groupIssues[ref.issueIndex!];
              return Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: LampIssueEntryListTile(issue: issue),
              );
            },
          ),
        ),
      ],
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
