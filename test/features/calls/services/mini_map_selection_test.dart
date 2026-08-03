// Προτεραιότητα πηγών του μικρού χάρτη: Τμήμα → Εξοπλισμός → Τηλέφωνο → Καλών.
//
//   flutter test test/features/calls/services/mini_map_selection_test.dart

import 'package:call_logger/features/calls/services/mini_map_data_loader.dart';
import 'package:flutter_test/flutter_test.dart';

MiniMapSelection _select({int? header, int? equipment, int? phone, int? user}) {
  return resolveMiniMapSelection(
    MiniMapCandidateDepartments(
      headerDepartmentId: header,
      equipmentDepartmentId: equipment,
      phoneDepartmentId: phone,
      userDepartmentId: user,
    ),
  );
}

void main() {
  group('προτεραιότητα όψης', () {
    test('το τμήμα της κεφαλίδας κερδίζει όλες τις άλλες πηγές', () {
      final s = _select(header: 10, equipment: 20, phone: 30, user: 40);
      expect(s.mode, MiniMapMode.department);
      expect(s.selectedDepartmentId, 10);
    });

    test('χωρίς τμήμα κεφαλίδας κερδίζει ο εξοπλισμός', () {
      final s = _select(equipment: 20, phone: 30, user: 40);
      expect(s.mode, MiniMapMode.equipment);
      expect(s.selectedDepartmentId, 20);
    });

    test('χωρίς τμήμα και εξοπλισμό κερδίζει το τηλέφωνο', () {
      final s = _select(phone: 30, user: 40);
      expect(s.mode, MiniMapMode.phone);
      expect(s.selectedDepartmentId, 30);
    });

    test('μόνο ο καλών: η όψη είναι του υπαλλήλου', () {
      final s = _select(user: 40);
      expect(s.mode, MiniMapMode.user);
      expect(s.selectedDepartmentId, 40);
    });

    test('άδεια φόρμα: όψη εξοπλισμού (προεπιλογή) χωρίς επιλεγμένο τμήμα', () {
      final s = _select();
      expect(s.mode, MiniMapMode.equipment);
      expect(s.selectedDepartmentId, isNull);
    });
  });

  group('συνέπεια όψης και επιλεγμένου τμήματος', () {
    test(
      'σε ΚΑΘΕ συνδυασμό πηγών, το επιλεγμένο τμήμα είναι το τμήμα της όψης',
      () {
        // 16 συνδυασμοί: κάθε πηγή υπάρχει ή λείπει. Η όψη και το τμήμα δεν
        // επιτρέπεται να αποκλίνουν — μία σειρά προτεραιότητας, όχι δύο.
        const ids = {
          MiniMapMode.department: 10,
          MiniMapMode.equipment: 20,
          MiniMapMode.phone: 30,
          MiniMapMode.user: 40,
        };
        for (var mask = 0; mask < 16; mask++) {
          final header = (mask & 1) != 0 ? ids[MiniMapMode.department] : null;
          final equipment = (mask & 2) != 0 ? ids[MiniMapMode.equipment] : null;
          final phone = (mask & 4) != 0 ? ids[MiniMapMode.phone] : null;
          final user = (mask & 8) != 0 ? ids[MiniMapMode.user] : null;

          final s = _select(
            header: header,
            equipment: equipment,
            phone: phone,
            user: user,
          );
          final departmentOfMode = switch (s.mode) {
            MiniMapMode.department => header,
            MiniMapMode.equipment => equipment,
            MiniMapMode.phone => phone,
            MiniMapMode.user => user,
          };

          expect(
            s.selectedDepartmentId,
            departmentOfMode,
            reason:
                'Συνδυασμός header=$header equipment=$equipment phone=$phone '
                'user=$user: η όψη ${s.mode} δείχνει άλλο τμήμα από το δικό της.',
          );
        }
      },
    );

    test('η όψη είναι πάντα η πρώτη πηγή που έχει τμήμα', () {
      expect(_select(header: 10, user: 40).mode, MiniMapMode.department);
      expect(_select(equipment: 20, user: 40).mode, MiniMapMode.equipment);
      expect(_select(phone: 30, user: 40).mode, MiniMapMode.phone);
      expect(_select(user: 40).mode, MiniMapMode.user);
    });
  });

  group('εναλλαγή εξοπλισμού/τηλεφώνου', () {
    test(
      'ενεργή όταν εξοπλισμός και τηλέφωνο δείχνουν σε ΔΙΑΦΟΡΕΤΙΚΑ τμήματα',
      () {
        expect(
          _select(equipment: 20, phone: 30).hasPhoneEquipmentToggle,
          isTrue,
        );
      },
    );

    test('ανενεργή όταν δείχνουν στο ΙΔΙΟ τμήμα', () {
      expect(
        _select(equipment: 20, phone: 20).hasPhoneEquipmentToggle,
        isFalse,
      );
    });

    test('ανενεργή όταν λείπει η μία από τις δύο πηγές', () {
      expect(_select(equipment: 20).hasPhoneEquipmentToggle, isFalse);
      expect(_select(phone: 30).hasPhoneEquipmentToggle, isFalse);
    });

    test(
      'ενεργή ακόμη και με τμήμα κεφαλίδας — η επιλογή μένει του χρήστη',
      () {
        final s = _select(header: 10, equipment: 20, phone: 30);
        expect(s.mode, MiniMapMode.department);
        expect(s.hasPhoneEquipmentToggle, isTrue);
      },
    );
  });
}
