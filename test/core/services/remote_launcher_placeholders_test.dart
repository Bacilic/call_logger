import 'dart:convert';

import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/core/services/remote_launcher_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteLauncherService.replaceAllPlaceholders', () {
    test('σειρά: EQUIPMENT_CODE, TARGET, FILE', () {
      expect(
        RemoteLauncherService.replaceAllPlaceholders(
          '-h={EQUIPMENT_CODE}-{TARGET}-{FILE}',
          equipmentCode: '99',
          resolvedTarget: '192.168.0.1',
          filePath: r'C:\a.rdp',
        ),
        '-h=99-192.168.0.1-C:\\a.rdp',
      );
    });

    test('TARGET πέφτει σε equipmentCode όταν resolvedTarget κενό', () {
      expect(
        RemoteLauncherService.replaceAllPlaceholders(
          'x={TARGET}',
          equipmentCode: '42',
          resolvedTarget: '',
          filePath: null,
        ),
        'x=42',
      );
    });

    test('TARGET πέφτει σε equipmentCode όταν resolvedTarget null', () {
      expect(
        RemoteLauncherService.replaceAllPlaceholders(
          'x={TARGET}',
          equipmentCode: '7',
          resolvedTarget: null,
          filePath: null,
        ),
        'x=7',
      );
    });
  });

  group('RemoteTool arguments_json escaping', () {
    test('round-trip με εισαγωγικά και backslash στο value', () {
      const tricky = r'"/p:abc\xyz"';
      final tool = RemoteTool(
        id: 1,
        name: 't',
        role: ToolRole.vnc,
        executablePath: r'C:\x.exe',
        launchMode: 'direct_exec',
        sortOrder: 1,
        isActive: true,
        arguments: [
          RemoteToolArgument(value: tricky, description: 'd', isActive: true),
        ],
      );
      final map = tool.toMap();
      final raw = map['arguments_json'] as String?;
      expect(raw, isNotNull);
      expect(raw, contains(r'\"'));
      final decoded = jsonDecode(raw!) as List<dynamic>;
      expect((decoded.first as Map)['value'], tricky);
      final back = RemoteTool.fromMap(map);
      expect(back.arguments.first.value, tricky);
    });
  });

  group('RemoteLauncherService.testArgumentList', () {
    RemoteTool vncTool(List<RemoteToolArgument> arguments) => RemoteTool(
          id: 1,
          name: 'TightVNC',
          role: ToolRole.vnc,
          executablePath: r'C:\Program Files\TightVNC\tvnviewer.exe',
          launchMode: 'direct_exec',
          sortOrder: 1,
          isActive: true,
          arguments: arguments,
        );

    test('EQUIPMENT_CODE και TARGET από δοκιμαστικό host', () {
      final tool = vncTool(const [
        RemoteToolArgument(
          value: '-host=PC{EQUIPMENT_CODE}',
          isActive: true,
        ),
        RemoteToolArgument(
          value: '-password=pass99',
          isActive: true,
        ),
      ]);
      expect(
        RemoteLauncherService.testArgumentList(tool, '922'),
        ['-host=PC922', '-password=pass99'],
      );
      expect(
        RemoteLauncherService.testArgumentList(tool, 'pc922'),
        ['-host=PCpc922', '-password=pass99'],
      );
    });

    test('παραλείπει ανενεργά ορίσματα', () {
      final tool = vncTool(const [
        RemoteToolArgument(
          value: '-host=PC{EQUIPMENT_CODE}',
          isActive: true,
        ),
        RemoteToolArgument(
          value: '-password=secret',
          isActive: false,
        ),
      ]);
      expect(
        RemoteLauncherService.testArgumentList(tool, '922'),
        ['-host=PC922'],
      );
    });
  });

  group('RemoteLauncherService.formatTestCommandPreview', () {
    test('ενιαία γραμμή εντολής με ενεργά ορίσματα', () {
      final tool = RemoteTool(
        id: 2,
        name: 'TightVNC',
        role: ToolRole.vnc,
        executablePath: r'C:\Program Files\TightVNC\tvnviewer.exe',
        launchMode: 'direct_exec',
        sortOrder: 1,
        isActive: true,
        testTargetIp: 'pc922',
        arguments: const [
          RemoteToolArgument(
            value: '-host=PC{EQUIPMENT_CODE}',
            isActive: true,
          ),
          RemoteToolArgument(
            value: '-password=12345',
            isActive: true,
          ),
        ],
      );
      expect(
        RemoteLauncherService.formatTestCommandPreview(tool),
        'tvnviewer.exe -host=PCpc922 -password=12345',
      );
    });
  });

  group('RemoteTool.acceptsFileParam', () {
    test('αναγνωρίζει template_file με placeholder αρχείου ανεξάρτητα από πεζά/κεφαλαία', () {
      final t = RemoteTool(
        id: 10,
        name: 'RDP Template',
        role: ToolRole.rdp,
        executablePath: r'C:\Windows\System32\mstsc.exe',
        launchMode: 'template_file',
        sortOrder: 1,
        isActive: true,
        arguments: const [
          RemoteToolArgument(value: '{FILE}', isActive: true),
        ],
      );
      expect(t.acceptsFileParam, isTrue);
      expect(RemoteTool.containsFilePlaceholder('{file}'), isTrue);
    });

    test('δεν αναγνωρίζει άμεση εκτέλεση χωρίς template mode', () {
      final t = RemoteTool(
        id: 11,
        name: 'RDP Direct',
        role: ToolRole.rdp,
        executablePath: r'C:\Windows\System32\mstsc.exe',
        launchMode: 'direct_exec',
        sortOrder: 1,
        isActive: true,
        arguments: const [
          RemoteToolArgument(value: '{FILE}', isActive: true),
        ],
      );
      expect(t.acceptsFileParam, isFalse);
    });
  });
}
