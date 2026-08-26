import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/remote_tools_repository.dart';
import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/core/services/remote_connection_service.dart';
import 'package:call_logger/core/services/remote_tool_connect_wait.dart';
import 'package:call_logger/features/calls/provider/remote_connect_cooldown_provider.dart';
import 'package:call_logger/features/calls/provider/remote_paths_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Το κλείδωμα του κουμπιού απομακρυσμένης σύνδεσης.
///
/// Το σφάλμα που φυλάει: η απομακρυσμένη επιφάνεια αργεί δεκάδες δευτερόλεπτα
/// να εμφανιστεί, ενώ το κουμπί ξεκλείδωνε μόλις τα Windows παρελάμβαναν τη
/// διεργασία. Στο ενδιάμεσο κενό, επτά πατήματα άνοιγαν επτά συνεδρίες.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String fakeExecutable;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('remote_cooldown_');
    fakeExecutable = '${tempDir.path}${Platform.pathSeparator}tool.exe';
    File(fakeExecutable).writeAsStringSync('');
    now = DateTime(2026, 8, 26, 10, 0, 0);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  RemoteTool toolWith({
    int id = 7,
    ToolRole role = ToolRole.rdp,
    int waitSeconds = 30,
  }) => RemoteTool(
    id: id,
    name: 'Εργαλείο $id',
    role: role,
    executablePath: fakeExecutable,
    sortOrder: 0,
    isActive: true,
    arguments: const [RemoteToolArgument(value: '/v:{TARGET}')],
    connectWaitSeconds: waitSeconds,
  );

  /// Δοχείο με καρφωμένο ρολόι και υπηρεσία που καταγράφει τις εκκινήσεις.
  ({ProviderContainer container, List<String> launched}) buildContainer({
    bool portOpen = true,
  }) {
    final launched = <String>[];
    final service = RemoteConnectionService(
      RemoteToolsRepository(DatabaseHelper.instance),
      aliveGrace: Duration.zero,
      portProbe: (host, port, timeout) async => portOpen,
      aliveProbe: (_) async => true,
      launcher: (exe, args) async {
        launched.add(args.join(' '));
        return 4242;
      },
    );
    final container = ProviderContainer(
      overrides: [
        remoteConnectClockProvider.overrideWithValue(() => now),
        remoteConnectionServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, launched: launched);
  }

  Future<String?> connect(
    ProviderContainer c,
    RemoteTool tool, {
    String target = '192.168.13.82',
  }) => c
      .read(remoteConnectLauncherProvider.notifier)
      .connect(tool: tool, target: target, remoteParams: const {});

  test('επτά πατήματα, μία συνεδρία', () async {
    final built = buildContainer();
    final tool = toolWith();

    for (var i = 0; i < 7; i++) {
      await connect(built.container, tool);
    }

    expect(
      built.launched,
      hasLength(1),
      reason:
          'Το κλείδωμα υπάρχει ακριβώς γι᾽ αυτό: όσο δεν έχει φανεί η '
          'απομακρυσμένη επιφάνεια, το κουμπί δεν ξαναδίνει την εντολή.',
    );
  });

  test('αποτυχημένη εκκίνηση δεν κλειδώνει τίποτα', () async {
    final built = buildContainer(portOpen: false);
    final tool = toolWith();

    final error = await connect(built.container, tool);

    expect(error, isNotNull);
    expect(
      built.container
          .read(remoteConnectCooldownProvider.notifier)
          .isLocked(toolId: tool.id, target: '192.168.13.82'),
      isFalse,
      reason:
          'Αναμονή σαράντα δευτερολέπτων για συνεδρία που δεν ξεκίνησε ποτέ '
          'θα ήταν χειρότερη από το πρόβλημα.',
    );
  });

  test('το κλείδωμα δένεται σε εργαλείο ΚΑΙ στόχο', () async {
    final built = buildContainer();
    final rdp = toolWith(id: 7);
    final vnc = toolWith(id: 8, role: ToolRole.vnc);

    await connect(built.container, rdp);
    final cooldown = built.container.read(
      remoteConnectCooldownProvider.notifier,
    );

    expect(cooldown.isLocked(toolId: 7, target: '192.168.13.82'), isTrue);
    expect(
      cooldown.isLocked(toolId: 8, target: '192.168.13.82'),
      isFalse,
      reason: 'Άλλο εργαλείο για τον ίδιο υπολογιστή μένει διαθέσιμο.',
    );
    expect(
      cooldown.isLocked(toolId: 7, target: '192.168.13.99'),
      isFalse,
      reason: 'Το ίδιο εργαλείο για άλλον υπολογιστή μένει διαθέσιμο.',
    );

    // Και στην πράξη: η δεύτερη σύνδεση όντως ξεκινά.
    await connect(built.container, vnc);
    expect(built.launched, hasLength(2));
  });

  test('όταν περάσει ο χρόνος, το κουμπί ξεκλειδώνει', () async {
    final built = buildContainer();
    final tool = toolWith(waitSeconds: 30);

    await connect(built.container, tool);
    expect(
      built.container
          .read(remoteConnectCooldownProvider.notifier)
          .isLocked(toolId: tool.id, target: '192.168.13.82'),
      isTrue,
    );

    now = now.add(const Duration(seconds: 31));
    expect(
      built.container
          .read(remoteConnectCooldownProvider.notifier)
          .isLocked(toolId: tool.id, target: '192.168.13.82'),
      isFalse,
    );

    await connect(built.container, tool);
    expect(built.launched, hasLength(2));
  });

  test('μηδέν δευτερόλεπτα σημαίνει χωρίς κλείδωμα', () async {
    final built = buildContainer();
    final tool = toolWith(waitSeconds: 0);

    await connect(built.container, tool);
    await connect(built.container, tool);

    expect(
      built.launched,
      hasLength(2),
      reason: 'Η ρύθμιση επιτρέπει ρητά το μηδέν για όποιον δεν το θέλει.',
    );
  });

  test('η τοπική παράκαμψη κερδίζει την κοινή τιμή', () async {
    final built = buildContainer();
    final tool = toolWith(waitSeconds: 30);
    await RemoteToolConnectWait.setLocalOverride(tool.id, 10);

    await connect(built.container, tool);

    // Στα δώδεκα δευτερόλεπτα η κοινή τιμή θα κρατούσε ακόμη· η δική μας όχι.
    now = now.add(const Duration(seconds: 12));
    expect(
      built.container
          .read(remoteConnectCooldownProvider.notifier)
          .isLocked(toolId: tool.id, target: '192.168.13.82'),
      isFalse,
      reason:
          'Ο χρόνος εξαρτάται από την ταχύτητα ΑΥΤΟΥ του μηχανήματος, όχι από '
          'τον κοινό ορισμό.',
    );
  });

  test('η αντίστροφη μέτρηση δείχνει όσα πραγματικά μένουν', () async {
    final built = buildContainer();
    final tool = toolWith(waitSeconds: 45);

    await connect(built.container, tool);
    now = now.add(const Duration(seconds: 7));

    expect(
      built.container
          .read(remoteConnectCooldownProvider.notifier)
          .remaining(toolId: tool.id, target: '192.168.13.82'),
      const Duration(seconds: 38),
    );
  });
}
