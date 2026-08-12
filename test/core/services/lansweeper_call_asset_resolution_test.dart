// Ο εξοπλισμός φτάνει στο ticket ακόμη κι όταν η κλήση κρατά ΜΟΝΟ το κείμενο
// του κωδικού, χωρίς σύνδεση στην καρτέλα του Καταλόγου (σενάριο 12/08/2026:
// κλήση με «470», εξοπλισμός 470 υπαρκτός, ticket χωρίς asset).
//
//   flutter test test/core/services/lansweeper_call_asset_resolution_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/equipment_repository.dart';
import 'package:call_logger/core/services/lansweeper_asset_target.dart';
import 'package:call_logger/core/services/lansweeper_call_asset_resolution.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late Database db;
  late EquipmentRepository repo;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('call_asset_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/asset.db');
    db = await DatabaseHelper.instance.database;
    repo = EquipmentRepository(db);
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
    await db.delete('equipment');
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  Future<int> insertEquipment({
    required String code,
    String? assetName,
    bool isDeleted = false,
  }) {
    return db.insert('equipment', {
      'code_equipment': code,
      'lansweeper_asset_name': assetName,
      'is_deleted': isDeleted ? 1 : 0,
    });
  }

  test(
    'κλήση με κείμενο κωδικού χωρίς σύνδεση παίρνει τον εξοπλισμό του Καταλόγου',
    () async {
      await insertEquipment(code: '470');

      final target = await resolveCallLansweeperAsset(
        repository: repo,
        equipmentId: null,
        equipmentText: '470',
      );

      expect(target?.value, 'PC470');
      expect(target?.kind, LansweeperAssetTargetKind.assetName);
    },
  );

  test(
    'η καρτέλα του Καταλόγου κερδίζει: το δικό της αναγνωριστικό, όχι PC+κωδικός',
    () async {
      await insertEquipment(code: '470', assetName: '10.10.5.7');

      final target = await resolveCallLansweeperAsset(
        repository: repo,
        equipmentId: null,
        equipmentText: '470',
      );

      expect(target?.value, '10.10.5.7');
      expect(target?.kind, LansweeperAssetTargetKind.ipAddress);
    },
  );

  test('κωδικός εκτός Καταλόγου πέφτει στον κανόνα «PC + κωδικός»', () async {
    final target = await resolveCallLansweeperAsset(
      repository: repo,
      equipmentId: null,
      equipmentText: '3675',
    );

    expect(target?.value, 'PC3675');
  });

  test('η σύνδεση προηγείται του κειμένου όταν τα δύο διαφωνούν', () async {
    final linkedId = await insertEquipment(code: '999', assetName: 'PRINTER-A');
    await insertEquipment(code: '470');

    final target = await resolveCallLansweeperAsset(
      repository: repo,
      equipmentId: linkedId,
      equipmentText: '470',
    );

    expect(target?.value, 'PRINTER-A');
  });

  test('διαγραμμένη καρτέλα δεν χρησιμοποιείται — μένει ο κανόνας', () async {
    await insertEquipment(code: '470', assetName: 'OLD-ASSET', isDeleted: true);

    final target = await resolveCallLansweeperAsset(
      repository: repo,
      equipmentId: null,
      equipmentText: '470',
    );

    expect(target?.value, 'PC470');
  });

  test('κενό κείμενο χωρίς σύνδεση δεν δίνει εξοπλισμό', () async {
    expect(
      await resolveCallLansweeperAsset(
        repository: repo,
        equipmentId: null,
        equipmentText: '   ',
      ),
      isNull,
    );
    expect(
      await resolveCallLansweeperAsset(
        repository: repo,
        equipmentId: null,
        equipmentText: null,
      ),
      isNull,
    );
  });

  test('κείμενο που δεν βγάζει έγκυρο στόχο δεν δίνει εξοπλισμό', () async {
    final target = await resolveCallLansweeperAsset(
      repository: repo,
      equipmentId: null,
      equipmentText: '12',
    );

    expect(
      target,
      isNull,
      reason: 'δύο ψηφία δεν είναι έγκυρος κωδικός εξοπλισμού (3–6)',
    );
  });

  test('IPv4 στο κείμενο μένει IPv4', () async {
    final target = await resolveCallLansweeperAsset(
      repository: repo,
      equipmentId: null,
      equipmentText: '10.10.201.22',
    );

    expect(target?.value, '10.10.201.22');
    expect(target?.kind, LansweeperAssetTargetKind.ipAddress);
  });
}
