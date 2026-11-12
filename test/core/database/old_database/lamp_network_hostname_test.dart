import 'package:call_logger/core/database/old_database/lamp_network_hostname.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lampNetworkHostnameCode — εξαγωγή κωδικού από hostname', () {
    test('ονόματα τύπου εξοπλισμού δίνουν τον κωδικό', () {
      expect(lampNetworkHostnameCode('PC3846'), 3846);
      expect(lampNetworkHostnameCode('pr1802'), 1802);
      expect(lampNetworkHostnameCode('PR0018'), 18);
      expect(lampNetworkHostnameCode('HP03'), 3);
      expect(lampNetworkHostnameCode('LAPTOP12'), 12);
      expect(lampNetworkHostnameCode('SW2678'), 2678);
      expect(lampNetworkHostnameCode('PRINT7'), 7);
    });

    test('ονόματα χρήστη, περιγραφικά και κενά δεν δίνουν κωδικό', () {
      expect(lampNetworkHostnameCode('user29'), isNull);
      expect(lampNetworkHostnameCode('iuser71'), isNull);
      expect(lampNetworkHostnameCode('LOGISTIRIO'), isNull);
      expect(lampNetworkHostnameCode(''), isNull);
      expect(lampNetworkHostnameCode('PC'), isNull);
      expect(lampNetworkHostnameCode('PC12A'), isNull);
    });
  });
}
