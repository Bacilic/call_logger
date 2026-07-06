import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/utils/equipment_remote_param_key.dart';
import 'package:flutter_test/flutter_test.dart';

RemoteTool _catalogTool({
  required int id,
  required String name,
  required ToolRole role,
  required int sortOrder,
}) {
  return RemoteTool(
    id: id,
    name: name,
    role: role,
    executablePath: r'C:\dummy.exe',
    launchMode: 'direct_exec',
    sortOrder: sortOrder,
    isActive: true,
  );
}

/// Κατάλογος όπως τα πραγματικά δεδομένα: VNC (1), RDP (3), AnyDesk (2).
List<RemoteTool> _realisticCatalog() => [
      _catalogTool(
        id: 1,
        name: 'VNC',
        role: ToolRole.vnc,
        sortOrder: 1,
      ),
      _catalogTool(
        id: 3,
        name: 'Απομακρυσμένη Επιφάνεια',
        role: ToolRole.rdp,
        sortOrder: 2,
      ),
      _catalogTool(
        id: 2,
        name: 'AnyDesk',
        role: ToolRole.anydesk,
        sortOrder: 3,
      ),
    ];

void main() {
  group('EquipmentModel effectiveDefaultRemoteToolId / hasInconsistentDefaultRemoteTool', () {
    late List<RemoteTool> catalog;

    setUp(() {
      catalog = _realisticCatalog();
    });

    test('αναπαραγωγή 1002: default 2 αλλά μόνο VNC επιλεγμένο → ασυνέπεια', () {
      final eq = EquipmentModel(
        defaultRemoteTool: '2',
        remoteParams: {'1': '4324324'},
      );

      expect(eq.effectiveDefaultRemoteToolId(catalog), 1);
      expect(eq.hasInconsistentDefaultRemoteTool(catalog), isTrue);
    });

    test('συνεπές: default και επιλογή ταυτίζονται', () {
      final eq = EquipmentModel(
        defaultRemoteTool: '1',
        remoteParams: {'1': 'x'},
      );

      expect(eq.hasInconsistentDefaultRemoteTool(catalog), isFalse);
    });

    test('κενό defaultRemoteTool → όχι ασυνέπεια', () {
      final eq = EquipmentModel(
        remoteParams: {'1': 'x'},
      );

      expect(eq.hasInconsistentDefaultRemoteTool(catalog), isFalse);
    });

    test('μη-αριθμητικό defaultRemoteTool → όχι ασυνέπεια (χειρίζεται ο resolver)', () {
      final eq = EquipmentModel(
        defaultRemoteTool: 'AnyDesk',
        remoteParams: {'1': 'x'},
      );

      expect(eq.hasInconsistentDefaultRemoteTool(catalog), isFalse);
    });

    test('αποθηκευμένο id χωρίς επιλεγμένο εργαλείο → ασυνέπεια', () {
      final eq = EquipmentModel(
        defaultRemoteTool: '2',
        remoteParams: {},
      );

      expect(eq.effectiveDefaultRemoteToolId(catalog), isNull);
      expect(eq.hasInconsistentDefaultRemoteTool(catalog), isTrue);
    });

    test('δεσμευμένα κλειδιά αγνοούνται στο effective', () {
      final eq = EquipmentModel(
        defaultRemoteTool: '1',
        remoteParams: {
          EquipmentRemoteParamKey.exclusiveToolKey: '2',
          '1': 'x',
        },
      );

      expect(eq.effectiveDefaultRemoteToolId(catalog), 1);
      expect(eq.hasInconsistentDefaultRemoteTool(catalog), isFalse);
    });

    test('επιλεγμένο εργαλείο με κενή τιμή παραμέτρου μετράει στο effective', () {
      final eq = EquipmentModel(
        defaultRemoteTool: '1',
        remoteParams: const {'1': ''},
      );

      expect(eq.effectiveDefaultRemoteToolId(catalog), 1);
      expect(eq.hasInconsistentDefaultRemoteTool(catalog), isFalse);
    });

    test('toMap περιλαμβάνει null default_remote_tool για εκκαθάριση στη βάση', () {
      final eq = EquipmentModel(code: 'X');

      expect(eq.toMap().containsKey('default_remote_tool'), isTrue);
      expect(eq.toMap()['default_remote_tool'], isNull);
    });

    group('displayPrimaryRemoteToolId (υπολογιζόμενο κύριο για τη λίστα)', () {
      test('χωρίς αποκλειστικό → το effective (πρώτο κατά σειρά)', () {
        final eq = EquipmentModel(remoteParams: {'1': 'x', '2': 'y'});

        expect(eq.displayPrimaryRemoteToolId(catalog), 1);
      });

      test('αγνοεί το αποθηκευμένο default_remote_tool (1002: default 2 → δείχνει 1)', () {
        final eq = EquipmentModel(
          defaultRemoteTool: '2',
          remoteParams: {'1': '4324324'},
        );

        expect(eq.displayPrimaryRemoteToolId(catalog), 1);
      });

      test('αποκλειστικό εργαλείο υπερισχύει του effective', () {
        final eq = EquipmentModel(
          remoteParams: {
            '1': 'x',
            EquipmentRemoteParamKey.exclusiveToolKey: '2',
          },
        );

        expect(eq.displayPrimaryRemoteToolId(catalog), 2);
      });

      test('αποκλειστικό id εκτός καταλόγου → πέφτει στο effective', () {
        final eq = EquipmentModel(
          remoteParams: {
            '1': 'x',
            EquipmentRemoteParamKey.exclusiveToolKey: '99',
          },
        );

        expect(eq.displayPrimaryRemoteToolId(catalog), 1);
      });

      test('χωρίς παραμέτρους και χωρίς αποκλειστικό → null', () {
        final eq = EquipmentModel(remoteParams: const {});

        expect(eq.displayPrimaryRemoteToolId(catalog), isNull);
      });
    });
  });
}
