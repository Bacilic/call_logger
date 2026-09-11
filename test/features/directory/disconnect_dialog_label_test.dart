// Ετικέτα υπαλλήλου στον διάλογο αποδέσμευσης (personalPhone / personalEquipment).
//
//   flutter test test/features/directory/disconnect_dialog_label_test.dart

import 'package:call_logger/features/directory/models/department_kind.dart';
import 'package:call_logger/features/directory/screens/widgets/shared_asset_disconnect_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const user = 'Χριστίνα Παναγοπούλου';
  const dept = 'Προμήθειες';

  group('disconnectDialogContent · personalPhone', () {
    test('(α) όνομα + τμήμα σε μία παρένθεση, χωρίς «χρήστη» / «τμήμα «', () {
      final text = disconnectDialogContent(
        isPhone: true,
        value: '2896',
        mode: SharedAssetDisconnectMode.personalPhone,
        personalPhoneUserDisplayName: user,
        sourceDepartmentName: dept,
      );
      expect(
        text,
        contains('από τον υπάλληλο «Χριστίνα Παναγοπούλου (Προμήθειες)»'),
      );
      expect(text, isNot(contains('χρήστη')));
      expect(text, isNot(contains('τμήμα «')));
    });

    test('(γ) χωρίς τμήμα → μόνο όνομα', () {
      final text = disconnectDialogContent(
        isPhone: true,
        value: '2896',
        mode: SharedAssetDisconnectMode.personalPhone,
        personalPhoneUserDisplayName: user,
        sourceDepartmentName: null,
      );
      expect(text, contains('από τον υπάλληλο «Χριστίνα Παναγοπούλου»'));
      expect(text, isNot(contains('(')));
      expect(text, isNot(contains('χρήστη')));
    });
  });

  group('disconnectDialogContent · personalEquipment', () {
    test('(β) όνομα + τμήμα σε μία παρένθεση, χωρίς «χρήστη» / «τμήμα «', () {
      final text = disconnectDialogContent(
        isPhone: false,
        value: '3874',
        mode: SharedAssetDisconnectMode.personalEquipment,
        personalPhoneUserDisplayName: user,
        sourceDepartmentName: dept,
      );
      expect(
        text,
        contains('από τον υπάλληλο «Χριστίνα Παναγοπούλου (Προμήθειες)»'),
      );
      expect(text, isNot(contains('χρήστη')));
      expect(text, isNot(contains('τμήμα «')));
    });

    test('(γ) χωρίς τμήμα → μόνο όνομα', () {
      final text = disconnectDialogContent(
        isPhone: false,
        value: '3874',
        mode: SharedAssetDisconnectMode.personalEquipment,
        personalPhoneUserDisplayName: user,
        sourceDepartmentName: '  ',
      );
      expect(text, contains('από τον υπάλληλο «Χριστίνα Παναγοπούλου»'));
      expect(text, isNot(contains('(Προμήθειες)')));
      expect(text, isNot(contains('χρήστη')));
    });
  });

  group('το Είδος της καρτέλας φτάνει στον διάλογο', () {
    test('η αποδέσμευση ονομάζει την εταιρεία, όχι «το τμήμα»', () {
      final text = disconnectDialogContent(
        isPhone: true,
        value: '2534',
        mode: SharedAssetDisconnectMode.sharedAsset,
        sourceDepartmentName: 'DataMed',
        sourceDepartmentKind: DepartmentKind.company,
      );

      expect(text, contains('από την εταιρεία «DataMed»'));
      expect(text, isNot(contains('από το τμήμα')));
    });

    test('χωρίς Είδος, το κείμενο μένει όπως ήταν', () {
      final text = disconnectDialogContent(
        isPhone: true,
        value: '2534',
        mode: SharedAssetDisconnectMode.sharedAsset,
        sourceDepartmentName: 'Γραμματεία',
      );

      expect(text, contains('από το τμήμα «Γραμματεία»'));
    });
  });
}
