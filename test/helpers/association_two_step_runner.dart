import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_v1_schema.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'association_two_step_scenarios.dart';

/// Αποτέλεσμα εκτέλεσης ενός σενάριου πράσινο → πορτοκαλί.
class AssociationTwoStepResult {
  const AssociationTwoStepResult({
    required this.scenario,
    required this.passed,
    required this.failures,
    required this.greenMessage,
    required this.orangeMessage,
    required this.userCountAfterGreen,
    required this.userCountAfterOrange,
    required this.equipmentCountAfterOrange,
    required this.needsAssociationAfterOrange,
    required this.selectedCallerIdAfterOrange,
    required this.userDepartmentNameAfterOrange,
  });

  final AssociationTwoStepScenario scenario;
  final bool passed;
  final List<String> failures;
  final String? greenMessage;
  final String? orangeMessage;
  final int userCountAfterGreen;
  final int userCountAfterOrange;
  final int equipmentCountAfterOrange;
  final bool needsAssociationAfterOrange;
  final int? selectedCallerIdAfterOrange;
  final String? userDepartmentNameAfterOrange;
}

/// Εκτελεί σενάρια διφασικής συσχέτισης με πραγματική SQLite (sqflite FFI).
class AssociationTwoStepRunner {
  AssociationTwoStepRunner._();

