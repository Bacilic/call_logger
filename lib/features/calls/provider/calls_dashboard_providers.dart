import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/calls_repository.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/services/settings_service.dart';
import '../models/call_model.dart';

/// Τελευταίες κλήσεις ανά caller_id (limit 3).
final recentCallsProvider = FutureProvider.family<List<CallModel>, int>((
  ref,
  callerId,
) async {
  final db = await DatabaseHelper.instance.database;
  final maps = await CallsRepository(
    db,
  ).getRecentCallsByCallerId(callerId, limit: 3);
  return maps.map((m) => CallModel.fromMap(m)).toList();
});

/// Τελευταίες κλήσεις ανά εξοπλισμό (limit 3, βάσει equipment code).
final recentCallsByEquipmentProvider =
    FutureProvider.family<List<CallModel>, String>((ref, equipmentCode) async {
      final code = equipmentCode.trim();
      if (code.isEmpty) return const <CallModel>[];
      final db = await DatabaseHelper.instance.database;
      final maps = await CallsRepository(
        db,
      ).getRecentCallsByEquipmentCode(code, limit: 3);
      return maps.map((m) => CallModel.fromMap(m)).toList();
    });

/// Καθολικές τελευταίες κλήσεις (limit 7) για το dashboard δεξιά.
final globalRecentCallsProvider = FutureProvider<List<CallModel>>((ref) async {
  final db = await DatabaseHelper.instance.database;
  final maps = await CallsRepository(db).getRecentCalls(limit: 7);
  return maps.map((m) => CallModel.fromMap(m)).toList();
});

/// Toggle ορατότητας για το global recent-calls panel.
final showGlobalCallsToggleProvider =
    NotifierProvider<ShowGlobalCallsToggleNotifier, bool>(
      ShowGlobalCallsToggleNotifier.new,
    );

class ShowGlobalCallsToggleNotifier extends Notifier<bool> {
  bool _loadedFromStorage = false;

  @override
  bool build() {
    if (!_loadedFromStorage) {
      _loadedFromStorage = true;
      unawaited(_hydrateFromStorage());
    }
    return true;
  }

  Future<void> _hydrateFromStorage() async {
    final value = await SettingsService().getShowGlobalCalls();
    if (ref.mounted) {
      state = value;
    }
  }

  Future<void> setVisible(bool value) async {
    if (state == value) return;
    state = value;
    await SettingsService().setShowGlobalCalls(value);
  }

  Future<void> toggle() async => setVisible(!state);
}
