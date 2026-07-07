import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/core/services/default_remote_tool_display.dart';
import 'package:flutter_test/flutter_test.dart';

RemoteTool _tool({
  required int id,
  required String name,
  bool isActive = true,
  DateTime? deletedAt,
}) {
  return RemoteTool(
    id: id,
    name: name,
    role: ToolRole.vnc,
    executablePath: r'C:\dummy.exe',
    sortOrder: 0,
    isActive: isActive,
    deletedAt: deletedAt,
  );
}

void main() {
  group('DefaultRemoteToolDisplay.resolve', () {
    test('μη-αριθμητική legacy τιμή → (άκυρο) με πλάγια γράμματα', () {
      final result = DefaultRemoteToolDisplay.resolve(
        'AnyDesk',
        [_tool(id: 1, name: 'TightVNC')],
      );

      expect(result.label, '(άκυρο)');
      expect(result.useMutedItalic, isTrue);
    });

    test('κενή ή null τιμή → εμβλημα – χωρίς πλάγια', () {
      for (final stored in <String?>[null, '', '   ']) {
        final result = DefaultRemoteToolDisplay.resolve(
          stored,
          [_tool(id: 1, name: 'TightVNC')],
        );

        expect(result.label, '–', reason: 'stored=$stored');
        expect(result.useMutedItalic, isFalse, reason: 'stored=$stored');
      }
    });

    test('έγκυρο αριθμητικό id ενεργού εργαλείου → όνομα εργαλείου', () {
      final result = DefaultRemoteToolDisplay.resolve(
        '2',
        [_tool(id: 2, name: 'AnyDesk Viewer')],
      );

      expect(result.label, 'AnyDesk Viewer');
      expect(result.useMutedItalic, isFalse);
    });

    test('αριθμητικό id που δεν βρίσκεται στη λίστα → ανενεργό/διαγραμμένο', () {
      final result = DefaultRemoteToolDisplay.resolve(
        '99',
        [_tool(id: 1, name: 'TightVNC')],
      );

      expect(result.label, startsWith('(ανενεργό / διαγραμμένο)'));
      expect(result.useMutedItalic, isTrue);
    });

    test('id διαγραμμένου εργαλείου → πλάγια γράμματα', () {
      final result = DefaultRemoteToolDisplay.resolve(
        '3',
        [
          _tool(
            id: 3,
            name: 'Παλιό VNC',
            deletedAt: DateTime(2024, 1, 1),
          ),
        ],
      );

      expect(result.label, '(ανενεργό / διαγραμμένο) Παλιό VNC');
      expect(result.useMutedItalic, isTrue);
    });

    test('id ανενεργού εργαλείου → πλάγια γράμματα', () {
      final result = DefaultRemoteToolDisplay.resolve(
        '4',
        [_tool(id: 4, name: 'Ανενεργό RDP', isActive: false)],
      );

      expect(result.label, '(ανενεργό) Ανενεργό RDP');
      expect(result.useMutedItalic, isTrue);
    });
  });
}