  static Future<void> resetCatalog({
    String? preseedDepartmentName,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await migrateDatabaseToV11(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS departments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        building TEXT,
        color TEXT DEFAULT '#1976D2',
        notes TEXT,
        map_floor TEXT,
        map_x REAL DEFAULT 0.0,
        map_y REAL DEFAULT 0.0,
        map_width REAL DEFAULT 0.0,
        map_height REAL DEFAULT 0.0,
        is_deleted INTEGER DEFAULT 0
      )
    ''');
    for (final table in [
      'tasks',
      'user_equipment',
      'user_phones',
      'phones',
      'equipment',
      'users',
      'categories',
      'departments',
    ]) {
      try {
        await db.delete(table);
      } catch (_) {}
    }

    if (preseedDepartmentName != null && preseedDepartmentName.trim().isNotEmpty) {
      await db.insert('departments', {
        'name': preseedDepartmentName,
        'name_key': SearchTextNormalizer.normalizeForSearch(
          preseedDepartmentName,
        ),
        'is_deleted': 0,
      });
    }

    LookupService.instance.resetForReload();
    await LookupService.instance.loadFromDatabase();
  }

  static Future<ProviderContainer> createContainer() async {
    final container = ProviderContainer(
      overrides: [
        lookupServiceProvider.overrideWith((ref) async {
          final service = LookupService.instance;
          service.resetForReload();
          await service.loadFromDatabase();
          return LookupLoadResult(service: service);
        }),
      ],
    );
    await container.read(lookupServiceProvider.future);
    return container;
  }

  static Future<int> _countActiveUsers(Database db) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM users WHERE COALESCE(is_deleted, 0) = 0',
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  static Future<int> _countEquipmentByCode(Database db, String code) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c FROM equipment
      WHERE code_equipment = ? AND COALESCE(is_deleted, 0) = 0
      ''',
      [code],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  static Future<String?> _userDepartmentName(Database db, int userId) async {
    final rows = await db.rawQuery(
      '''
      SELECT d.name AS name FROM users u
      LEFT JOIN departments d ON d.id = u.department_id
      WHERE u.id = ?
      ''',
      [userId],
    );
    if (rows.isEmpty) return null;
    return rows.first['name'] as String?;
  }

  static String _suffixFromId(String id) {
    final match = RegExp(r'(\d+)').firstMatch(id);
    return match?.group(1) ?? '0';
  }

  static void _applyGreenFields({
    required SmartEntitySelectorNotifier notifier,
    required AssociationTwoStepScenario scenario,
    required String suffix,
  }) {
    final caller = scenario.callerFor(suffix);
    notifier.updateCallerDisplayText(caller);
    notifier.checkContent(callerText: caller);

    if (scenario.greenPhone) {
      final phone = scenario.phoneFor(suffix);
      notifier.updatePhone(phone);
      notifier.checkContent(phoneText: phone);
    }

    if (scenario.greenDepartment) {
      final dept = scenario.preseedDepartmentName ??
          scenario.departmentFor(suffix);
      notifier.updateDepartmentText(dept);
      notifier.checkContent(departmentText: dept);
    }

    if (scenario.greenEquipment) {
      final equip = scenario.equipmentFor(suffix);
      notifier.checkContent(equipmentText: equip);
    }
  }

  static void _applyOrangeFill({
    required SmartEntitySelectorNotifier notifier,
    required AssociationTwoStepScenario scenario,
    required String suffix,
  }) {
    switch (scenario.orangeFill) {
      case AssociationOrangeFill.none:
        return;
      case AssociationOrangeFill.phone:
        final phone = scenario.phoneFor(suffix);
        // Προσομοίωση πληκτρολόγησης τηλεφώνου (όπως στο UI) — σημείο αδυναμίας.
        notifier.updatePhone(phone);
        notifier.checkContent(phoneText: phone);
      case AssociationOrangeFill.department:
        final dept = scenario.preseedDepartmentName ??
            scenario.departmentFor(suffix);
        notifier.updateDepartmentText(dept);
        notifier.checkContent(departmentText: dept);
      case AssociationOrangeFill.equipment:
        final equip = scenario.equipmentFor(suffix);
        notifier.checkContent(equipmentText: equip);
        notifier.performEquipmentLookupByCode(equip);
    }
  }

  static List<String> _evaluate({
    required AssociationTwoStepScenario scenario,
    required String? greenMessage,
    required String? orangeMessage,
    required int userCountAfterGreen,
    required int userCountAfterOrange,
    required int equipmentCountAfterOrange,
    required bool needsAssociationAfterOrange,
    required int? selectedCallerIdAfterOrange,
    required String? userDepartmentNameAfterOrange,
    required String equipmentCode,
    required String departmentName,
  }) {
    final failures = <String>[];

    if (userCountAfterGreen != 1) {
      failures.add(
        'Μετά πράσινο: αναμενόταν 1 χρήστης, βρέθηκαν $userCountAfterGreen.',
      );
    }
    if (userCountAfterOrange != 1) {
      failures.add(
        'Μετά πορτοκαλί: αναμενόταν 1 χρήστης, βρέθηκαν $userCountAfterOrange.',
      );
    }

    if (greenMessage == null || greenMessage.trim().isEmpty) {
      failures.add('Το πράσινο βήμα δεν επέστρεψε μήνυμα επιτυχίας.');
    } else if (greenMessage.contains('Σφάλμα')) {
      failures.add('Το πράσινο βήμα επέστρεψε σφάλμα: $greenMessage');
    }

    if (scenario.hasOrangeStep) {
      if (needsAssociationAfterOrange) {
        failures.add(
          'Μετά πορτοκαλί το needsAssociation παραμένει true (ατελής συσχέτιση).',
        );
      }

      if (orangeMessage == null || orangeMessage.trim().isEmpty) {
        failures.add(
          'Το πορτοκαλί βήμα δεν επέστρεψε μήνυμα — συμπεριφορά «δεν γίνεται τίποτα».',
        );
      } else if (orangeMessage.contains('Δημιουργήθηκε νέος χρήστης')) {
        failures.add(
          'Το πορτοκαλί μήνυμα λανθασμένα αναφέρει δημιουργία νέου χρήστη.',
        );
      } else if (orangeMessage.contains('Σφάλμα')) {
        failures.add('Το πορτοκαλί βήμα επέστρεψε σφάλμα: $orangeMessage');
      }

      if (scenario.orangeFill == AssociationOrangeFill.equipment) {
        if (equipmentCountAfterOrange != 1) {
          failures.add(
            'Εξοπλισμός $equipmentCode: αναμενόταν 1 εγγραφή, βρέθηκαν $equipmentCountAfterOrange.',
          );
        }
      }

      if (scenario.orangeFill == AssociationOrangeFill.department &&
          scenario.updatePrimaryDepartmentOnOrange == true) {
        final norm = SearchTextNormalizer.normalizeForSearch(departmentName);
        final actualNorm = userDepartmentNameAfterOrange == null
            ? ''
            : SearchTextNormalizer.normalizeForSearch(
                userDepartmentNameAfterOrange,
              );
        if (actualNorm != norm) {
          failures.add(
            'Μετά πορτοκαλί (dialog Ναι) το κύριο τμήμα του χρήστη είναι '
            '"$userDepartmentNameAfterOrange" αντί για "$departmentName".',
          );
        }
      }

      if (scenario.orangeFill == AssociationOrangeFill.phone &&
          selectedCallerIdAfterOrange == null) {
        failures.add('Μετά πορτοκαλί λείπει selectedCaller.id.');
      }
    } else {
      // G7: όλα στο πράσινο
      if (equipmentCountAfterOrange != 1) {
        failures.add(
          'G7: αναμενόταν 1 εξοπλισμός $equipmentCode, βρέθηκαν $equipmentCountAfterOrange.',
        );
      }
      if (needsAssociationAfterOrange) {
        failures.add('G7: needsAssociation παραμένει true μετά πλήρες πράσινο.');
      }
    }

    return failures;
  }

  static Future<AssociationTwoStepResult> run(
    ProviderContainer container,
    AssociationTwoStepScenario scenario,
  ) async {
    final suffix = _suffixFromId(scenario.id);
    final notifier = container.read(callSmartEntityProvider.notifier);
    final lookup = (await container.read(lookupServiceProvider.future)).service;
    final db = await DatabaseHelper.instance.database;
    final equipmentCode = scenario.equipmentFor(suffix);
    final departmentName =
        scenario.preseedDepartmentName ?? scenario.departmentFor(suffix);

    _applyGreenFields(
      notifier: notifier,
      scenario: scenario,
      suffix: suffix,
    );

    final stateBeforeGreen = container.read(callSmartEntityProvider);
    if (!stateBeforeGreen.needsNewCallerCreation) {
      return AssociationTwoStepResult(
        scenario: scenario,
        passed: false,
        failures: [
          'Πριν το πράσινο: needsNewCallerCreation=false (μη έγκυρη αρχική κατάσταση).',
        ],
        greenMessage: null,
        orangeMessage: null,
        userCountAfterGreen: await _countActiveUsers(db),
        userCountAfterOrange: await _countActiveUsers(db),
        equipmentCountAfterOrange: await _countEquipmentByCode(db, equipmentCode),
        needsAssociationAfterOrange: stateBeforeGreen.needsAssociation(lookup),
        selectedCallerIdAfterOrange: stateBeforeGreen.selectedCaller?.id,
        userDepartmentNameAfterOrange: null,
      );
    }

    final greenMessage = await notifier.associateCurrentIfNeeded();
    await container.read(lookupServiceProvider.future);

    final userCountAfterGreen = await _countActiveUsers(db);

    String? orangeMessage;
    if (scenario.hasOrangeStep) {
      _applyOrangeFill(
        notifier: notifier,
        scenario: scenario,
        suffix: suffix,
      );

      final stateBeforeOrange = container.read(callSmartEntityProvider);
      if (!stateBeforeOrange.needsAssociation(lookup)) {
        orangeMessage = null;
      } else {
        orangeMessage = await notifier.associateCurrentIfNeeded(
          updatePrimaryDepartment:
              scenario.updatePrimaryDepartmentOnOrange ?? false,
        );
        await container.read(lookupServiceProvider.future);
      }
    }

    final stateAfterOrange = container.read(callSmartEntityProvider);
    final lookupAfter = (await container.read(lookupServiceProvider.future))
        .service;
    final userCountAfterOrange = await _countActiveUsers(db);
    final equipmentCount = await _countEquipmentByCode(db, equipmentCode);
    final callerId = stateAfterOrange.selectedCaller?.id;
    String? deptName;
    if (callerId != null) {
      deptName = await _userDepartmentName(db, callerId);
    }

    final failures = _evaluate(
      scenario: scenario,
      greenMessage: greenMessage,
      orangeMessage: orangeMessage,
      userCountAfterGreen: userCountAfterGreen,
      userCountAfterOrange: userCountAfterOrange,
      equipmentCountAfterOrange: equipmentCount,
      needsAssociationAfterOrange:
          stateAfterOrange.needsAssociation(lookupAfter),
      selectedCallerIdAfterOrange: callerId,
      userDepartmentNameAfterOrange: deptName,
      equipmentCode: equipmentCode,
      departmentName: departmentName,
    );

    return AssociationTwoStepResult(
      scenario: scenario,
      passed: failures.isEmpty,
      failures: failures,
      greenMessage: greenMessage,
      orangeMessage: orangeMessage,
      userCountAfterGreen: userCountAfterGreen,
      userCountAfterOrange: userCountAfterOrange,
      equipmentCountAfterOrange: equipmentCount,
      needsAssociationAfterOrange:
          stateAfterOrange.needsAssociation(lookupAfter),
      selectedCallerIdAfterOrange: callerId,
      userDepartmentNameAfterOrange: deptName,
    );
  }
}

/// Χρώμα πριν το πράσινο — βοηθητικό για logs.
Color? expectedAssociationColorBeforeGreen(
  SmartEntitySelectorState state,
  LookupService? lookup,
) {
  if (!state.needsAssociation(lookup)) return null;
  return state.associationColor(lookup);
}
