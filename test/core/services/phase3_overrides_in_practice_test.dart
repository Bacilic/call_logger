// Φάση 3 στην πράξη: οι δύο ρυθμίσεις που απέκτησαν παράκαμψη.
//
// 1. Διαδρομή εργαλείου — τοπική, ανά υπολογιστή: όποιος τη διορθώνει για το
//    μηχάνημά του δεν τη χαλάει πια για τους υπόλοιπους.
// 2. Κλειδί ΤΝ — προσωπικό, ανά χρήστη: τον ακολουθεί όπου καθίσει.
//
//   flutter test test/core/services/phase3_overrides_in_practice_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/operator_settings_repository.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/services/gemini_api_key_resolution.dart';
import 'package:call_logger/core/services/overridable_settings.dart';
import 'package:call_logger/core/services/remote_tools_paths_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_setup.dart';

Operator _operator(int id) => Operator(
  id: id,
  displayName: 'Χρήστης $id',
  createdAt: DateTime(2026, 8, 20),
);

RemoteTool _tool({required int id, required String path}) => RemoteTool(
  id: id,
  name: 'AnyDesk',
  role: ToolRole.generic,
  executablePath: path,
  sortOrder: 0,
  isActive: true,
);

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    CurrentOperator.reset();
    final db = await DatabaseHelper.instance.database;
    await db.delete(OperatorSettingsRepository.tableName);
    await db.delete(
      'app_settings',
      where: 'key = ?',
      whereArgs: [kGeminiApiKeySettingKey],
    );
  });

  tearDown(CurrentOperator.reset);

  group('Διαδρομή εργαλείου — τοπική παράκαμψη', () {
    test('χωρίς παράκαμψη ισχύει η κοινή του ορισμού', () async {
      final tool = _tool(id: 1, path: r'C:\koino\AnyDesk.exe');
      expect(await effectiveExecutablePath(tool), r'C:\koino\AnyDesk.exe');
    });

    test('με παράκαμψη ισχύει η τοπική — η κοινή μένει ανέπαφη', () async {
      final tool = _tool(id: 1, path: r'C:\koino\AnyDesk.exe');
      await OverridableSettings.setOverride(
        OverridableSettingKeys.remoteToolExecutablePath.forId(1),
        r'D:\Programs\AnyDesk.exe',
      );

      expect(await effectiveExecutablePath(tool), r'D:\Programs\AnyDesk.exe');
      expect(
        tool.executablePath,
        r'C:\koino\AnyDesk.exe',
        reason: 'Ο κοινός ορισμός δεν αγγίζεται — οι συνάδελφοι συνεχίζουν.',
      );
    });

    test('η παράκαμψη είναι ανά εργαλείο, δεν διαρρέει', () async {
      await OverridableSettings.setOverride(
        OverridableSettingKeys.remoteToolExecutablePath.forId(1),
        r'D:\AnyDesk.exe',
      );

      final other = _tool(id: 2, path: r'C:\koino\VNC.exe');
      expect(await effectiveExecutablePath(other), r'C:\koino\VNC.exe');
    });

    test('«Χρήση της κοινής» επαναφέρει τον ορισμό', () async {
      final tool = _tool(id: 1, path: r'C:\koino\AnyDesk.exe');
      final key = OverridableSettingKeys.remoteToolExecutablePath.forId(1);

      await OverridableSettings.setOverride(key, r'D:\AnyDesk.exe');
      await OverridableSettings.clearOverride(key);

      expect(await effectiveExecutablePath(tool), r'C:\koino\AnyDesk.exe');
    });

    test('κενή παράκαμψη σημαίνει «κανένα πρόγραμμα εδώ»', () async {
      final tool = _tool(id: 1, path: r'C:\koino\AnyDesk.exe');
      await OverridableSettings.setOverride(
        OverridableSettingKeys.remoteToolExecutablePath.forId(1),
        '',
      );

      expect(
        await effectiveExecutablePath(tool),
        isEmpty,
        reason: 'Ρητά δηλωμένη κενή — δεν πέφτουμε πίσω στην κοινή.',
      );
    });
  });

  group('Κλειδί ΤΝ — προσωπική παράκαμψη', () {
    Future<void> setShared(String value) async {
      final db = await DatabaseHelper.instance.database;
      await SettingsRepository(db).saveSetting(kGeminiApiKeySettingKey, value);
    }

    test('χωρίς προσωπικό ισχύει το κοινό της ομάδας', () async {
      await setShared('KOINO-KEY');
      CurrentOperator.activate(_operator(1));
      expect(await resolveGeminiApiKey(), 'KOINO-KEY');
    });

    test('με προσωπικό ισχύει το προσωπικό', () async {
      await setShared('KOINO-KEY');
      CurrentOperator.activate(_operator(1));
      await OverridableSettings.setOverride(
        OverridableSettingKeys.geminiApiKey,
        'DIKO-MOU',
      );

      expect(await resolveGeminiApiKey(), 'DIKO-MOU');
    });

    test('ο άλλος χρήστης δεν βλέπει το προσωπικό μου', () async {
      await setShared('KOINO-KEY');
      CurrentOperator.activate(_operator(1));
      await OverridableSettings.setOverride(
        OverridableSettingKeys.geminiApiKey,
        'DIKO-MOU',
      );

      CurrentOperator.activate(_operator(2));
      expect(await resolveGeminiApiKey(), 'KOINO-KEY');
    });

    test('η οθόνη και ο εκτελεστής διαβάζουν την ΙΔΙΑ αλυσίδα', () async {
      // Δύο σημεία ζητούν το κλειδί: ο provider της οθόνης και ο εκτελεστής
      // των κλήσεων. Αν αποκλίνουν, η οθόνη δείχνει άλλο κλειδί από αυτό που
      // φεύγει στο δίκτυο.
      await setShared('KOINO-KEY');
      CurrentOperator.activate(_operator(1));
      await OverridableSettings.setOverride(
        OverridableSettingKeys.geminiApiKey,
        'DIKO-MOU',
      );

      final fromChain = await resolveGeminiApiKey();
      final fromChainAgain = await resolveGeminiApiKey();
      expect(fromChain, fromChainAgain);
      expect(fromChain, 'DIKO-MOU');
    });
  });
}
