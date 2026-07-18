// Ακριβές κωδικός εξοπλισμού έναντι μερικών ταιριασμάτων (π.χ. 506 vs 5067).
//
//   flutter test test/features/calls/smart_entity_equipment_exact_code_match_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/phone_list_parser.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

const _kDeptId = 1;
const _kDeptName = 'Γραμματεία ΤΕΠ';
const _kOwnerId = 10;
const _kPhone = '2534';

Future<ProviderContainer> _containerWithPrefixCodes() async {
  final owner = UserModel(
    id: _kOwnerId,
    firstName: 'Βαρβάρα',
    lastName: 'Νακαστσή',
    phones: PhoneListParser.splitPhones(_kPhone),
    departmentId: _kDeptId,
  );
  final equipment = [
    EquipmentModel(id: 506, code: '506', type: 'PC'),
    EquipmentModel(id: 5067, code: '5067', type: 'PC'),
    EquipmentModel(id: 5068, code: '5068', type: 'PC'),
    EquipmentModel(id: 5069, code: '5069', type: 'PC'),
  ];
  final svc = LookupService.instance;
  svc.resetForReload();
  svc.injectInMemoryCatalogForTests(
    users: [owner],
    equipment: equipment,
    departmentRows: [
      DepartmentModel(id: _kDeptId, name: _kDeptName),
    ],
    userToEquipmentIds: {
      _kOwnerId: [506],
    },
  );
  final container = ProviderContainer(
    overrides: [
      lookupServiceProvider.overrideWith(
        (ref) async => LookupLoadResult(service: svc),
      ),
    ],
  );
  await container.read(lookupServiceProvider.future);
  return container;
}

void main() {
  group('performEquipmentLookupByCode · ακριβής κωδικός vs πρόθεμα', () {
    test(
      'α) κατοχύρωση «506» με υπάρχοντες 5067/5068/5069 → επιλογή 506 και γέμισμα',
      () async {
        final container = await _containerWithPrefixCodes();
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);

        n.performEquipmentLookupByCode('506');
        final s = container.read(callSmartEntityProvider);

        expect(
          s.selectedEquipment?.code,
          '506',
          reason: greekExpectMsg(
            'Ο ακριβής κωδικός 506 πρέπει να επιλέγεται παρά τα πρόθεμα-ταιριάσματα',
          ),
        );
        expect(s.isEquipmentAmbiguous, isFalse);
        expect(s.equipmentCandidates, isEmpty);
        expect(
          s.selectedCaller?.id,
          _kOwnerId,
          reason: greekExpectMsg('Πρέπει να γεμίζει ο κάτοχος του 506'),
        );
        expect(s.selectedDepartmentId, _kDeptId);
        expect(s.departmentText, _kDeptName);
      },
    );

    test('β) κατοχύρωση «5067» → επιλέγεται ο 5067 κανονικά', () async {
      final container = await _containerWithPrefixCodes();
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      n.performEquipmentLookupByCode('5067');
      final s = container.read(callSmartEntityProvider);

      expect(s.selectedEquipment?.code, '5067');
      expect(s.isEquipmentAmbiguous, isFalse);
      expect(s.equipmentNoMatch, isFalse);
    });

    test(
      'γ) κατοχύρωση μερικού «50» → λίστα υποψηφίων και isEquipmentAmbiguous',
      () async {
        final container = await _containerWithPrefixCodes();
        addTearDown(container.dispose);
        final n = container.read(callSmartEntityProvider.notifier);

        n.performEquipmentLookupByCode('50');
        final s = container.read(callSmartEntityProvider);

        expect(s.isEquipmentAmbiguous, isTrue);
        expect(s.selectedEquipment, isNull);
        expect(s.equipmentCandidates.length, greaterThanOrEqualTo(2));
      },
    );

    test('δ) κατοχύρωση ανύπαρκτου κωδικού → equipmentNoMatch', () async {
      final container = await _containerWithPrefixCodes();
      addTearDown(container.dispose);
      final n = container.read(callSmartEntityProvider.notifier);

      n.performEquipmentLookupByCode('99999');
      final s = container.read(callSmartEntityProvider);

      expect(s.equipmentNoMatch, isTrue);
      expect(s.selectedEquipment, isNull);
      expect(s.isEquipmentAmbiguous, isFalse);
    });
  });
}
