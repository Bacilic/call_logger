import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolRole.shortLabel', () {
    test('επιστρέφει σύντομες ετικέτες ανά ρόλο', () {
      expect(ToolRole.vnc.shortLabel, 'VNC');
      expect(ToolRole.rdp.shortLabel, 'RDP');
      expect(ToolRole.anydesk.shortLabel, 'AnyDesk');
      expect(ToolRole.generic.shortLabel, 'Γενικό');
    });
  });
}
