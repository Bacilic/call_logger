import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:flutter_test/flutter_test.dart';

RemoteTool _tool({List<RemoteToolArgument> arguments = const []}) => RemoteTool(
      id: 1,
      name: 'Test',
      role: ToolRole.rdp,
      executablePath: r'C:\test.exe',
      sortOrder: 0,
      isActive: true,
      arguments: arguments,
    );

void main() {
  group('RemoteTool.acceptsFileParam', () {
    test(
      'ενεργό όρισμα {FILE} → true ανεξάρτητα τρόπου εκκίνησης',
      () {
        final tool = _tool(
          arguments: const [
            RemoteToolArgument(value: '{FILE}', isActive: true),
          ],
        );
        expect(tool.acceptsFileParam, isTrue);
      },
    );

    test('ανενεργό όρισμα {FILE} → false', () {
      final tool = _tool(
        arguments: const [
          RemoteToolArgument(value: '{FILE}', isActive: false),
        ],
      );
      expect(tool.acceptsFileParam, isFalse);
    });

    test('χωρίς όρισμα {FILE} → false', () {
      final tool = _tool(
        arguments: const [
          RemoteToolArgument(value: '/v:{TARGET}', isActive: true),
        ],
      );
      expect(tool.acceptsFileParam, isFalse);
    });

    test('πεζά {file} σε ενεργό όρισμα → true', () {
      final tool = _tool(
        arguments: const [
          RemoteToolArgument(value: '{file}', isActive: true),
        ],
      );
      expect(tool.acceptsFileParam, isTrue);
      expect(RemoteTool.containsFilePlaceholder('{file}'), isTrue);
    });
  });
}
