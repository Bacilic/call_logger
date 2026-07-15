// Unit test: κείμενα βοήθειας παραμέτρων απομακρυσμένης σύνδεσης.
//
//   flutter test test/features/directory/screens/widgets/remote_param_help_text_test.dart

import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/features/directory/screens/widgets/remote_param_help_text.dart';
import 'package:flutter_test/flutter_test.dart';

RemoteTool _tool({
  required ToolRole role,
  String name = 'Δοκιμαστικό',
}) {
  return RemoteTool(
    id: 1,
    name: name,
    role: role,
    executablePath: r'C:\tool.exe',
    sortOrder: 1,
    isActive: true,
  );
}

void main() {
  group('RemoteParamHelpText.forTool', () {
    test('AnyDesk περιέχει μορφολογία 9-10 ψηφία', () {
      final text = RemoteParamHelpText.forTool(
        tool: _tool(role: ToolRole.anydesk, name: 'AnyDesk'),
        acceptsFileParam: false,
      );
      expect(text, contains('9-10 ψηφία'));
      expect(text, contains('AnyDesk'));
    });

    test('VNC αναφέρει προεπιλεγμένο στόχο και όνομα εργαλείου', () {
      final text = RemoteParamHelpText.forTool(
        tool: _tool(role: ToolRole.vnc, name: 'UltraVNC'),
        acceptsFileParam: false,
      );
      expect(text, contains('προεπιλεγμένος στόχος'));
      expect(text, contains('UltraVNC'));
    });

    test('RDP με διεύθυνση (χωρίς αρχείο) αναφέρει απενεργοποίηση', () {
      final text = RemoteParamHelpText.forTool(
        tool: _tool(role: ToolRole.rdp, name: 'mstsc'),
        acceptsFileParam: false,
      );
      expect(text, contains('απενεργοποίηση'));
      expect(text, isNot(contains('.rdp')));
      expect(text, contains('mstsc'));
    });

    test('RDP με αρχείο αναφέρει .rdp', () {
      final text = RemoteParamHelpText.forTool(
        tool: _tool(role: ToolRole.rdp, name: 'RDP File'),
        acceptsFileParam: true,
      );
      expect(text, contains('.rdp'));
      expect(text, contains('RDP File'));
    });

    test('γενικό εργαλείο αναφέρει στόχο σύνδεσης', () {
      final text = RemoteParamHelpText.forTool(
        tool: _tool(role: ToolRole.generic, name: 'Custom'),
        acceptsFileParam: false,
      );
      expect(text, contains('στόχος σύνδεσης'));
      expect(text, contains('Custom'));
    });

    test('χωρίς εργαλείο (null) δίνει γενικό κείμενο χωρίς όνομα', () {
      final text = RemoteParamHelpText.forTool(
        tool: null,
        acceptsFileParam: false,
      );
      expect(text, contains('στόχος σύνδεσης'));
      expect(text, isNot(contains('«')));
    });
  });
}
