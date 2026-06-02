import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// Αποθήκευση/επαναφορά όλων των κλειδιών SharedPreferences του τρέχοντος CLI προφίλ.
class ApplicationPrefsSnapshot {
  ApplicationPrefsSnapshot._();

  static const int _formatVersion = 1;

  static String _profileScopeLabel() {
    final name = AppConfig.activeProfile?.trim();
    return (name == null || name.isEmpty) ? 'production' : name;
  }

  static Future<File> _snapshotFile() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'reset_snapshots'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(
      p.join(dir.path, 'pending_reset_${_profileScopeLabel()}.json'),
    );
  }

  static bool _keyBelongsToCurrentProfile(String key) {
    final profile = AppConfig.activeProfile?.trim();
    if (profile == null || profile.isEmpty) {
      return !key.startsWith('profile_');
    }
    final prefix = 'profile_${profile}_';
    return key.startsWith(prefix);
  }

  /// Αντιγράφει όλα τα prefs του τρέχοντος προφίλ σε αρχείο JSON.
  static Future<void> writeToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = <String, Object>{};
    for (final key in prefs.getKeys()) {
      if (!_keyBelongsToCurrentProfile(key)) continue;
      final value = prefs.get(key);
      if (value != null) {
        entries[key] = value;
      }
    }
    final payload = <String, dynamic>{
      'version': _formatVersion,
      'profile_scope': _profileScopeLabel(),
      'captured_at': DateTime.now().toIso8601String(),
      'entries': entries,
    };
    final file = await _snapshotFile();
    await file.writeAsString(jsonEncode(payload));
  }

  static Future<bool> snapshotExistsOnDisk() async {
    return (await _snapshotFile()).exists();
  }

  /// Επαναφέρει prefs από το αρχείο snapshot και διαγράφει το αρχείο.
  static Future<bool> restoreFromDisk() async {
    final file = await _snapshotFile();
    if (!await file.exists()) return false;

    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      await _deleteSnapshotFile();
      return false;
    }
    final entriesRaw = decoded['entries'];
    if (entriesRaw is! Map) {
      await _deleteSnapshotFile();
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (_keyBelongsToCurrentProfile(key)) {
        await prefs.remove(key);
      }
    }

    for (final entry in entriesRaw.entries) {
      final key = entry.key.toString();
      if (!_keyBelongsToCurrentProfile(key)) continue;
      final value = entry.value;
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is List) {
        await prefs.setStringList(
          key,
          value.map((e) => e.toString()).toList(),
        );
      }
    }

    await _deleteSnapshotFile();
    return true;
  }

  static Future<void> deleteSnapshotFile() => _deleteSnapshotFile();

  static Future<void> _deleteSnapshotFile() async {
    final file = await _snapshotFile();
    if (await file.exists()) {
      await file.delete();
    }
  }
}
