import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/remote_tools_repository.dart';
import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/core/services/remote_connection_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Οι πύλες που πρέπει να περάσει μια εκκίνηση πριν θεωρηθεί επιβεβαιωμένη.
///
/// Το συμβόλαιο που φυλάνε: **το κουμπί κλειδώνει μόνο πάνω σε εκκίνηση που
/// έγινε πραγματικά.** Το κλείδωμα κρατά δεκάδες δευτερόλεπτα χωρίς τρόπο
/// ακύρωσης· αν στηριζόταν σε εκκίνηση που απέτυχε σιωπηλά, ο χρήστης θα
/// περίμενε μπροστά σε νεκρό κουμπί.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String fakeExecutable;
  late RemoteToolsRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('remote_gates_');
    fakeExecutable = '${tempDir.path}${Platform.pathSeparator}tool.exe';
    File(fakeExecutable).writeAsStringSync('');
    repo = RemoteToolsRepository(DatabaseHelper.instance);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  RemoteTool toolWith({
    required ToolRole role,
    List<RemoteToolArgument> arguments = const [
      RemoteToolArgument(value: '/v:{TARGET}'),
    ],
  }) => RemoteTool(
    id: 7,
    name: 'Απομακρυσμένη',
    role: role,
    executablePath: fakeExecutable,
    sortOrder: 0,
    isActive: true,
    arguments: arguments,
  );

  /// Στήνει υπηρεσία με ελεγχόμενες πύλες. Η προεπιλογή είναι «όλα καλά»,
  /// ώστε κάθε τεστ να χαλάει **μία** πύλη και να φαίνεται ποια δοκιμάζεται.
  ({RemoteConnectionService service, List<String> launched}) buildService({
    bool portOpen = true,
    bool processAlive = true,
    int? pid = 4242,
    bool launcherThrows = false,
  }) {
    final launched = <String>[];
    return (
      launched: launched,
      service: RemoteConnectionService(
        repo,
        aliveGrace: Duration.zero,
        portProbe: (host, port, timeout) async => portOpen,
        aliveProbe: (_) async => processAlive,
        launcher: (exe, args) async {
          if (launcherThrows) throw const ProcessException('tool.exe', []);
          launched.add('$exe ${args.join(' ')}');
          return pid;
        },
      ),
    );
  }

  Future<void> launch(
    RemoteConnectionService service,
    RemoteTool tool, {
    String target = '192.168.13.82',
    Map<String, String> remoteParams = const {},
  }) => service.launchRemoteTool(
    tool: tool,
    resolvedTarget: target,
    remoteParams: remoteParams,
  );

  group('Πύλη 2 — ο απομακρυσμένος υπολογιστής απαντά', () {
    test('σβηστός υπολογιστής RDP: πετάει χωρίς καν να ξεκινήσει πρόγραμμα', () async {
      final built = buildService(portOpen: false);
      await expectLater(
        launch(built.service, toolWith(role: ToolRole.rdp)),
        throwsA(isA<Exception>()),
      );
      expect(
        built.launched,
        isEmpty,
        reason:
            'Χωρίς απάντηση στη θύρα, η αναμονή των σαράντα δευτερολέπτων θα '
            'ήταν αναμονή για το τίποτα.',
      );
    });

    test('σβηστός υπολογιστής VNC: πετάει', () async {
      final built = buildService(portOpen: false);
      await expectLater(
        launch(built.service, toolWith(role: ToolRole.vnc)),
        throwsA(isA<Exception>()),
      );
      expect(built.launched, isEmpty);
    });

    test('εργαλείο με αρχείο σύνδεσης: δεν ρωτιέται καθόλου θύρα', () async {
      // Ο στόχος είναι διαδρομή στον δίσκο, όχι διεύθυνση δικτύου: ο έλεγχος
      // θύρας θα απέρριπτε μια απολύτως έγκυρη σύνδεση.
      final fileTool = toolWith(
        role: ToolRole.rdp,
        arguments: const [RemoteToolArgument(value: '{FILE}')],
      );
      expect(RemoteConnectionService.probePortForTool(fileTool), isNull);

      final built = buildService(portOpen: false);
      await launch(
        built.service,
        fileTool,
        target: r'C:\sessions\3557.rdp',
        remoteParams: const {'7': r'C:\sessions\3557.rdp'},
      );
      expect(built.launched, hasLength(1));
    });

    test('εργαλείο χωρίς γνωστή θύρα: δεν ρωτιέται', () {
      expect(
        RemoteConnectionService.probePortForTool(
          toolWith(role: ToolRole.anydesk),
        ),
        isNull,
      );
    });
  });

  group('Πύλη 3 — η διεργασία δημιουργήθηκε', () {
    test('χωρίς αναγνωριστικό διεργασίας: πετάει', () async {
      final built = buildService(pid: null);
      await expectLater(
        launch(built.service, toolWith(role: ToolRole.rdp)),
        throwsA(isA<Exception>()),
      );
    });

    test('η εκκίνηση πετάει: το σφάλμα δεν καταπίνεται', () async {
      final built = buildService(launcherThrows: true);
      await expectLater(
        launch(built.service, toolWith(role: ToolRole.rdp)),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Πύλη 4 — η διεργασία ζει ακόμη', () {
    test('RDP που πεθαίνει αμέσως: πετάει', () async {
      final built = buildService(processAlive: false);
      await expectLater(
        launch(built.service, toolWith(role: ToolRole.rdp)),
        throwsA(isA<Exception>()),
      );
    });

    test('AnyDesk που πεθαίνει αμέσως: ΔΕΝ πετάει', () async {
      // Όταν το AnyDesk τρέχει ήδη, το νέο στιγμιότυπο περνά την εντολή στο
      // ανοιχτό και τερματίζει νόμιμα. Η πύλη 4 εδώ θα ανακοίνωνε αποτυχία τη
      // στιγμή που η συνεδρία μόλις άνοιξε.
      final anydesk = toolWith(role: ToolRole.anydesk);
      expect(RemoteConnectionService.holdsOwnWindow(anydesk), isFalse);

      final built = buildService(processAlive: false);
      await launch(built.service, anydesk);
      expect(built.launched, hasLength(1));
    });
  });

  test('όλες οι πύλες περνούν: η εκκίνηση ολοκληρώνεται', () async {
    final built = buildService();
    await launch(built.service, toolWith(role: ToolRole.rdp));
    expect(built.launched.single, contains('192.168.13.82'));
  });
}
