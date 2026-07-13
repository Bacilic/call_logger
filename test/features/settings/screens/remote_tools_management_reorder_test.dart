import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/features/settings/screens/remote_tools_management_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('remoteToolArgumentsSummary', () {
    test('απόκρυψη κωδικού στη σύνοψη λίστας', () {
      final tool = RemoteTool(
        id: 1,
        name: 'VNC Test',
        role: ToolRole.vnc,
        executablePath: r'C:\vnc.exe',
        sortOrder: 1,
        isActive: true,
        arguments: const [
          RemoteToolArgument(value: '-password=pass99', isActive: true),
        ],
      );

      expect(
        remoteToolArgumentsSummary(tool),
        '-password=***',
      );
    });
  });

  group('reorderedPositionOneBased', () {
    test('μετακίνηση προς τα κάτω: newIndex > oldIndex αφαιρεί 1', () {
      expect(reorderedPositionOneBased(0, 2), 2);
      expect(reorderedPositionOneBased(0, 4), 4);
      expect(reorderedPositionOneBased(1, 3), 3);
    });

    test('μετακίνηση προς τα πάνω: newIndex <= oldIndex → newIndex + 1', () {
      expect(reorderedPositionOneBased(3, 0), 1);
      expect(reorderedPositionOneBased(2, 1), 2);
      expect(reorderedPositionOneBased(2, 2), 3);
    });

    test('από αρχή στο τέλος και αντίστροφα', () {
      expect(reorderedPositionOneBased(0, 5), 5);
      expect(reorderedPositionOneBased(4, 0), 1);
    });
  });
}
