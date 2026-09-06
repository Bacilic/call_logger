/// Η λωρίδα φίλτρων των Στατιστικών Κλήσεων.
///
/// Αντικατέστησε το αιωρούμενο πλαίσιο που άνοιγε πάνω από τις κάρτες και
/// έκρυβε την τέταρτη. Τα χειριστήρια ζουν σε μία γραμμή κάτω από τον τίτλο —
/// όπως στο Ιστορικό — και από κάτω τους στέκονται οι **μάρκες των ενεργών
/// φίλτρων**, ώστε να φαίνεται πάντα τι περιορίζει τους αριθμούς της οθόνης.
///
/// Δεν υπάρχει κουμπί «Εφαρμογή»: κάθε επιλογή ισχύει αμέσως. Το παλιό κουμπί
/// υπήρχε επειδή τα πεδία ήταν ελεύθερο κείμενο με αναμονή πληκτρολόγησης· τώρα
/// που τα τρία φίλτρα οντότητας είναι κλειστές λίστες, η επιλογή **είναι** η
/// εφαρμογή.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/user_facing_error_messages.dart';
import '../models/dashboard_active_filter.dart';
import '../models/dashboard_date_preset.dart';
import '../models/dashboard_filter_model.dart';
import '../providers/dashboard_provider.dart';
import '../providers/history_provider.dart';
import '../widgets/audit_filter_autocomplete.dart';
import '../widgets/call_entity_filter_fields.dart';
import 'dashboard_palette_colors.dart';

/// Πλάτη των χειριστηρίων μέσα στη λωρίδα.
///
/// Δηλωμένα ρητά ώστε η αναδίπλωση να σπάει σε προβλέψιμα σημεία αντί να
/// τεντώνει ένα πεδίο σε ολόκληρη τη γραμμή.
const double _kSearchFieldWidth = 260;
const double _kFilterFieldWidth = 190;

class DashboardFilterBar extends ConsumerWidget {
  const DashboardFilterBar({
    super.key,
    required this.colors,
    required this.filter,
    required this.activeDatePreset,
    required this.controlsExpanded,
    required this.onPickDateRange,
    required this.onSetDatePreset,
  });

  final DashboardPaletteColors colors;
  final DashboardFilterModel filter;
  final DashboardDatePreset activeDatePreset;

  /// Αν φαίνονται τα χειριστήρια. Οι μάρκες των ενεργών φίλτρων φαίνονται
  /// **πάντα**: το ζητούμενο ήταν να μη χρειάζεται να ανοίξει κανείς τίποτα για
  /// να μάθει τι περιορίζει τους αριθμούς.
  final bool controlsExpanded;

  final VoidCallback onPickDateRange;
  final ValueChanged<DashboardDatePreset> onSetDatePreset;

