import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dashboard_date_preset.dart';

class DatePresetButton extends StatelessWidget {
  const DatePresetButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return FilledButton(onPressed: onPressed, child: Text(label));
    }
    return FilledButton.tonal(onPressed: onPressed, child: Text(label));
  }
}

class FilterPane extends StatelessWidget {
  const FilterPane({
    super.key,
    required this.paneWidth,
    required this.dateRangeLabel,
    required this.keywordController,
    required this.userController,
    required this.equipmentController,
    required this.departmentsAsync,
    required this.selectedDepartment,
    required this.activeDatePreset,
    required this.onClose,
    required this.onPickDateRange,
    required this.onSetToday,
    required this.onSetWeek,
    required this.onSetMonth,
    required this.onSetAll,
    required this.onApply,
    required this.onClearAll,
    required this.onDepartmentChanged,
    required this.onChangedText,
  });

  final double paneWidth;
  final String dateRangeLabel;
  final TextEditingController keywordController;
  final TextEditingController userController;
  final TextEditingController equipmentController;
  final AsyncValue<List<String>> departmentsAsync;
  final String? selectedDepartment;
  final DashboardDatePreset activeDatePreset;
  final VoidCallback onClose;
  final VoidCallback onPickDateRange;
  final VoidCallback onSetToday;
  final VoidCallback onSetWeek;
  final VoidCallback onSetMonth;
  final VoidCallback onSetAll;
  final VoidCallback onApply;
  final VoidCallback onClearAll;
  final ValueChanged<String?> onDepartmentChanged;
  final VoidCallback onChangedText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: paneWidth,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x330F172A),
                blurRadius: 28,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Φίλτρα',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: keywordController,
                onChanged: (_) => onChangedText(),
                decoration: const InputDecoration(
                  labelText: 'Αναζήτηση Οντότητας',
                  hintText: 'Αναζήτηση ονόματος ή τμήματος...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onPickDateRange,
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: Text(dateRangeLabel),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  DatePresetButton(
                    label: 'Σήμερα',
                    selected: activeDatePreset == DashboardDatePreset.today,
                    onPressed: onSetToday,
                  ),
                  DatePresetButton(
                    label: '7 ημέρες',
                    selected: activeDatePreset == DashboardDatePreset.last7,
                    onPressed: onSetWeek,
                  ),
                  DatePresetButton(
                    label: '30 ημέρες',
                    selected: activeDatePreset == DashboardDatePreset.last30,
                    onPressed: onSetMonth,
                  ),
                  DatePresetButton(
                    label: 'Όλα',
                    selected: activeDatePreset == DashboardDatePreset.all,
                    onPressed: onSetAll,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              departmentsAsync.when(
                data: (deps) {
                  final options = <String?>[null, ...deps];
                  return DropdownButtonFormField<String?>(
                    initialValue: options.contains(selectedDepartment)
                        ? selectedDepartment
                        : null,
                    isExpanded: true,
                    items: options
                        .map(
                          (e) => DropdownMenuItem<String?>(
                            value: e,
                            child: Text(e ?? 'Όλα τα Τμήματα'),
                          ),
                        )
                        .toList(),
                    onChanged: onDepartmentChanged,
                    decoration: const InputDecoration(
                      labelText: 'Τμήμα',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(10),
                  child: LinearProgressIndicator(),
                ),
                error: (e, _) => Text(
                  'Σφάλμα φόρτωσης τμημάτων: $e',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: userController,
                onChanged: (_) => onChangedText(),
                decoration: const InputDecoration(
                  labelText: 'Όνομα Χρήστη',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: equipmentController,
                onChanged: (_) => onChangedText(),
                decoration: const InputDecoration(
                  labelText: 'Εξοπλισμός',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onClearAll,
                      child: const Text('Καθαρισμός'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: onApply,
                      child: const Text('Εφαρμογή'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
