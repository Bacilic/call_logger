// Καμία ροή δεν δίνει εξοπλισμό σε εταιρεία.
//
// Σενάριο πεδίου 05/09/2026: ο Δαμωράκης από την DataMed τηλεφωνεί, γράφεται ο
// κωδικός 5698 που δεν υπάρχει στον κατάλογο, και η «Προσθήκη» της οθόνης
// κλήσεων θα τον δημιουργούσε με κάτοχο τμήμα την DataMed.
//
// Το πεδίο εξοπλισμού ΠΡΕΠΕΙ να συνεχίζει να δουλεύει — η εταιρεία τηλεφωνεί
// ακριβώς για δικά μας μηχανήματα — αλλά καμία συσχέτιση δεν προσφέρεται.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/calls/company_never_owns_equipment_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/directory/models/department_kind.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

const int _kCompanyId = 70;
const int _kHospitalId = 49;

UserModel _damorakis() => UserModel(
  id: 1,
  firstName: 'Αντώνης',
  lastName: 'Δαμωράκης',
  departmentId: _kCompanyId,
  departmentName: 'DataMed',
);

UserModel _hospitalUser() => UserModel(
  id: 2,
  firstName: 'Εύα',
  lastName: 'Κάρκουλα',
  departmentId: _kHospitalId,
  departmentName: 'Αιματολογικό',
);

LookupService _lookup() {
  final service = LookupService.forTest();
  service.injectInMemoryCatalogForTests(
    users: [_damorakis(), _hospitalUser()],
    equipment: const [],
    departmentRows: [
      DepartmentModel(
        id: _kCompanyId,
        name: 'DataMed',
        kind: DepartmentKind.company,
      ),
      DepartmentModel(id: _kHospitalId, name: 'Αιματολογικό'),
    ],
  );
  return service;
}

