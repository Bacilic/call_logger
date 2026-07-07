import 'package:call_logger/core/database/remote_tools_repository.dart';
import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/calls/utils/call_remote_targets.dart';
import 'package:call_logger/features/calls/utils/equipment_remote_param_key.dart';
import 'package:flutter_test/flutter_test.dart';

RemoteTool _tool({
  required int id,
  required ToolRole role,
  bool isExclusive = false,
  List<RemoteToolArgument> arguments = const [],
}) {
  return RemoteTool(
    id: id,
    name: role.dbValue.toUpperCase(),
    role: role,
    executablePath: r'C:\dummy.exe',
    sortOrder: 0,
    isActive: true,
    isExclusive: isExclusive,
    arguments: arguments,
  );
}

void main() {
  group('CallRemoteTargets', () {
    test('resolvedRdpHost από ελεύθερο κείμενο IPv4', () {
      final s = SmartEntitySelectorState(equipmentText: '192.168.0.10');
      final tools = [_tool(id: 3, role: ToolRole.rdp)];
      expect(CallRemoteTargets.resolvedRdpHost(s, tools), '192.168.0.10');
    });

    test(
      'resolvedLaunchTarget: RDP template_file με {file} επιστρέφει path αρχείου από equipment param',
      () {
        final eq = EquipmentModel(
          code: 'PC-1',
          remoteParams: const {'3': r'C:\templates\pc-1.rdp'},
        );
        final s = SmartEntitySelectorState(selectedEquipment: eq);
        final rdpFileTool = _tool(
          id: 3,
          role: ToolRole.rdp,
          arguments: const [
            RemoteToolArgument(value: '{file}', isActive: true),
          ],
        );
        expect(
          CallRemoteTargets.resolvedLaunchTarget(s, rdpFileTool, [rdpFileTool]),
          r'C:\templates\pc-1.rdp',
        );
        expect(CallRemoteTargets.canConnectForTool(s, rdpFileTool, [rdpFileTool]), isTrue);
      },
    );

    test('visibleRemoteToolsForCallState: προεπιλεγμένο + παράμετρος tool id', () {
      final eq = EquipmentModel(
        code: '12',
        remoteParams: {'2': '123456789'},
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

    test(
      'visibleRemoteToolsForCallState: exclusiveToolKey στον εξοπλισμό κρατά μόνο το εργαλείο',
      () {
        final eq = EquipmentModel(
          code: '999',
          remoteParams: {
            '2': '123456789',
            EquipmentRemoteParamKey.exclusiveToolKey: '2',
          },
          defaultRemoteTool: '1',
        );
        final s = SmartEntitySelectorState(selectedEquipment: eq);
        final vnc = _tool(id: 1, role: ToolRole.vnc);
        final ad = _tool(id: 2, role: ToolRole.anydesk);
        final vis = CallRemoteTargets.visibleRemoteToolsForCallState(s, [vnc, ad]);
        expect(vis.map((t) => t.id).toList(), [2]);
      },
    );

    test(
      'visibleRemoteToolsForCallState: χωρίς exclusiveToolKey εμφανίζονται όλα ακόμα κι αν tool.isExclusive',
      () {
        final eq = EquipmentModel(
          code: '999',
          remoteParams: const {'2': '123456789'},
          defaultRemoteTool: '1',
        );
        final s = SmartEntitySelectorState(selectedEquipment: eq);
        final vnc = _tool(id: 1, role: ToolRole.vnc, isExclusive: false);
        final ad = _tool(id: 2, role: ToolRole.anydesk, isExclusive: true);
        final vis = CallRemoteTargets.visibleRemoteToolsForCallState(s, [vnc, ad]);
        expect(vis.map((t) => t.id).toList(), [2, 1]);
      },
    );

    test(
      'visibleRemoteToolsForCallState: exclusiveToolKey σε άγνωστο id → όλα τα έγκυρα',
      () {
        final eq = EquipmentModel(
          code: '999',
          remoteParams: {
            '2': '123456789',
            EquipmentRemoteParamKey.exclusiveToolKey: '99',
          },
          defaultRemoteTool: '1',
        );
        final s = SmartEntitySelectorState(selectedEquipment: eq);
        final vnc = _tool(id: 1, role: ToolRole.vnc);
        final ad = _tool(id: 2, role: ToolRole.anydesk);
        final vis = CallRemoteTargets.visibleRemoteToolsForCallState(s, [vnc, ad]);
        expect(vis.map((t) => t.id).toList(), [2, 1]);
      },
    );

    test(
      'visibleRemoteToolsForCallState: applyExclusive false vs true με exclusiveToolKey',
      () {
        final eq = EquipmentModel(
          code: '999',
          remoteParams: {
            '2': '123456789',
            EquipmentRemoteParamKey.exclusiveToolKey: '2',
          },
          defaultRemoteTool: '1',
        );
        final s = SmartEntitySelectorState(selectedEquipment: eq);
        final vnc = _tool(id: 1, role: ToolRole.vnc);
        final ad = _tool(id: 2, role: ToolRole.anydesk);
        final catalog = [vnc, ad];

        final withExclusive = CallRemoteTargets.visibleRemoteToolsForCallState(
          s,
          catalog,
          applyExclusive: true,
        );
        final withoutExclusive = CallRemoteTargets.visibleRemoteToolsForCallState(
          s,
          catalog,
          applyExclusive: false,
        );

        expect(withExclusive.map((t) => t.id).toList(), [2]);
        expect(withoutExclusive.map((t) => t.id).toList(), [2, 1]);
        expect(CallRemoteTargets.exclusiveHidesTools(s, catalog), isTrue);
      },
    );

    test(
      'exclusiveHidesTools: false χωρίς exclusiveToolKey — ίδια λίστα true/false',
      () {
        final eq = EquipmentModel(
          code: '999',
          remoteParams: const {'2': '123456789'},
          defaultRemoteTool: '1',
        );
        final s = SmartEntitySelectorState(selectedEquipment: eq);
        final vnc = _tool(id: 1, role: ToolRole.vnc);
        final ad = _tool(id: 2, role: ToolRole.anydesk);
        final catalog = [vnc, ad];

        final withExclusive = CallRemoteTargets.visibleRemoteToolsForCallState(
          s,
          catalog,
          applyExclusive: true,
        );
        final withoutExclusive = CallRemoteTargets.visibleRemoteToolsForCallState(
          s,
          catalog,
          applyExclusive: false,
        );

        expect(withExclusive.map((t) => t.id).toList(), [2, 1]);
        expect(withoutExclusive.map((t) => t.id).toList(), [2, 1]);
        expect(CallRemoteTargets.exclusiveHidesTools(s, catalog), isFalse);
      },
    );

    test('όλα chips αποεπιλεγμένα → default id null (parse)', () {
      expect(RemoteToolsRepository.parseDefaultRemoteToolId(null), isNull);
      expect(RemoteToolsRepository.parseDefaultRemoteToolId(''), isNull);
      expect(RemoteToolsRepository.parseDefaultRemoteToolId('12'), 12);
    });

    test('vncLikeTargetResolved χρησιμοποιεί σταθερό πρόθεμα PC για ψηφιακό κωδικό', () {
      final eq = EquipmentModel(
        code: '2850',
        remoteParams: const {},
      );
      final vnc = _tool(
        id: 1,
        role: ToolRole.vnc,
      );
      expect(eq.vncLikeTargetResolved(vnc), 'PC2850');
    });

    test('generic με παράμετρο: resolvedLaunchTarget και visibleRemoteTools', () {
      final eq = EquipmentModel(
        code: '1137',
        remoteParams: const {'5': 'MANUAL-TGT'},
      );
      final s = SmartEntitySelectorState(selectedEquipment: eq);
      final gen = _tool(id: 5, role: ToolRole.generic);
      final catalog = [gen];

      expect(
        CallRemoteTargets.resolvedLaunchTarget(s, gen, catalog),
        'MANUAL-TGT',
      );
      expect(CallRemoteTargets.canConnectForTool(s, gen, catalog), isTrue);
      expect(
        CallRemoteTargets.visibleRemoteToolsForCallState(s, catalog)
            .map((t) => t.id)
            .toList(),
        [5],
      );
    });

    test('generic χωρίς παράμετρο: κρύβεται από visibleRemoteTools', () {
      final eq = EquipmentModel(
        code: '1137',
        remoteParams: const {},
      );
      final s = SmartEntitySelectorState(selectedEquipment: eq);
      final gen = _tool(id: 5, role: ToolRole.generic);
      final catalog = [gen];

      expect(
        CallRemoteTargets.resolvedLaunchTarget(s, gen, catalog),
        isNull,
      );
      expect(
        CallRemoteTargets.visibleRemoteToolsForCallState(s, catalog),
        isEmpty,
      );
    });

    test('generic με ελεύθερο κείμενο: δεν εμφανίζεται χωρίς selectedEquipment', () {
      final s = SmartEntitySelectorState(equipmentText: 'foo');
      final gen = _tool(id: 5, role: ToolRole.generic);
      final catalog = [gen];

      expect(
        CallRemoteTargets.visibleRemoteToolsForCallState(s, catalog),
        isEmpty,
      );
    });
  });
}
