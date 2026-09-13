// Η κρίση και τα κείμενα της γρήγορης καταχώρησης ορφανών, χωρίς βάση.
//
// Ό,τι δεν πρόκειται να γραφτεί δεν ζητά έγκριση και δεν ανακοινώνεται. Η ίδια
// υπόσχεση κρατά και το μήνυμα επιτυχίας.
//
//   flutter test test/features/calls/orphan_quick_add_plan_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/provider/orphan_quick_add_plan.dart';
import 'package:flutter_test/flutter_test.dart';

const int _kHospitalId = 49;
const int _kOtherDepartmentId = 12;

OrphanQuickAddPlan _plan({
  int? departmentId = _kHospitalId,
  String departmentText = 'Αιματολογικό',
  String? phone,
  String? equipmentCode,
  PhoneUsageCheck? phoneUsage,
  EquipmentUsageCheck? equipmentUsage,
  bool phoneNeedsShared = false,
  bool equipmentNeedsShared = false,
  bool departmentExistedBefore = true,
  bool phoneExistedBefore = true,
  bool equipmentExistedBefore = true,
}) {
  return OrphanQuickAddPlan(
    departmentText: departmentText,
    departmentId: departmentId,
    phone: phone,
    equipmentCode: equipmentCode,
    phoneUsage: phoneUsage,
    equipmentUsage: equipmentUsage,
    phoneNeedsShared: phoneNeedsShared,
    equipmentNeedsShared: equipmentNeedsShared,
    departmentExistedBefore: departmentExistedBefore,
    phoneExistedBefore: phoneExistedBefore,
    equipmentExistedBefore: equipmentExistedBefore,
  );
}

void main() {
  group('Η έγκριση ζητείται μόνο για ό,τι θα γραφτεί', () {
    test('χωρίς τίποτα προς εγγραφή δεν ζητιέται έγκριση', () {
      final plan = _plan(
        phone: '2534',
        phoneUsage: const PhoneUsageCheck(
          phone: '2534',
          userNames: ['Βαρβάρα Ψαρρά'],
        ),
      );

      expect(plan.hasConflict, isFalse);
      expect(orphanQuickAddConflictMessage(plan), isNull);
    });

    test('τηλέφωνο με κατόχους ζητά έγκριση και ονομάζει τους κατόχους', () {
      final plan = _plan(
        phone: '2534',
        phoneNeedsShared: true,
        phoneUsage: const PhoneUsageCheck(
          phone: '2534',
          userNames: ['Βαρβάρα Ψαρρά'],
        ),
      );

      final message = orphanQuickAddConflictMessage(plan);
      expect(message, isNotNull);
      expect(message, contains('Βαρβάρα Ψαρρά'));
      expect(message, contains('Αιματολογικό'));
    });

    test('το μηχάνημα που δεν γράφεται μένει έξω από το μήνυμα', () {
      final plan = _plan(
        phone: '2534',
        equipmentCode: '5067',
        phoneNeedsShared: true,
        phoneUsage: const PhoneUsageCheck(
          phone: '2534',
          userNames: ['Βαρβάρα Ψαρρά'],
        ),
        equipmentUsage: const EquipmentUsageCheck(
          code: '5067',
          userNames: ['Αντώνης Δαμωράκης'],
        ),
      );

      final message = orphanQuickAddConflictMessage(plan);
      expect(message, isNotNull);
      expect(
        message,
        isNot(contains('5067')),
        reason: 'δεν ζητάμε έγκριση για κάτι που η κρίση άφησε έξω',
      );
    });

    test('ίδιο τμήμα χωρίς κατόχους δεν είναι σύγκρουση', () {
      final plan = _plan(
        phone: '2534',
        phoneNeedsShared: true,
        phoneUsage: const PhoneUsageCheck(
          phone: '2534',
          userNames: [],
          departmentId: _kHospitalId,
          departmentName: 'Αιματολογικό',
        ),
      );

      expect(plan.hasConflict, isFalse);
    });

    test('άλλο τμήμα είναι σύγκρουση και το μήνυμα το λέει', () {
      final plan = _plan(
        equipmentCode: '5067',
        equipmentNeedsShared: true,
        equipmentUsage: const EquipmentUsageCheck(
          code: '5067',
          userNames: [],
          departmentId: _kOtherDepartmentId,
          departmentName: 'Μικροβιολογικό',
        ),
      );

      expect(plan.hasConflict, isTrue);
      expect(orphanQuickAddConflictMessage(plan), contains('Μικροβιολογικό'));
    });
  });

  group('Το μήνυμα ανακοινώνει ό,τι γράφτηκε', () {
    test('μόνο τηλέφωνο', () {
      expect(
        orphanQuickAddSuccessMessage(
          phoneWritten: true,
          equipmentWritten: false,
          departmentName: 'Αιματολογικό',
        ),
        'Καταχωρήθηκε τηλέφωνο ως κοινόχρηστο στο τμήμα Αιματολογικό.',
      );
    });

    test('τηλέφωνο και εξοπλισμός', () {
      expect(
        orphanQuickAddSuccessMessage(
          phoneWritten: true,
          equipmentWritten: true,
          departmentName: 'Αιματολογικό',
        ),
        'Καταχωρήθηκε τηλέφωνο και εξοπλισμός ως κοινόχρηστο '
        'στο τμήμα Αιματολογικό.',
      );
    });

    test('τίποτα', () {
      expect(
        orphanQuickAddSuccessMessage(
          phoneWritten: false,
          equipmentWritten: false,
          departmentName: 'Αιματολογικό',
        ),
        'Δεν υπήρχε στοιχείο προς καταχώρηση.',
      );
    });
  });

  group('Πότε γεννιέται εκκρεμότητα νέας οντότητας', () {
    test('όλα γνωστά → καμία', () {
      expect(_plan(phone: '2534', equipmentCode: '5067').hasNewEntity, isFalse);
    });

    test('άγνωστο μηχάνημα → ναι, ακόμη κι αν δεν γράφτηκε', () {
      final plan = _plan(
        equipmentCode: '5067',
        equipmentExistedBefore: false,
        equipmentNeedsShared: false,
      );

      expect(
        plan.hasNewEntity,
        isTrue,
        reason: 'ο άγνωστος κωδικός αξίζει υπενθύμιση, όχι χρέωση',
      );
      expect(plan.writesAnything, isFalse);
    });

    test('νέο τμήμα → ναι', () {
      expect(_plan(departmentExistedBefore: false).hasNewEntity, isTrue);
    });
  });
}
