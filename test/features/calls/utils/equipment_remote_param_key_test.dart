import 'package:call_logger/features/calls/utils/equipment_remote_param_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EquipmentRemoteParamKey', () {
    test('withExclusiveToolId + exclusiveToolIdFrom διατηρούν το id', () {
      const params = {'1': '10.0.0.1', '2': '123456789'};
      final withExclusive = EquipmentRemoteParamKey.withExclusiveToolId(params, 2);
      expect(
        EquipmentRemoteParamKey.exclusiveToolIdFrom(withExclusive),
        2,
      );
      expect(withExclusive[EquipmentRemoteParamKey.exclusiveToolKey], '2');
      expect(withExclusive['1'], '10.0.0.1');
    });

    test('withExclusiveToolId(params, null) αφαιρεί το κλειδί', () {
      final params = {
        '1': '10.0.0.1',
        EquipmentRemoteParamKey.exclusiveToolKey: '2',
      };
      final cleared = EquipmentRemoteParamKey.withExclusiveToolId(params, null);
      expect(cleared.containsKey(EquipmentRemoteParamKey.exclusiveToolKey), isFalse);
      expect(EquipmentRemoteParamKey.exclusiveToolIdFrom(cleared), isNull);
      expect(cleared['1'], '10.0.0.1');
    });

    test('isReservedKey: exclusive και stash true, αριθμητικά false', () {
      expect(
        EquipmentRemoteParamKey.isReservedKey(
          EquipmentRemoteParamKey.exclusiveToolKey,
        ),
        isTrue,
      );
      expect(
        EquipmentRemoteParamKey.isReservedKey(
          EquipmentRemoteParamKey.remoteParamStashKeyFor('3'),
        ),
        isTrue,
      );
      expect(EquipmentRemoteParamKey.isReservedKey('1'), isFalse);
      expect(EquipmentRemoteParamKey.isReservedKey('42'), isFalse);
    });
  });
}
