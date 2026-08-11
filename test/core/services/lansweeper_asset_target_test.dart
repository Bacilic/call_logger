import 'package:call_logger/core/services/lansweeper_asset_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lansweeperAssetTargetFor — αποθηκευμένη τιμή', () {
    test('κερδίζει πάντα έναντι του κωδικού', () {
      final target = lansweeperAssetTargetFor(
        storedAssetName: 'PRINTER-B2',
        equipmentCode: '3715',
      );
      expect(target, isNotNull);
      expect(target!.value, 'PRINTER-B2');
      expect(target.kind, LansweeperAssetTargetKind.assetName);
    });

    test('IP ταξινομείται ως IPAddress', () {
      final target = lansweeperAssetTargetFor(
        storedAssetName: '10.10.222.19',
        equipmentCode: '3715',
      );
      expect(target!.value, '10.10.222.19');
      expect(target.kind, LansweeperAssetTargetKind.ipAddress);
    });

    test('IP με κόμματα (ελληνικό numpad) κανονικοποιείται σε τελείες', () {
      final target = lansweeperAssetTargetFor(
        storedAssetName: '10,10,222,19',
        equipmentCode: null,
      );
      expect(target!.value, '10.10.222.19');
      expect(target.kind, LansweeperAssetTargetKind.ipAddress);
    });
  });

  group('lansweeperAssetTargetFor — κενή αποθηκευμένη τιμή (κοινός κανόνας VNC)', () {
    test('κωδικός 3-6 ψηφίων → PC + κωδικός', () {
      final target = lansweeperAssetTargetFor(
        storedAssetName: null,
        equipmentCode: '3715',
      );
      expect(target!.value, 'PC3715');
      expect(target.kind, LansweeperAssetTargetKind.assetName);
    });

    test('κωδικός που ξεκινά με γράμμα μένει ως έχει', () {
      final target = lansweeperAssetTargetFor(
        storedAssetName: '',
        equipmentCode: 'SRV-DC1',
      );
      expect(target!.value, 'SRV-DC1');
      expect(target.kind, LansweeperAssetTargetKind.assetName);
    });

    test('χωρίς τίποτα χρήσιμο → null (χωρίς σύνδεση, χωρίς σφάλμα)', () {
      expect(
        lansweeperAssetTargetFor(storedAssetName: null, equipmentCode: null),
        isNull,
      );
      expect(
        lansweeperAssetTargetFor(storedAssetName: '  ', equipmentCode: ''),
        isNull,
      );
      // Κωδικός εκτός κανόνα (π.χ. 2 ψηφία με σύμβολο) δεν παράγει στόχο.
      expect(
        lansweeperAssetTargetFor(storedAssetName: null, equipmentCode: '#12'),
        isNull,
      );
    });
  });
}
