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

    group('διάγνωση απόπειρας IP (VNC/RDP host)', () {
      final vnc = _tool(ToolRole.vnc);
      final rdpHost = _tool(ToolRole.rdp, id: 2);

      String? validateVnc(String value) => RemoteParamValidator.validate(
            tool: vnc,
            value: value,
            acceptsFileParam: false,
          );

      String? validateRdpHost(String value) => RemoteParamValidator.validate(
            tool: rdpHost,
            value: value,
            acceptsFileParam: false,
          );

      test('3164, hostname και έγκυρη IPv4 παραμένουν έγκυρα', () {
        for (final value in ['3164', 'server1', '10.0.0.55']) {
          expect(validateVnc(value), isNull, reason: 'VNC: $value');
          expect(validateRdpHost(value), isNull, reason: 'RDP: $value');
        }
      });

      test('κενό μέσα → «Η διεύθυνση περιέχει κενό — αφαιρέστε το.»', () {
        const msg = 'Η διεύθυνση περιέχει κενό — αφαιρέστε το.';
        expect(validateVnc('10 10.25.12'), msg);
        expect(validateRdpHost('10 10.25.12'), msg);
      });

      test('διπλή τελεία → «Διπλή ή τελική τελεία στη διεύθυνση.»', () {
        const msg = 'Διπλή ή τελική τελεία στη διεύθυνση.';
        expect(validateVnc('10..10.25.12'), msg);
        expect(validateRdpHost('10..10.25.12'), msg);
      });

      test('τελική τελεία → «Διπλή ή τελική τελεία στη διεύθυνση.»', () {
        const msg = 'Διπλή ή τελική τελεία στη διεύθυνση.';
        expect(validateVnc('10.10.25.'), msg);
        expect(validateRdpHost('10.10.25.'), msg);
      });

      test('ελληνικό Ο → «Περιέχει το γράμμα "Ο" αντί για τον αριθμό 0.»', () {
        const msg = 'Περιέχει το γράμμα "Ο" αντί για τον αριθμό 0.';
        expect(validateVnc('10.10Ο.25.12'), msg);
        expect(validateRdpHost('10.10Ο.25.12'), msg);
      });

      test('μη αποδεκτός χαρακτήρας → «Μη αποδεκτός χαρακτήρας "x" στη διεύθυνση.»', () {
        const msg = 'Μη αποδεκτός χαρακτήρας "x" στη διεύθυνση.';
        expect(validateVnc('10.10.x.25'), msg);
        expect(validateRdpHost('10.10.x.25'), msg);
      });

      test('3 ομάδες → «Η IP θέλει 4 αριθμούς χωρισμένους με τελείες — βρέθηκαν 3.»', () {
        const msg =
            'Η IP θέλει 4 αριθμούς χωρισμένους με τελείες — βρέθηκαν 3.';
        expect(validateVnc('10.10.25'), msg);
        expect(validateRdpHost('10.10.25'), msg);
      });

      test('5 ομάδες → «Η IP θέλει 4 αριθμούς χωρισμένους με τελείες — βρέθηκαν 5.»', () {
        const msg =
            'Η IP θέλει 4 αριθμούς χωρισμένους με τελείες — βρέθηκαν 5.';
        expect(validateVnc('10.10.25.12.5'), msg);
        expect(validateRdpHost('10.10.25.12.5'), msg);
      });

      test('256 → «Το 256 ξεπερνά το όριο 255 κάθε τμήματος της IP.»', () {
        const msg = 'Το 256 ξεπερνά το όριο 255 κάθε τμήματος της IP.';
        expect(validateVnc('256.1.1.1'), msg);
        expect(validateRdpHost('256.1.1.1'), msg);
      });
    });
  });
}
