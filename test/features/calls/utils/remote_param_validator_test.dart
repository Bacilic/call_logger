import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/features/calls/utils/remote_param_validator.dart';
import 'package:flutter_test/flutter_test.dart';

RemoteTool _tool(ToolRole role, {int id = 1}) => RemoteTool(
      id: id,
      name: 'Test $role',
      role: role,
      executablePath: r'C:\test.exe',
      sortOrder: 1,
      isActive: true,
    );

void main() {
  group('RemoteParamValidator', () {
  group('VNC (ToolRole.vnc)', () {
      final vnc = _tool(ToolRole.vnc);

      test('10.0.0.55 → null', () {
        expect(
          RemoteParamValidator.validate(
            tool: vnc,
            value: '10.0.0.55',
            acceptsFileParam: false,
          ),
          isNull,
        );
      });

      test('PC1234 → null (κωδικός εξοπλισμού)', () {
        expect(
          RemoteParamValidator.validate(
            tool: vnc,
            value: 'PC1234',
            acceptsFileParam: false,
          ),
          isNull,
        );
      });

      test('server1 → null (hostname)', () {
        expect(
          RemoteParamValidator.validate(
            tool: vnc,
            value: 'server1',
            acceptsFileParam: false,
          ),
          isNull,
        );
      });

      test('άκυρο κενό μέσα → μήνυμα σφάλματος', () {
        expect(
          RemoteParamValidator.validate(
            tool: vnc,
            value: 'άκυρο κενό μέσα',
            acceptsFileParam: false,
          ),
          isNotNull,
        );
      });

      test('κενή τιμή → null', () {
        expect(
          RemoteParamValidator.validate(
            tool: vnc,
            value: '',
            acceptsFileParam: false,
          ),
          isNull,
        );
      });
    });

    group('RDP host (ToolRole.rdp, acceptsFileParam=false)', () {
      final rdpHost = _tool(ToolRole.rdp);

      test('IP έγκυρο → null', () {
        expect(
          RemoteParamValidator.validate(
            tool: rdpHost,
            value: '192.168.1.10',
            acceptsFileParam: false,
          ),
          isNull,
        );
      });

      test('hostname έγκυρο → null', () {
        expect(
          RemoteParamValidator.validate(
            tool: rdpHost,
            value: 'rdp-server',
            acceptsFileParam: false,
          ),
          isNull,
        );
      });

      test('σκουπίδι → σφάλμα', () {
        expect(
          RemoteParamValidator.validate(
            tool: rdpHost,
            value: '!!!σκουπίδι!!!',
            acceptsFileParam: false,
          ),
          isNotNull,
        );
      });

      test('κενή τιμή → null', () {
        expect(
          RemoteParamValidator.validate(
            tool: rdpHost,
            value: '   ',
            acceptsFileParam: false,
          ),
          isNull,
        );
      });
    });

    group('RDP αρχείο (ToolRole.rdp, acceptsFileParam=true)', () {
      final rdpFile = _tool(ToolRole.rdp);

      test(r'C:\x\pc.rdp → null', () {
        expect(
          RemoteParamValidator.validate(
            tool: rdpFile,
            value: r'C:\x\pc.rdp',
            acceptsFileParam: true,
          ),
          isNull,
        );
      });

      test(r'C:\x\pc.RDP → null (case-insensitive)', () {
        expect(
          RemoteParamValidator.validate(
            tool: rdpFile,
            value: r'C:\x\pc.RDP',
            acceptsFileParam: true,
          ),
          isNull,
        );
      });

      test(r'C:\x\pc.txt → σφάλμα', () {
        expect(
          RemoteParamValidator.validate(
            tool: rdpFile,
            value: r'C:\x\pc.txt',
            acceptsFileParam: true,
          ),
          isNotNull,
        );
      });

      test('κενή τιμή → null', () {
        expect(
          RemoteParamValidator.validate(
            tool: rdpFile,
            value: '',
            acceptsFileParam: true,
          ),
          isNull,
        );
      });
    });

    group('AnyDesk (ToolRole.anydesk)', () {
      final anydesk = _tool(ToolRole.anydesk);

      test('123456789 → null', () {
        expect(
          RemoteParamValidator.validate(
            tool: anydesk,
            value: '123456789',
            acceptsFileParam: false,
          ),
          isNull,
        );
      });

      test('12 → σφάλμα', () {
        expect(
          RemoteParamValidator.validate(
            tool: anydesk,
            value: '12',
            acceptsFileParam: false,
          ),
          isNotNull,
        );
      });

      test('name@ns → null', () {
        expect(
          RemoteParamValidator.validate(
            tool: anydesk,
            value: 'name@ns',
            acceptsFileParam: false,
          ),
          isNull,
        );
      });

      test('κενή τιμή → null', () {
        expect(
          RemoteParamValidator.validate(
            tool: anydesk,
            value: '',
            acceptsFileParam: false,
          ),
          isNull,
        );
      });
    });

    group('generic (ToolRole.generic)', () {
      final generic = _tool(ToolRole.generic);

      test('οποιαδήποτε τιμή → null', () {
        expect(
          RemoteParamValidator.validate(
            tool: generic,
            value: 'οτιδήποτε',
            acceptsFileParam: false,
          ),
          isNull,
        );
      });

      test('κενή τιμή → null', () {
        expect(
          RemoteParamValidator.validate(
            tool: generic,
            value: '',
            acceptsFileParam: false,
          ),
          isNull,
        );
      });
    });
  });
}