void main() {
  group('Το τμήμα δέχεται εξοπλισμό;', () {
    test('εταιρεία: όχι', () {
      final state = SmartEntitySelectorState(
        selectedDepartmentId: _kCompanyId,
        departmentText: 'DataMed',
      );

      expect(state.departmentAcceptsEquipment(_lookup()), isFalse);
    });

    test('τμήμα νοσοκομείου: ναι', () {
      final state = SmartEntitySelectorState(
        selectedDepartmentId: _kHospitalId,
        departmentText: 'Αιματολογικό',
      );

      expect(state.departmentAcceptsEquipment(_lookup()), isTrue);
    });

    test('το τμήμα του καλούντα μετράει όταν το πεδίο είναι κενό', () {
      final state = SmartEntitySelectorState(selectedCaller: _damorakis());

      expect(
        state.departmentAcceptsEquipment(_lookup()),
        isFalse,
        reason:
            'ο Δαμωράκης ανήκει στην DataMed ακόμη κι αν το πεδίο τμήματος '
            'δεν έχει συμπληρωθεί',
      );
    });

    test('χωρίς κατάλογο δεν εμποδίζουμε τίποτα', () {
      final state = SmartEntitySelectorState(
        selectedDepartmentId: _kCompanyId,
        departmentText: 'DataMed',
      );

      expect(state.departmentAcceptsEquipment(null), isTrue);
    });
  });

  group('Η «Προσθήκη» δεν προσφέρει εξοπλισμό σε εταιρεία', () {
    test('υπάρχων καλών εταιρείας με άγνωστο κωδικό → καμία συσχέτιση', () {
      final state = SmartEntitySelectorState(
        selectedCaller: _damorakis(),
        selectedDepartmentId: _kCompanyId,
        departmentText: 'DataMed',
        equipmentText: '5698',
      );

      expect(
        state.needsExistingCallerAssociation(_lookup()),
        isFalse,
        reason:
            'το 5698 θα δημιουργούνταν με κάτοχο την DataMed — ο κατάλογος '
            'εξοπλισμού είναι του νοσοκομείου',
      );
      expect(state.needsAssociation(_lookup()), isFalse);
    });

    test('ίδιο σενάριο σε τμήμα νοσοκομείου → η συσχέτιση προσφέρεται', () {
      final state = SmartEntitySelectorState(
        selectedCaller: _hospitalUser(),
        selectedDepartmentId: _kHospitalId,
        departmentText: 'Αιματολογικό',
        equipmentText: '5698',
      );

      expect(state.needsExistingCallerAssociation(_lookup()), isTrue);
    });

    test('το τηλέφωνο της εταιρείας παραμένει θεμιτό', () {
      final state = SmartEntitySelectorState(
        selectedCaller: _damorakis(),
        selectedDepartmentId: _kCompanyId,
        departmentText: 'DataMed',
        selectedPhone: '2108056700',
      );

      expect(
        state.needsExistingCallerAssociation(_lookup()),
        isTrue,
        reason: 'μια εταιρεία έχει κέντρο και οι άνθρωποί της κινητά',
      );
    });

    test('ορφανή γρήγορη καταχώρηση σε εταιρεία δεν γράφει εξοπλισμό', () {
      final state = SmartEntitySelectorState(
        selectedDepartmentId: _kCompanyId,
        departmentText: 'DataMed',
        equipmentText: '5698',
      );

      expect(
        state.needsOrphanDepartmentQuickAddResolved(_lookup()),
        isFalse,
        reason:
            'αυτή η ροή γράφει equipment.department_id στο τμήμα της φόρμας',
      );
    });

    test('το μήνυμα του κουμπιού δεν υπόσχεται εξοπλισμό σε εταιρεία', () {
      final state = SmartEntitySelectorState(
        selectedDepartmentId: _kCompanyId,
        departmentText: 'DataMed',
        callerDisplayText: 'Γιώργος Μπάρτζης',
        selectedPhone: '6971234567',
        equipmentText: '5698',
      );

      final tooltip = state.associationTooltip(_lookup());
      expect(tooltip, isNotNull);
      expect(
        tooltip,
        isNot(contains('5698')),
        reason: 'ό,τι δεν πρόκειται να γραφτεί δεν ανακοινώνεται',
      );
    });
  });

  // Η κρίση «τι θα γραφτεί» ελέγχεται παραπάνω σε καθαρή λογική. Εδώ τρέχει η
  // ΕΚΤΕΛΕΣΗ πάνω σε πραγματική βάση: ό,τι υπόσχεται η οθόνη είναι ό,τι γράφει
  // η ροή — αλλιώς οι δύο αποκλίνουν σιωπηλά.
  group('Η γρήγορη καταχώρηση ορφανών εκτελεί ό,τι κρίθηκε', () {
    late Database db;

    registerCallLoggerIsolatedDatabaseHooks();

    setUp(() async {
      await seedIsolatedTestDatabase();
      db = await DatabaseHelper.instance.database;
    });

    Future<int> insertDepartment(String name, DepartmentKind kind) {
      return db.insert('departments', {
        'name': name,
        'name_key': SearchTextNormalizer.normalizeForSearch(name),
        'kind': kind.dbValue,
        'is_deleted': 0,
      });
    }

    Future<int?> departmentIdOfEquipment(String code) async {
      final rows = await db.query(
        'equipment',
        columns: ['department_id'],
        where: 'code_equipment = ?',
        whereArgs: [code],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['department_id'] as int?;
    }

    Future<ProviderContainer> containerReady() async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      await container.read(lookupServiceProvider.future);
      return container;
    }

    test(
      'τηλέφωνο εταιρείας μαζί με μηχάνημα: γράφεται μόνο το τηλέφωνο',
      () async {
        final companyId = await insertDepartment(
          'DataMed',
          DepartmentKind.company,
        );
        final container = await containerReady();
        addTearDown(container.dispose);

        const phone = '2108056700';
        const equipmentCode = '5698';

        final notifier = container.read(callSmartEntityProvider.notifier);
        notifier.updateDepartmentText('DataMed');
        notifier.checkContent(departmentText: 'DataMed');
        notifier.updatePhone(phone);
        notifier.checkContent(phoneText: phone);
        notifier.checkContent(equipmentText: equipmentCode);

        final result = await notifier.quickAddOrphanToDepartment(
          forceSharedOnConflict: true,
        );

        expect(result, isNotNull);
        expect(
          await departmentIdOfEquipment(equipmentCode),
          isNot(companyId),
          reason:
              'το τηλέφωνο δικαιολογεί τη ροή — το μηχάνημα δεν ακολουθεί '
              'στην εταιρεία',
        );
        expect(
          result!.successMessage,
          isNot(contains('εξοπλισμός')),
          reason: 'το μήνυμα δεν ανακοινώνει καταχώρηση που δεν έγινε',
        );
      },
    );

    test('σε τμήμα νοσοκομείου γράφονται και τα δύο', () async {
      final hospitalId = await insertDepartment(
        'Αιματολογικό',
        DepartmentKind.hospital,
      );
      final container = await containerReady();
      addTearDown(container.dispose);

      const phone = '2534';
      const equipmentCode = '5067';

      final notifier = container.read(callSmartEntityProvider.notifier);
      notifier.updateDepartmentText('Αιματολογικό');
      notifier.checkContent(departmentText: 'Αιματολογικό');
      notifier.updatePhone(phone);
      notifier.checkContent(phoneText: phone);
      notifier.checkContent(equipmentText: equipmentCode);

      final result = await notifier.quickAddOrphanToDepartment(
        forceSharedOnConflict: true,
      );

      expect(result, isNotNull);
      expect(await departmentIdOfEquipment(equipmentCode), hospitalId);
      expect(result!.successMessage, contains('εξοπλισμός'));
    });
  });
}
