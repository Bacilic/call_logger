import 'package:call_logger/core/database/remote_tools_repository.dart';
import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/calls/utils/call_remote_targets.dart';
import 'package:flutter_test/flutter_test.dart';

RemoteTool _tool({
  required int id,
  required ToolRole role,
  String? vncHostPrefix,
  bool isExclusive = false,
}) {
  return RemoteTool(
    id: id,
    name: role.dbValue.toUpperCase(),
    role: role,
    executablePath: r'C:\dummy.exe',
    launchMode: 'direct_exec',
    sortOrder: 0,
    isActive: true,
    vncHostPrefix: vncHostPrefix,
    isExclusive: isExclusive,
  );
}

void main() {
  group('CallRemoteTargets', () {
    test('resolvedRdpHost από ελεύθερο κείμενο IPv4', () {
      final s = SmartEntitySelectorState(equipmentText: '192.168.0.10');
      final tools = [_tool(id: 3, role: ToolRole.rdp)];
      expect(CallRemoteTargets.resolvedRdpHost(s, tools), '192.168.0.10');
    });

    test('visibleRemoteToolsForCallState: προεπιλεγμένο + παράμετρος anydesk', () {
      final eq = EquipmentModel(
        code: 'X',
        remoteParams: {'anydesk': '123456789'},
        defaultRemoteTool: '2',
      );
      final s = SmartEntitySelectorState(selectedEquipment: eq);
      final ad = _tool(id: 2, role: ToolRole.anydesk);
      final vnc = _tool(id: 3, role: ToolRole.vnc);
      final tools = [ad, vnc];
      final vis = CallRemoteTargets.visibleRemoteToolsForCallState(s, tools);
      expect(vis.map((t) => t.id).toList(), [2]);
    });

    test('visibleRemoteToolsForCallState: ελεύθερο κείμενο AnyDesk', () {
      final s = SmartEntitySelectorState(equipmentText: '123456789');
      final ad = _tool(id: 2, role: ToolRole.anydesk);
      final vis = CallRemoteTargets.visibleRemoteToolsForCallState(s, [ad]);
      expect(vis, [ad]);
    });

    test('visibleRemoteToolsForCallState: strict validation κόβει default χωρίς στόχο', () {
      final eq = EquipmentModel(
        code: '',
        remoteParams: const {},
        defaultRemoteTool: '1',
      );
      final s = SmartEntitySelectorState(selectedEquipment: eq);
      final vnc = _tool(id: 1, role: ToolRole.vnc);
      final vis = CallRemoteTargets.visibleRemoteToolsForCallState(s, [vnc]);
      expect(vis, isEmpty);
    });

    test('visibleRemoteToolsForCallState: exclusive suppression κρατά μόνο αποκλειστικά', () {
      final eq = EquipmentModel(
        code: '99',
        remoteParams: const {'anydesk': '123456789'},
        defaultRemoteTool: '1',
      );
      final s = SmartEntitySelectorState(selectedEquipment: eq);
      final vnc = _tool(id: 1, role: ToolRole.vnc, isExclusive: false);
      final ad = _tool(id: 2, role: ToolRole.anydesk, isExclusive: true);
      final vis = CallRemoteTargets.visibleRemoteToolsForCallState(s, [vnc, ad]);
      expect(vis.map((t) => t.id).toList(), [2]);
    });

    test('όλα chips αποεπιλεγμένα → default id null (parse)', () {
      expect(RemoteToolsRepository.parseDefaultRemoteToolId(null), isNull);
      expect(RemoteToolsRepository.parseDefaultRemoteToolId(''), isNull);
      expect(RemoteToolsRepository.parseDefaultRemoteToolId('12'), 12);
    });

    test('shouldHideRemoteConnectionButtons όταν το προεπιλεγμένο εργαλείο είναι ανενεργό', () {
      final eq = EquipmentModel(
        code: 'X',
        defaultRemoteTool: '1',
      );
      final inactive = _tool(id: 1, role: ToolRole.vnc).copyWith(isActive: false);
      expect(
        CallRemoteTargets.shouldHideRemoteConnectionButtons(eq, [inactive]),
        isTrue,
      );
      final active = _tool(id: 1, role: ToolRole.vnc);
      expect(
        CallRemoteTargets.shouldHideRemoteConnectionButtons(eq, [active]),
        isFalse,
      );
    });

    test('vncLikeTargetResolved χρησιμοποιεί vnc_host_prefix από ορισμό εργαλείου', () {
      final eq = EquipmentModel(
        code: '99',
        remoteParams: const {},
      );
      final vnc = _tool(
        id: 1,
        role: ToolRole.vnc,
        vncHostPrefix: 'PC',
      );
      expect(eq.vncLikeTargetResolved(vnc), 'PC99');
    });
  });
}
