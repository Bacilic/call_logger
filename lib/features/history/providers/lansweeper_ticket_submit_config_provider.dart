import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/settings_repository.dart';
import '../../../core/services/lansweeper_ticket_submit_config.dart';

/// Απομνημόνευση παραμετροποίησης πολυβηματικής καταχώρησης Lansweeper.
class LansweeperTicketSubmitConfigNotifier
    extends Notifier<LansweeperTicketSubmitConfig> {
  final Completer<void> _hydrationCompleter = Completer<void>();

  /// Ολοκληρώθηκε η ανάγνωση ρυθμίσεων από τη βάση (ανεξάρτητα από αλλαγή state).
  Future<void> get hydrationFuture => _hydrationCompleter.future;

  @override
  LansweeperTicketSubmitConfig build() {
    Future<void>(_hydrateFromDb);
    return LansweeperTicketSubmitConfig.defaults();
  }

  /// Ολοκλήρωση hydration (π.χ. test doubles χωρίς DB).
  void ensureHydrationCompleted() {
    if (!_hydrationCompleter.isCompleted) {
      _hydrationCompleter.complete();
    }
  }

  Future<void> _hydrateFromDb() async {
    try {
      final db = await DatabaseHelper.instance.database;
      if (!ref.mounted) return;
      final raw = await SettingsRepository(db)
          .getSetting(kLansweeperTicketSubmitConfigSettingKey);
      if (!ref.mounted) return;
      if (raw == null) {
        state = LansweeperTicketSubmitConfig.defaults();
        await _persist();
      } else {
        state = LansweeperTicketSubmitConfig.decodeFromStorage(raw);
      }
    } finally {
      if (!_hydrationCompleter.isCompleted) {
        _hydrationCompleter.complete();
      }
    }
  }

  Future<void> _persist() async {
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(db).saveSetting(
      kLansweeperTicketSubmitConfigSettingKey,
      LansweeperTicketSubmitConfig.encodeForStorage(state),
    );
  }

  Future<void> replace(
    LansweeperTicketSubmitConfig next, {
    bool persist = true,
  }) async {
    state = next;
    if (persist) await _persist();
  }

  Future<void> resetToDefaults() async {
    state = LansweeperTicketSubmitConfig.defaults();
    await _persist();
  }

  Future<void> setNoteType(String value) async {
    state = state.copyWith(noteType: value);
    await _persist();
  }

  Future<void> setDefaultTicketState(String value) async {
    state = state.copyWith(defaultTicketState: value);
    await _persist();
  }

  Future<void> setTicketStates(List<String> value) async {
    state = state.copyWith(ticketStates: value);
    await _persist();
  }

  Future<void> replaceCustomFields(List<LansweeperCustomFieldDef> value) async {
    state = state.copyWith(customFields: value);
    await _persist();
  }

  Future<void> setTicketType(String value) async {
    final types = LansweeperTicketSubmitConfig.ensureSelectedInList(
      state.ticketTypes,
      value,
      fallbackList: LansweeperTicketSubmitConfig.defaultTicketTypes,
    );
    state = state.copyWith(ticketType: value, ticketTypes: types);
    await _persist();
  }

  Future<void> setTicketTypes(List<String> value) async {
    final types = LansweeperTicketSubmitConfig.ensureSelectedInList(
      value,
      state.ticketType,
      fallbackList: LansweeperTicketSubmitConfig.defaultTicketTypes,
    );
    final selected = types.contains(state.ticketType)
        ? state.ticketType
        : types.first;
    state = state.copyWith(ticketTypes: types, ticketType: selected);
    await _persist();
  }

  Future<void> setPriority(String value) async {
    final list = LansweeperTicketSubmitConfig.ensureSelectedInList(
      state.priorities,
      value,
      fallbackList: LansweeperTicketSubmitConfig.defaultPriorities,
    );
    state = state.copyWith(priority: value, priorities: list);
    await _persist();
  }

  Future<void> setPriorities(List<String> value) async {
    final list = LansweeperTicketSubmitConfig.ensureSelectedInList(
      value,
      state.priority,
      fallbackList: LansweeperTicketSubmitConfig.defaultPriorities,
    );
    final selected =
        list.contains(state.priority) ? state.priority : list.first;
    state = state.copyWith(priorities: list, priority: selected);
    await _persist();
  }

  Future<void> setTeam(String value) async {
    final list = LansweeperTicketSubmitConfig.ensureSelectedInList(
      state.teams,
      value,
      fallbackList: LansweeperTicketSubmitConfig.defaultTeams,
    );
    state = state.copyWith(team: value, teams: list);
    await _persist();
  }

  Future<void> setTeams(List<String> value) async {
    final list = LansweeperTicketSubmitConfig.ensureSelectedInList(
      value,
      state.team,
      fallbackList: LansweeperTicketSubmitConfig.defaultTeams,
    );
    final selected = list.contains(state.team) ? state.team : list.first;
    state = state.copyWith(teams: list, team: selected);
    await _persist();
  }

  Future<void> setEnableAddNoteStep(bool value) async {
    state = state.copyWith(enableAddNoteStep: value);
    await _persist();
  }

  Future<void> setEnableStateUpdateStep(bool value) async {
    state = state.copyWith(enableStateUpdateStep: value);
    await _persist();
  }

  Future<void> setRememberFormSelections(bool value) async {
    state = state.copyWith(rememberFormSelections: value);
    await _persist();
  }

  Future<void> setIncludeNoteTime(bool value) async {
    state = state.copyWith(includeNoteTime: value);
    await _persist();
  }
}

final lansweeperTicketSubmitConfigProvider = NotifierProvider.autoDispose<
    LansweeperTicketSubmitConfigNotifier,
    LansweeperTicketSubmitConfig>(
  LansweeperTicketSubmitConfigNotifier.new,
);
