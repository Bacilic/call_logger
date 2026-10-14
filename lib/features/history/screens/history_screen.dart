import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/history_audit_immersive_provider.dart';
import '../../../core/providers/history_search_prefill_intent_provider.dart';
import '../../../core/providers/lexicon_full_mode_provider.dart';
import '../../../core/providers/shell_navigation_intent_provider.dart';
import '../../../core/widgets/calendar_range_picker.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/widgets/main_nav_destination.dart';
import '../../../core/widgets/app_asset_image.dart';
import '../models/lansweeper_sync_state.dart';
import '../providers/history_application_audit_view_provider.dart';
import '../../../core/models/owner_filter.dart';
import '../../../core/widgets/owner_filter_chip.dart';
import '../providers/call_owner_filter_providers.dart';
import '../providers/dashboard_provider.dart';
import '../providers/history_provider.dart';
import '../providers/history_table_zoom_provider.dart';
import '../widgets/call_entity_filter_fields.dart';
import '../widgets/lansweeper/lansweeper_report_launcher.dart';
import '../widgets/call_delete_dialog.dart';
import '../widgets/application_audit_tab.dart';
import '../widgets/history_data_table.dart';
import 'dashboard_screen.dart';

/// Οθόνη Ιστορικού Κλήσεων: φίλτρα (keyword, ημερομηνίες, κατηγορία) και πίνακας αποτελεσμάτων.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  Future<void> _pickDateRange() async {
    final filter = ref.read(historyFilterProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialStart = filter.dateFrom ?? today;
    final initialEnd = filter.dateTo ?? today;
    final result = await showCalendarRangePickerDialog(
      context,
      initialValue: DateTimeRange(start: initialStart, end: initialEnd),
    );
    if (!mounted || result == null) return;
    if (result.wasCleared) {
      _clearDateRange();
      return;
    }
    final range = result.range;
    if (range == null) return;
    ref
        .read(historyFilterProvider.notifier)
        .update((s) => s.copyWith(dateFrom: range.start, dateTo: range.end));
  }

  void _clearDateRange() {
    ref
        .read(historyFilterProvider.notifier)
        .update((s) => s.copyWith(clearDateRange: true));
  }

  /// Η καθημερινή δουλειά: ό,τι μένει να καταχωρηθεί στο Lansweeper.
  ///
  /// Ανοίγει στο διάστημα που διάλεξε τελευταία ο χρήστης. Τα φίλτρα του
  /// Ιστορικού δεν μεταφέρονται: η αναφορά είναι ουρά εργασίας, ενώ το
  /// Ιστορικό απαντά «τι έγινε» — μια μισή μεταφορά θα έδειχνε σύνολο που δεν
  /// θα αντιστοιχούσε ούτε στο ένα ούτε στο άλλο.
  Future<void> _openLansweeperReport() =>
      openLansweeperReport(context, ref, scope: null);

  void _toggleApplicationAuditView() {
    final next = !ref.read(historyApplicationAuditViewProvider);
    ref.read(historyApplicationAuditViewProvider.notifier).set(next);
    if (next) {
      ref.read(historyAuditImmersiveProvider.notifier).setTrue();
      ref.read(lexiconFullModeProvider.notifier).setFalse();
    } else {
      ref.read(historyAuditImmersiveProvider.notifier).setFalse();
    }
  }

  void _navigateFromImmersiveHistory(MainNavDestination destination) {
    ref.read(shellNavigationIntentProvider.notifier).setPending(destination);
    ref.read(historyAuditImmersiveProvider.notifier).setFalse();
    ref.read(historyApplicationAuditViewProvider.notifier).setFalse();
  }

  static Widget _navMenuRow(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
      ],
    );
  }

  Widget _immersiveNavigationMenuButton() {
    final showDb = ref.watch(databaseNavVisibleProvider);
    return PopupMenuButton<MainNavDestination>(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tooltip: 'Μετάβαση σε άλλη οθόνη',
      icon: const Icon(Icons.menu),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      onSelected: _navigateFromImmersiveHistory,
      itemBuilder: (context) {
        return <PopupMenuEntry<MainNavDestination>>[
          PopupMenuItem(
            value: MainNavDestination.calls,
            child: _navMenuRow(Icons.phone_in_talk, 'Κλήσεις'),
          ),
          PopupMenuItem(
            value: MainNavDestination.tasks,
            child: _navMenuRow(Icons.task_alt, 'Εκκρεμότητες'),
          ),
          PopupMenuItem(
            value: MainNavDestination.directory,
            child: _navMenuRow(Icons.contacts, 'Κατάλογος'),
          ),
          PopupMenuItem(
            value: MainNavDestination.history,
            child: _navMenuRow(Icons.history, 'Ιστορικό (κλήσεις)'),
          ),
          if (showDb)
            PopupMenuItem(
              value: MainNavDestination.database,
              child: _navMenuRow(Icons.storage, 'Βάση Δεδομένων'),
            ),
        ];
      },
    );
  }

  Widget _auditToggleButton({
    required String tooltip,
    required bool backToCallHistory,
  }) {
    final asset = backToCallHistory
        ? 'assets/back_to_call_history.png'
        : 'assets/audit_log_icon.png';
    final fallbackIcon = backToCallHistory
        ? Icons.history
        : Icons.fact_check_outlined;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        onPressed: _toggleApplicationAuditView,
        icon: Image.asset(
          asset,
          width: 24,
          height: 24,
          errorBuilder: (context, error, stackTrace) =>
              Icon(fallbackIcon, size: 24),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<HistoryFilterModel>(historyFilterProvider, (_, _) {
      ref.read(historySelectedCallIdsProvider.notifier).clear();
    });
    ref.listen<String?>(historySearchPrefillIntentProvider, (_, next) {
      final keyword = next?.trim() ?? '';
      if (keyword.isEmpty) return;
      ref.read(historySearchPrefillIntentProvider.notifier).clear();
      // Ο όρος έρχεται έτοιμος από αλλού: εφαρμόζεται αμέσως, χωρίς την
      // αναμονή πληκτρολόγησης που έχει νόημα μόνο όταν γράφει ο χρήστης.
      // Το πλαίσιο τον δείχνει επειδή ακολουθεί το φίλτρο — δεν γράφεται
      // χωριστά, αλλιώς τα δύο θα μπορούσαν να αποκλίνουν.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(historyFilterProvider.notifier)
            .update((s) => s.copyWith(keyword: keyword));
      });
    });
    final theme = Theme.of(context);
    final filter = ref.watch(historyFilterProvider);
    final asyncCalls = ref.watch(historyCallsProvider);
    final totalCallsAsync = ref.watch(totalCallsCountProvider);
    final asyncCallCount = ref.watch(historyCategoryDateCallCountProvider);
    final asyncCategories = ref.watch(historyCategoriesProvider);
    final asyncDepartments = ref.watch(callFilterDepartmentsProvider);
    final tableZoom = ref.watch(historyTableZoomProvider);
    final filtersEnabled = totalCallsAsync.maybeWhen(
      data: (count) => count > 0,
      orElse: () => false,
    );
    final databaseDisplayName = ref.watch(historyDatabaseDisplayNameProvider);
    final appAudit = ref.watch(historyApplicationAuditViewProvider);
    // Το watch γίνεται άνευ όρων, έξω από κάθε `if`: ένα watch που άλλοτε
    // εκτελείται και άλλοτε όχι αλλάζει το σύνολο των εξαρτήσεων του widget
    // από build σε build.
    final mayViewAudit = ref.watch(applicationAuditVisibleProvider);
    final immersive = ref.watch(historyAuditImmersiveProvider);
    final selectedCallIds = ref.watch(historySelectedCallIdsProvider);

    String dateRangeLabel = '';
    if (filter.dateFrom != null && filter.dateTo != null) {
      dateRangeLabel =
          '${DateFormat('dd/MM/yyyy').format(filter.dateFrom!)} – ${DateFormat('dd/MM/yyyy').format(filter.dateTo!)}';
    } else if (filter.dateFrom != null) {
      dateRangeLabel =
          'από ${DateFormat('dd/MM/yyyy').format(filter.dateFrom!)}';
    } else if (filter.dateTo != null) {
      dateRangeLabel = 'έως ${DateFormat('dd/MM/yyyy').format(filter.dateTo!)}';
    }
    final hasDateRange = filter.dateFrom != null || filter.dateTo != null;

    if (appAudit) {
      return Scaffold(
        appBar: AppBar(
          leading: immersive ? _immersiveNavigationMenuButton() : null,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  'Ιστορικό Εφαρμογής',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _auditToggleButton(
                tooltip: 'Εναλλαγή σε ιστορικό κλήσεων',
                backToCallHistory: true,
              ),
            ],
          ),
        ),
        body: const ApplicationAuditTab(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Expanded(
              child: Text('Ιστορικό Κλήσεων', overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              tooltip: kLansweeperReportShortcutTooltip,
              onPressed: filtersEnabled ? _openLansweeperReport : null,
              icon: const AppAssetImage(
                assetPath: kLansweeperReportBadgeAsset,
                width: 24,
                height: 24,
                fit: BoxFit.contain,
                fallbackIcon: Icons.confirmation_number_outlined,
              ),
            ),
            IconButton(
              tooltip: 'Στατιστικά κλήσεων / Αναφορές',
              onPressed: filtersEnabled
                  ? () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const DashboardScreen(),
                        ),
                      );
                    }
                  : null,
              icon: const Icon(Icons.analytics_outlined),
            ),
            // Χωρίς το δικαίωμα το κουμπί **λείπει**, δεν γκριζάρει: γκρίζο
            // κουμπί είναι πρόσκληση να ρωτήσει κανείς «γιατί δεν μπορώ».
            if (mayViewAudit)
              _auditToggleButton(
                tooltip: 'Εναλλαγή σε ιστορικό εφαρμογής (audit)',
                backToCallHistory: false,
              ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ——— Φίλτρα ———
          Material(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 980;
                      final keywordField = CallEntityTextFilterField(
                        icon: Icons.search,
                        hintText: compact
                            ? 'Αναζήτηση ιστορικού'
                            : 'Αναζήτηση (Σε όλα τα πεδία, εκτός από ώρα και διάρκεια)',
                        clearTooltip: 'Καθαρισμός αναζήτησης',
                        value: filter.keyword,
                        enabled: filtersEnabled,
                        onChanged: (value) => ref
                            .read(historyFilterProvider.notifier)
                            .update((s) => s.copyWith(keyword: value ?? '')),
                      );
                      final categoryDropdown = asyncCategories.when(
                        data: (categories) {
                          final options = <String?>[null, ...categories];
                          final current = filter.category;
                          return DropdownButtonFormField<String?>(
                            initialValue: options.contains(current)
                                ? current
                                : null,
                            decoration: InputDecoration(
                              labelText: 'Κατηγορία',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            items: options.map((c) {
                              return DropdownMenuItem<String?>(
                                value: c,
                                child: Text(c ?? '— Όλες —'),
                              );
                            }).toList(),
                            onChanged: filtersEnabled
                                ? (v) {
                                    ref
                                        .read(historyFilterProvider.notifier)
                                        .update(
                                          (s) => s.copyWith(
                                            category: v,
                                            clearCategory: v == null,
                                          ),
                                        );
                                  }
                                : null,
                          );
                        },
                        loading: () => const SizedBox(
                          height: 48,
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        error: (_, _) => const SizedBox.shrink(),
                      );
                      final dateButton = IconButton.filled(
                        onPressed: filtersEnabled ? _pickDateRange : null,
                        tooltip: 'Εύρος ημερομηνιών',
                        icon: const Icon(Icons.date_range),
                      );

                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(child: keywordField),
                                const SizedBox(width: 8),
                                dateButton,
                              ],
                            ),
                            const SizedBox(height: 8),
                            categoryDropdown,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 2, child: keywordField),
                          const SizedBox(width: 12),
                          dateButton,
                          const SizedBox(width: 8),
                          Expanded(child: categoryDropdown),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final departmentField = CallDepartmentFilterField(
                        departments: asyncDepartments,
                        value: filter.department,
                        enabled: filtersEnabled,
                        onChanged: (value) => ref
                            .read(historyFilterProvider.notifier)
                            .update(
                              (s) => s.copyWith(
                                department: value,
                                clearDepartment: value == null,
                              ),
                            ),
                      );
                      final userField = CallCallerFilterField(
                        callers: ref.watch(callFilterCallersProvider),
                        value: filter.userName,
                        enabled: filtersEnabled,
                        onChanged: (value) => ref
                            .read(historyFilterProvider.notifier)
                            .update(
                              (s) => s.copyWith(
                                userName: value,
                                clearUserName: value == null,
                              ),
                            ),
                      );
                      final equipmentField = CallEntityTextFilterField(
                        label: 'Εξοπλισμός',
                        icon: Icons.computer_outlined,
                        value: filter.equipmentCode,
                        enabled: filtersEnabled,
                        onChanged: (value) => ref
                            .read(historyFilterProvider.notifier)
                            .update(
                              (s) => s.copyWith(
                                equipmentCode: value,
                                clearEquipmentCode: value == null,
                              ),
                            ),
                      );

                      if (constraints.maxWidth < 720) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            departmentField,
                            const SizedBox(height: 8),
                            userField,
                            const SizedBox(height: 8),
                            equipmentField,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: departmentField),
                          const SizedBox(width: 8),
                          Expanded(child: userField),
                          const SizedBox(width: 8),
                          Expanded(child: equipmentField),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  // Δύο ομάδες: φίλτρα αριστερά, μέγεθος πίνακα δεξιά.
                  // Wrap αντί για Row με Spacer — στο πιο στενό παράθυρο
                  // οι δύο ομάδες δεν χωρούν στην ίδια σειρά, οπότε η
                  // δεξιά κατεβαίνει από κάτω αντί να βγει εκτός οθόνης.
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          asyncCalls.when(
                            data: (rows) => _HistoryCountLabel(
                              shownCount: rows.length,
                              searching: filter.keyword.trim().isNotEmpty,
                              totalWithoutKeyword: asyncCallCount.maybeWhen(
                                data: (count) => count,
                                orElse: () => null,
                              ),
                            ),
                            loading: () => SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            error: (_, _) => const SizedBox.shrink(),
                          ),
                          _CallLinkFilterChip(
                            label: 'Με εκκρεμότητα',
                            icon: Icons.task_alt,
                            selected: filter.onlyWithTask,
                            enabled: filtersEnabled,
                            onChanged: (value) => ref
                                .read(historyFilterProvider.notifier)
                                .update((s) => s.copyWith(onlyWithTask: value)),
                          ),
                          _LansweeperStateFilterChip(
                            selectedState: filter.lansweeperState,
                            enabled: filtersEnabled,
                            onChanged: (value) => ref
                                .read(historyFilterProvider.notifier)
                                .update(
                                  (s) => value == null
                                      ? s.copyWith(clearLansweeperState: true)
                                      : s.copyWith(lansweeperState: value),
                                ),
                          ),
                          OwnerFilterChip(
                            tooltip: 'Ποιος κατέγραψε την κλήση',
                            options:
                                ref.watch(callOwnerOptionsProvider).value ??
                                const [],
                            current:
                                ref.watch(historyOwnerFilterProvider).value ??
                                OwnerFilter.everyone,
                            enabled: filtersEnabled,
                            onSelected: (value) => ref
                                .read(historyOwnerFilterProvider.notifier)
                                .select(value),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Σμίκρυνση',
                            icon: const Icon(Icons.zoom_out),
                            onPressed: filtersEnabled
                                ? () => ref
                                      .read(historyTableZoomProvider.notifier)
                                      .zoomOut()
                                : null,
                          ),
                          IconButton(
                            tooltip: 'Επαναφορά μεγέθους (100%)',
                            icon: const Icon(Icons.restart_alt),
                            onPressed: filtersEnabled
                                ? () => ref
                                      .read(historyTableZoomProvider.notifier)
                                      .reset()
                                : null,
                          ),
                          IconButton(
                            tooltip: 'Μεγέθυνση',
                            icon: const Icon(Icons.zoom_in),
                            onPressed: filtersEnabled
                                ? () => ref
                                      .read(historyTableZoomProvider.notifier)
                                      .zoomIn()
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Μέγεθος πίνακα',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(tableZoom * 100).round()}%',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (hasDateRange) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.calendar_today, size: 18),
                          label: Text(dateRangeLabel),
                          onPressed: filtersEnabled ? _pickDateRange : null,
                        ),
                        ActionChip(
                          label: const Text('Καθαρισμός ημερομηνιών'),
                          onPressed: filtersEnabled ? _clearDateRange : null,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          // ——— Πίνακας αποτελεσμάτων ———
          Expanded(
            child: asyncCalls.when(
              loading: () => const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Φόρτωση ιστορικού...'),
                  ],
                ),
              ),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      databaseDisplayName.when(
                        loading: () => Text(
                          'Υπάρχει σφάλμα στη βάση δεδομένων: …',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        error: (_, _) => Text(
                          'Υπάρχει σφάλμα στη βάση δεδομένων: —',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        data: (dbName) => Text(
                          'Υπάρχει σφάλμα στη βάση δεδομένων: $dbName',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => ref.invalidate(historyCallsProvider),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Επανάληψη'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  // Όταν το φίλτρο χρήστη είναι αυτό που αδειάζει τη λίστα,
                  // η οθόνη το λέει και δίνει διέξοδο — αλλιώς η άδεια λίστα
                  // μοιάζει με «δεν υπάρχουν κλήσεις», που είναι ψέμα.
                  final owner =
                      ref.watch(historyOwnerFilterProvider).value ??
                      OwnerFilter.everyone;
                  final emptyMessage = filter.hasActiveFilters
                      ? 'Δεν βρέθηκαν κλήσεις με τα τρέχοντα κριτήρια.'
                      : (owner.isEveryone
                            ? 'Δεν υπάρχουν εγγραφές'
                            : 'Καμία κλήση για την επιλογή του φίλτρου χρήστη');
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          emptyMessage,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (!owner.isEveryone) ...[
                          const SizedBox(height: 16),
                          FilledButton.tonalIcon(
                            onPressed: () => ref
                                .read(historyOwnerFilterProvider.notifier)
                                .select(OwnerFilter.everyone),
                            icon: const Icon(Icons.groups_outlined),
                            label: const Text('Δείξε όλες'),
                          ),
                        ],
                      ],
                    ),
                  );
                }
                final visibleRowIds = rows
                    .map((r) => r['id'])
                    .whereType<int>()
                    .toSet();
                final visibleSelectedIds = selectedCallIds
                    .where(visibleRowIds.contains)
                    .toSet();

                if (visibleSelectedIds.length != selectedCallIds.length) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    ref
                        .read(historySelectedCallIdsProvider.notifier)
                        .setAll(visibleSelectedIds);
                  });
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (visibleSelectedIds.isNotEmpty)
                      Container(
                        color: theme.colorScheme.secondaryContainer.withValues(
                          alpha: 0.35,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Επιλεγμένες κλήσεις: ${visibleSelectedIds.length}',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(width: 12),
                            TextButton(
                              onPressed: () {
                                ref
                                    .read(
                                      historySelectedCallIdsProvider.notifier,
                                    )
                                    .clear();
                              },
                              child: const Text('Καθαρισμός'),
                            ),
                            const Spacer(),
                            FilledButton.icon(
                              onPressed: () async {
                                await showCallBulkDeleteDialog(
                                  context,
                                  callIds: visibleSelectedIds.toList(),
                                );
                                if (!mounted) return;
                                ref
                                    .read(
                                      historySelectedCallIdsProvider.notifier,
                                    )
                                    .clear();
                              },
                              icon: const Icon(Icons.delete_sweep_outlined),
                              label: const Text('Μαζική διαγραφή'),
                            ),
                          ],
                        ),
                      ),
                    Expanded(child: HistoryDataTable(rows: rows)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Διακόπτης φίλτρου «μόνο κλήσεις με …» πάνω από τον πίνακα.
class _CallLinkFilterChip extends StatelessWidget {
  const _CallLinkFilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      avatar: Icon(icon, size: 18),
      selected: selected,
      onSelected: enabled ? onChanged : null,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Φίλτρο κατάστασης Lansweeper: μία θέση στη μπάρα, πέντε επιλογές.
///
/// Ως αναπτυσσόμενη λίστα και όχι ως πέντε chips — η μπάρα κουβαλά ήδη
/// αναζήτηση, ημερομηνίες, κατηγορία και «Με εκκρεμότητα».
class _LansweeperStateFilterChip extends StatelessWidget {
  const _LansweeperStateFilterChip({
    required this.selectedState,
    required this.enabled,
    required this.onChanged,
  });

  /// `null` σημαίνει «όλες οι καταστάσεις» — η προεπιλογή.
  final String? selectedState;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  /// Τιμή-θέση για το «Όλες»: το μενού δεν δέχεται `null` ως τιμή στοιχείου.
  static const String _allValue = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = selectedState != null && selectedState!.trim().isNotEmpty;
    final label = active
        ? 'Lansweeper: ${LansweeperSyncState.labelPlural(selectedState)}'
        : 'Lansweeper: όλες';

    return PopupMenuButton<String>(
      enabled: enabled,
      initialValue: active ? selectedState : _allValue,
      tooltip: 'Κατάσταση καταχώρησης στο Lansweeper',
      onSelected: (value) => onChanged(value == _allValue ? null : value),
      itemBuilder: (context) => [
        const PopupMenuItem(value: _allValue, child: Text('Όλες')),
        for (final state in LansweeperSyncState.all)
          PopupMenuItem(
            value: state,
            child: Text(LansweeperSyncState.labelPlural(state)),
          ),
      ],
      child: Chip(
        avatar: Icon(
          Icons.confirmation_number_outlined,
          size: 18,
          color: active ? theme.colorScheme.onSecondaryContainer : null,
        ),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
        backgroundColor: active ? theme.colorScheme.secondaryContainer : null,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Λεζάντα πλήθους πάνω από τον πίνακα.
///
/// Το [shownCount] είναι το μήκος της λίστας που εμφανίζεται από κάτω, ώστε ο
/// αριθμός να μη λέει ποτέ άλλα από όσα βλέπει ο χρήστης. Το
/// [totalWithoutKeyword] μετράει τα ίδια φίλτρα χωρίς την αναζήτηση, οπότε
/// χρησιμεύει μόνο ως «από N» όταν όντως γίνεται αναζήτηση.
class _HistoryCountLabel extends StatelessWidget {
  const _HistoryCountLabel({
    required this.shownCount,
    required this.searching,
    required this.totalWithoutKeyword,
  });

  final int shownCount;
  final bool searching;
  final int? totalWithoutKeyword;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = totalWithoutKeyword;
    final value = searching && total != null
        ? '$shownCount από $total'
        : '$shownCount';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          searching ? 'Αποτελέσματα' : 'Συνολικές κλήσεις',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: theme.textTheme.labelMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
