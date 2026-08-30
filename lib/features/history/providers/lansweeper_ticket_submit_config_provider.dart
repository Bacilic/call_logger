import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/settings_repository.dart';
import '../../../core/services/lansweeper_ticket_submit_config.dart';
import '../../../core/services/settings_list_conflict.dart';

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
      final raw = await SettingsRepository(
        db,
      ).getSetting(kLansweeperTicketSubmitConfigSettingKey);
      if (!ref.mounted) return;
      if (raw == null) {
        state = LansweeperTicketSubmitConfig.defaults();
        await _persistWholeConfig();
      } else {
        state = LansweeperTicketSubmitConfig.decodeFromStorage(raw);
      }
    } finally {
      if (!_hydrationCompleter.isCompleted) {
        _hydrationCompleter.complete();
      }
    }
  }

  /// Γράφει **ολόκληρη** τη ρύθμιση — μόνο για ρητή πρόθεση αντικατάστασης.
  Future<void> _persistWholeConfig() async {
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    await SettingsRepository(db).saveSetting(
      kLansweeperTicketSubmitConfigSettingKey,
      LansweeperTicketSubmitConfig.encodeForStorage(state),
    );
  }

  /// **Στοχευμένη αλλαγή** — αλλάζει μόνο ό,τι άγγιξε ο χρήστης.
  ///
  /// Δεκαπέντε επιλογές ζουν σε ΕΝΑ κλειδί. Γράφοντας ολόκληρο το JSON από την
  /// εικόνα της οθόνης σβήναμε την επιλογή που μόλις άλλαξε ο άλλος
  /// διαχειριστής — κανείς δεν *θέλησε* να την αλλάξει, την κουβάλησε η
  /// μπαγιάτικη εικόνα. Η [change] εφαρμόζεται στη **φρέσκια** αποθηκευμένη
  /// τιμή, μέσα σε ατομική δέσμευση, οπότε οφείλει να είναι καθαρή (μπορεί να
  /// ξανατρέξει).
  ///
  /// Η οθόνη ενημερώνεται δύο φορές επίτηδες: αμέσως με την αισιόδοξη εικόνα,
  /// ώστε ο διακόπτης να μη «κολλάει» όσο γράφει η δικτυακή βάση, και μετά με
  /// ό,τι **όντως** αποθηκεύτηκε — εκεί φαίνονται και οι αλλαγές του άλλου.
  Future<void> _applyTargeted(
    LansweeperTicketSubmitConfig Function(LansweeperTicketSubmitConfig current)
    change,
  ) async {
    state = change(state);
    final db = await DatabaseHelper.instance.database;
    if (!ref.mounted) return;
    final storedRaw = await SettingsRepository(db).updateSetting(
      kLansweeperTicketSubmitConfigSettingKey,
      (raw) =>
          LansweeperTicketSubmitConfig.encodeForStorage(change(_decode(raw))),
    );
    if (!ref.mounted) return;
    state = LansweeperTicketSubmitConfig.decodeFromStorage(storedRaw);
  }

  /// Στοχευμένη αλλαγή **λίστας** — με φρουρό αντί για σιωπηλή συγχώνευση.
  ///
  /// Τις λίστες τις πληκτρολογεί ο χρήστης ολόκληρες, οπότε η εφαρμογή δεν
  /// μπορεί να ξέρει αν μια τιμή που λείπει σβήστηκε επίτηδες. Αν κάποιος
  /// πρόλαβε, πετιέται [SettingsListStaleException] και αποφασίζει ο άνθρωπος
  /// (απόφαση Διευθυντή 25/08/2026). Το [expected] `null` ή το [force] `true`
  /// γράφει χωρίς έλεγχο — ο τρόπος να επιμείνει ο χρήστης εν γνώσει του.
  Future<void> _applyGuardedList({
    required List<String> next,
    required List<String>? expected,
    required bool force,
    required List<String> Function(LansweeperTicketSubmitConfig current) read,
    required LansweeperTicketSubmitConfig Function(
      LansweeperTicketSubmitConfig current,
    )
    change,
  }) {
    final baseline = expected == null ? null : _csv(expected);
    return _applyTargeted((current) {
      if (!force && baseline != null) {
        final fresh = _csv(read(current));
        if (fresh != baseline) {
          throw SettingsListStaleException(
            SettingsListConflict(
              expected: baseline,
              fresh: fresh,
              attempted: _csv(next),
            ),
          );
        }
      }
      return change(current);
    });
  }

  static LansweeperTicketSubmitConfig _decode(String? raw) => raw == null
      ? LansweeperTicketSubmitConfig.defaults()
      : LansweeperTicketSubmitConfig.decodeFromStorage(raw);

  /// Η λίστα σε μορφή που καταλαβαίνει ο [SettingsListConflict].
  static String _csv(Iterable<String> values) => values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .join(', ');

  Future<void> replace(
    LansweeperTicketSubmitConfig next, {
    bool persist = true,
  }) async {
    state = next;
    if (persist) await _persistWholeConfig();
  }

  /// Ρητή αντικατάσταση όλων — γι' αυτό γράφει ολόκληρη τη ρύθμιση.
  Future<void> resetToDefaults() async {
    state = LansweeperTicketSubmitConfig.defaults();
    await _persistWholeConfig();
  }

  Future<void> setNoteType(String value) =>
      _applyTargeted((current) => current.copyWith(noteType: value));

  Future<void> setDefaultTicketState(String value) =>
      _applyTargeted((current) => current.copyWith(defaultTicketState: value));

  Future<void> setTicketStates(
    List<String> value, {
    required List<String>? expected,
    bool force = false,
  }) => _applyGuardedList(
    next: value,
    expected: expected,
    force: force,
    read: (current) => current.ticketStates,
    change: (current) => current.copyWith(ticketStates: value),
  );

  /// Τα προσαρμοσμένα πεδία είναι κι αυτά λίστα που διαχειρίζεται ο χρήστης
  /// ολόκληρη (προσθήκη, διαγραφή, αναδιάταξη) — ίδιος φρουρός, με τις
  /// **ετικέτες** των πεδίων ως στοιχεία που διαβάζει ο άνθρωπος.
  Future<void> replaceCustomFields(
    List<LansweeperCustomFieldDef> value, {
    required List<LansweeperCustomFieldDef>? expected,
    bool force = false,
  }) => _applyGuardedList(
    next: value.map((field) => field.formLabel).toList(),
    expected: expected?.map((field) => field.formLabel).toList(),
    force: force,
    read: (current) =>
        current.customFields.map((field) => field.formLabel).toList(),
    change: (current) => current.copyWith(customFields: value),
  );

  Future<void> setTicketType(String value) => _applyTargeted((current) {
    final types = LansweeperTicketSubmitConfig.ensureSelectedInList(
      current.ticketTypes,
      value,
      fallbackList: LansweeperTicketSubmitConfig.defaultTicketTypes,
    );
    return current.copyWith(ticketType: value, ticketTypes: types);
  });

  Future<void> setTicketTypes(
    List<String> value, {
    required List<String>? expected,
    bool force = false,
  }) => _applyGuardedList(
    next: value,
    expected: expected,
    force: force,
    read: (current) => current.ticketTypes,
    change: (current) {
      final types = LansweeperTicketSubmitConfig.ensureSelectedInList(
        value,
        current.ticketType,
        fallbackList: LansweeperTicketSubmitConfig.defaultTicketTypes,
      );
      final selected = types.contains(current.ticketType)
          ? current.ticketType
          : types.first;
      return current.copyWith(ticketTypes: types, ticketType: selected);
    },
  );

  Future<void> setPriority(String value) => _applyTargeted((current) {
    final list = LansweeperTicketSubmitConfig.ensureSelectedInList(
      current.priorities,
      value,
      fallbackList: LansweeperTicketSubmitConfig.defaultPriorities,
    );
    return current.copyWith(priority: value, priorities: list);
  });

  Future<void> setPriorities(
    List<String> value, {
    required List<String>? expected,
    bool force = false,
  }) => _applyGuardedList(
    next: value,
    expected: expected,
    force: force,
    read: (current) => current.priorities,
    change: (current) {
      final list = LansweeperTicketSubmitConfig.ensureSelectedInList(
        value,
        current.priority,
        fallbackList: LansweeperTicketSubmitConfig.defaultPriorities,
      );
      final selected = list.contains(current.priority)
          ? current.priority
          : list.first;
      return current.copyWith(priorities: list, priority: selected);
    },
  );

  Future<void> setTeam(String value) => _applyTargeted((current) {
    final list = LansweeperTicketSubmitConfig.ensureSelectedInList(
      current.teams,
      value,
      fallbackList: LansweeperTicketSubmitConfig.defaultTeams,
    );
    return current.copyWith(team: value, teams: list);
  });

  Future<void> setTeams(
    List<String> value, {
    required List<String>? expected,
    bool force = false,
  }) => _applyGuardedList(
    next: value,
    expected: expected,
    force: force,
    read: (current) => current.teams,
    change: (current) {
      final list = LansweeperTicketSubmitConfig.ensureSelectedInList(
        value,
        current.team,
        fallbackList: LansweeperTicketSubmitConfig.defaultTeams,
      );
      final selected = list.contains(current.team) ? current.team : list.first;
      return current.copyWith(teams: list, team: selected);
    },
  );

  Future<void> setEnableAddNoteStep(bool value) =>
      _applyTargeted((current) => current.copyWith(enableAddNoteStep: value));

  Future<void> setEnableStateUpdateStep(bool value) => _applyTargeted(
    (current) => current.copyWith(enableStateUpdateStep: value),
  );

  Future<void> setRememberFormSelections(bool value) => _applyTargeted(
    (current) => current.copyWith(rememberFormSelections: value),
  );

  Future<void> setIncludeNoteTime(bool value) =>
      _applyTargeted((current) => current.copyWith(includeNoteTime: value));
}

final lansweeperTicketSubmitConfigProvider =
    NotifierProvider.autoDispose<
      LansweeperTicketSubmitConfigNotifier,
      LansweeperTicketSubmitConfig
    >(LansweeperTicketSubmitConfigNotifier.new);
