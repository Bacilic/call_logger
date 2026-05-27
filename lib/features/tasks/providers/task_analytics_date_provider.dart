import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/settings_service.dart';
import '../models/task_analytics_date_preset.dart';
import 'task_service_provider.dart';

class TaskAnalyticsDateState {
  const TaskAnalyticsDateState({
    required this.startDate,
    required this.endDate,
    required this.activePreset,
    required this.creationSpan,
  });

  final DateTime startDate;
  final DateTime endDate;
  final TaskAnalyticsDatePreset activePreset;
  final ({DateTime start, DateTime end}) creationSpan;
}

class TaskAnalyticsDateNotifier extends AsyncNotifier<TaskAnalyticsDateState> {
  DateTime? _storedCustomFrom;
  DateTime? _storedCustomTo;

  TaskAnalyticsDatePreset get activePreset =>
      state.value?.activePreset ?? TaskAnalyticsDatePreset.defaultPreset;

  @override
  Future<TaskAnalyticsDateState> build() async {
    return _resolveFromSettings();
  }

  Future<({DateTime start, DateTime end})> _loadCreationSpan() async {
    return ref.read(taskServiceProvider).getTaskCreationDateSpan();
  }

  Future<TaskAnalyticsDateState> _resolveFromSettings() async {
    final creationSpan = await _loadCreationSpan();
    final settings = SettingsService();
    final rawPreset = await settings.getTaskAnalyticsDatePreset();
    var preset =
        TaskAnalyticsDatePreset.fromStorage(rawPreset) ??
        TaskAnalyticsDatePreset.defaultPreset;
    DateTime? customFrom;
    DateTime? customTo;
    if (preset == TaskAnalyticsDatePreset.custom) {
      customFrom = await settings.getTaskAnalyticsCustomDateFrom();
      customTo = await settings.getTaskAnalyticsCustomDateTo();
      if (customFrom == null || customTo == null) {
        preset = TaskAnalyticsDatePreset.defaultPreset;
      } else {
        _storedCustomFrom = customFrom;
        _storedCustomTo = customTo;
      }
    }
    final range = TaskAnalyticsDatePreset.dateRangeFor(
      preset,
      customFrom: customFrom,
      customTo: customTo,
      creationSpan: creationSpan,
    );
    return TaskAnalyticsDateState(
      startDate: range.start,
      endDate: range.end,
      activePreset: preset,
      creationSpan: creationSpan,
    );
  }

  Future<void> _persistPreset(
    TaskAnalyticsDatePreset preset, {
    DateTime? customFrom,
    DateTime? customTo,
  }) async {
    await SettingsService().setTaskAnalyticsDateFilter(
      preset: preset.storageValue,
      customFrom: customFrom,
      customTo: customTo,
    );
  }

  Future<void> _applyPreset(
    TaskAnalyticsDatePreset preset, {
    DateTime? customFrom,
    DateTime? customTo,
    bool persist = true,
  }) async {
    var current = state.value;
    current ??= await _resolveFromSettings();
    final creationSpan = current.creationSpan;
    if (preset == TaskAnalyticsDatePreset.custom) {
      _storedCustomFrom = customFrom;
      _storedCustomTo = customTo;
    }
    final range = TaskAnalyticsDatePreset.dateRangeFor(
      preset,
      customFrom: customFrom ?? _storedCustomFrom,
      customTo: customTo ?? _storedCustomTo,
      creationSpan: creationSpan,
    );
    final next = TaskAnalyticsDateState(
      startDate: range.start,
      endDate: range.end,
      activePreset: preset,
      creationSpan: creationSpan,
    );
    state = AsyncData(next);
    if (persist) {
      await _persistPreset(
        preset,
        customFrom: customFrom ?? range.start,
        customTo: customTo ?? range.end,
      );
    }
  }

  Future<void> setDatePreset(TaskAnalyticsDatePreset preset) async {
    await _applyPreset(preset);
  }

  Future<void> setCustomDateRange(DateTime from, DateTime to) async {
    final start = TaskAnalyticsDatePreset.dayOnly(from);
    final end = TaskAnalyticsDatePreset.dayOnly(to);
    await _applyPreset(
      TaskAnalyticsDatePreset.custom,
      customFrom: start,
      customTo: end,
    );
  }

  /// Πλήρες εύρος δημιουργίας (όλες οι εκκρεμότητες στο διάγραμμα).
  Future<void> clearToAllTasksRange() async {
    await _applyPreset(TaskAnalyticsDatePreset.all);
  }

  Future<void> refreshCreationSpan() async {
    final current = state.value;
    if (current == null) return;
    final creationSpan = await _loadCreationSpan();
    final range = TaskAnalyticsDatePreset.dateRangeFor(
      current.activePreset,
      customFrom: _storedCustomFrom,
      customTo: _storedCustomTo,
      creationSpan: creationSpan,
    );
    state = AsyncData(
      TaskAnalyticsDateState(
        startDate: range.start,
        endDate: range.end,
        activePreset: current.activePreset,
        creationSpan: creationSpan,
      ),
    );
  }
}

final taskAnalyticsDateProvider =
    AsyncNotifierProvider<TaskAnalyticsDateNotifier, TaskAnalyticsDateState>(
  TaskAnalyticsDateNotifier.new,
);
