import 'package:call_logger/core/models/remote_tool_arg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteToolArg.maskSecretValues', () {
    test('-password=pass99 → -password=***', () {
      expect(
        RemoteToolArg.maskSecretValues('-password=pass99'),
        '-password=***',
      );
    });

    test('/pwd:χ → /pwd:***', () {
      expect(RemoteToolArg.maskSecretValues('/pwd:χ'), '/pwd:***');
    });

    test('PASS=χ → PASS=***', () {
      expect(RemoteToolArg.maskSecretValues('PASS=χ'), 'PASS=***');
    });

    test('pin:1234 → pin:***', () {
      expect(RemoteToolArg.maskSecretValues('pin:1234'), 'pin:***');
    });

    test('τιμή χωρίς κωδικό μένει ίδια', () {
      const plain = '-host=PC{TARGET}';
      expect(RemoteToolArg.maskSecretValues(plain), plain);
    });

    test('{TARGET} μένει ίδιο', () {
      const target = '{TARGET}';
      expect(RemoteToolArg.maskSecretValues(target), target);
    });
  });
}