  DashboardFilterNotifier _notifier(WidgetRef ref) =>
      ref.read(dashboardFilterProvider.notifier);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final active = describeActiveDashboardFilters(filter);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: colors.topBarFill.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.topBarBorder.withValues(alpha: 0.95)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (controlsExpanded) ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _dateRangeButton(),
                _datePresets(),
                SizedBox(
                  width: _kFilterFieldWidth,
                  child: _departmentField(ref),
                ),
                SizedBox(width: _kFilterFieldWidth, child: _callerField(ref)),
                SizedBox(
                  width: _kFilterFieldWidth,
                  child: _equipmentField(ref),
                ),
                SizedBox(width: _kFilterFieldWidth, child: _categoryField(ref)),
                SizedBox(width: _kSearchFieldWidth, child: _searchField(ref)),
              ],
            ),
            const SizedBox(height: 10),
          ],
          _activeFilterStrip(ref, theme, active),
        ],
      ),
    );
  }

  Widget _dateRangeButton() {
    return OutlinedButton.icon(
      onPressed: onPickDateRange,
      icon: const Icon(Icons.event_available_outlined, size: 18),
      label: Text(_dateRangeLabel()),
    );
  }

  String _dateRangeLabel() {
    final from = filter.dateFrom;
    final to = filter.dateTo;
    if (from != null && to != null) {
      return '${DashboardFilterModel.formatDisplayDate(from)} – '
          '${DashboardFilterModel.formatDisplayDate(to)}';
    }
    if (from != null) {
      return 'από ${DashboardFilterModel.formatDisplayDate(from)}';
    }
    if (to != null) {
      return 'έως ${DashboardFilterModel.formatDisplayDate(to)}';
    }
    return 'Εύρος ημερομηνιών';
  }

  Widget _datePresets() {
    return Wrap(
      spacing: 6,
      children: [
        _presetButton('Σήμερα', DashboardDatePreset.today),
        _presetButton('7 ημέρες', DashboardDatePreset.last7),
        _presetButton('30 ημέρες', DashboardDatePreset.last30),
        _presetButton('Όλα', DashboardDatePreset.all),
      ],
    );
  }

  Widget _presetButton(String label, DashboardDatePreset preset) {
    void onPressed() => onSetDatePreset(preset);
    if (activeDatePreset == preset) {
      return FilledButton(onPressed: onPressed, child: Text(label));
    }
    return FilledButton.tonal(onPressed: onPressed, child: Text(label));
  }

  Widget _departmentField(WidgetRef ref) {
    return CallDepartmentFilterField(
      departments: ref.watch(callFilterDepartmentsProvider),
      value: filter.department,
      onChanged: (value) => _notifier(ref).update(
        (s) => s.copyWith(department: value, clearDepartment: value == null),
      ),
    );
  }

  /// Ο υπάλληλος επιλέγεται από λίστα, αλλά η λίστα ψάχνεται **και με
  /// τηλέφωνο**: το τηλέφωνο μπαίνει στην ετικέτα της πρότασης, οπότε η
  /// πληκτρολόγηση «2534» φέρνει τον άνθρωπο και το φίλτρο εφαρμόζεται με το
  /// όνομά του.
  Widget _callerField(WidgetRef ref) {
    final callersAsync = ref.watch(callFilterCallersProvider);
    return callersAsync.when(
      data: (callers) {
        return AuditFilterAutocomplete(
          labelText: 'Υπάλληλος',
          options: [
            for (final caller in callers)
              AuditFilterAutocompleteOption(
                value: caller.name,
                label: caller.phones.isEmpty || caller.phones == '-'
                    ? caller.name
                    : '${caller.name} — ${caller.phones}',
              ),
          ],
          selectedValue: filter.userName,
          selectedLabel: filter.userName,
          onSelected: (value) => _notifier(ref).update(
            (s) => s.copyWith(userName: value, clearUserName: value == null),
          ),
        );
      },
      loading: () => const _FilterFieldPlaceholder(label: 'Υπάλληλος'),
      error: (e, _) => _FilterFieldError(message: humanizeUserFacingError(e)),
    );
  }

  Widget _equipmentField(WidgetRef ref) {
    final equipmentAsync = ref.watch(callFilterEquipmentProvider);
    return equipmentAsync.when(
      data: (codes) {
        return AuditFilterAutocomplete(
          labelText: 'Εξοπλισμός',
          options: [
            for (final code in codes)
              AuditFilterAutocompleteOption(value: code, label: code),
          ],
          selectedValue: filter.equipmentCode,
          selectedLabel: filter.equipmentCode,
          onSelected: (value) => _notifier(ref).update(
            (s) => s.copyWith(
              equipmentCode: value,
              clearEquipmentCode: value == null,
            ),
          ),
        );
      },
      loading: () => const _FilterFieldPlaceholder(label: 'Εξοπλισμός'),
      error: (e, _) => _FilterFieldError(message: humanizeUserFacingError(e)),
    );
  }

  Widget _categoryField(WidgetRef ref) {
    final categoriesAsync = ref.watch(historyCategoriesProvider);
    return categoriesAsync.when(
      data: (categories) {
        final options = <String?>[null, ...categories];
        final current = options.contains(filter.category)
            ? filter.category
            : null;
        return DropdownButtonFormField<String?>(
          initialValue: current,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Κατηγορία',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          items: [
            for (final option in options)
              DropdownMenuItem<String?>(
                value: option,
                child: Text(option ?? '— Όλες —'),
              ),
          ],
          onChanged: (value) => _notifier(ref).update(
            (s) => s.copyWith(category: value, clearCategory: value == null),
          ),
        );
      },
      loading: () => const _FilterFieldPlaceholder(label: 'Κατηγορία'),
      error: (e, _) => _FilterFieldError(message: humanizeUserFacingError(e)),
    );
  }

  Widget _searchField(WidgetRef ref) {
    return CallEntityTextFilterField(
      icon: Icons.search,
      hintText: 'Αναζήτηση κλήσεων…',
      clearTooltip: 'Καθαρισμός αναζήτησης',
      value: filter.keyword,
      onChanged: (value) =>
          _notifier(ref).update((s) => s.copyWith(keyword: value ?? '')),
    );
  }

  /// Οι μάρκες των ενεργών φίλτρων.
  ///
  /// Η γραμμή υπάρχει και όταν δεν ισχύει κανένα φίλτρο, λέγοντάς το με λόγια:
  /// η απουσία μαρκών είναι διφορούμενη — «δεν φιλτράρω» ή «δεν το δείχνει η
  /// οθόνη;» — ενώ μια πρόταση απαντά.
  Widget _activeFilterStrip(
    WidgetRef ref,
    ThemeData theme,
    List<DashboardActiveFilter> active,
  ) {
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.kpiSubtitle,
    );
    if (active.isEmpty) {
      return Text(
        'Ενεργά φίλτρα: κανένα — εμφανίζονται όλες οι κλήσεις.',
        style: labelStyle,
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Ενεργά φίλτρα:', style: labelStyle),
        for (final entry in active)
          InputChip(
            label: Text(entry.label),
            onDeleted: () => _notifier(ref).clearFilter(entry.kind),
            deleteIcon: const Icon(Icons.close_rounded, size: 16),
            deleteButtonTooltipMessage: 'Αφαίρεση φίλτρου',
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        TextButton(
          onPressed: () => _notifier(ref).clearAllFilters(),
          child: const Text('Καθαρισμός όλων'),
        ),
      ],
    );
  }
}

/// Θέση πεδίου όσο φορτώνει η λίστα του — ίδιο ύψος με το πεδίο, ώστε η λωρίδα
/// να μην αναπηδά όταν έρθουν τα δεδομένα.
class _FilterFieldPlaceholder extends StatelessWidget {
  const _FilterFieldPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      child: const SizedBox(
        height: 16,
        child: LinearProgressIndicator(minHeight: 2),
      ),
    );
  }
}

class _FilterFieldError extends StatelessWidget {
  const _FilterFieldError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: message,
      child: Text(
        'Σφάλμα φόρτωσης',
        style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
      ),
    );
  }
}
