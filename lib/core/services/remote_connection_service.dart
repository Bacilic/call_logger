import 'dart:io';

import '../database/remote_tools_repository.dart';
import '../models/remote_tool.dart';
import '../models/remote_tool_role.dart';
import 'remote_launcher_service.dart';
import 'remote_tools_paths_helper.dart';

/// Ρωτά αν ο υπολογιστής απαντά στη θύρα του εργαλείου.
typedef PortReachabilityProbe =
    Future<bool> Function(String host, int port, Duration timeout);

/// Ρωτά αν η διεργασία με αυτό το αναγνωριστικό ζει ακόμη.
typedef ProcessAliveProbe = Future<bool> Function(int pid);

/// Ξεκινά το πρόγραμμα και επιστρέφει το αναγνωριστικό διεργασίας.
typedef ProcessLauncher =
    Future<int?> Function(String executable, List<String> arguments);

/// Υπηρεσία απομακρυσμένων συνδέσεων: διαδρομές από `remote_tools`, εκκίνηση με ανάλυση ορισμάτων.
///
/// **Η εκκίνηση είτε επιβεβαιώνεται είτε πετάει.** Δεν υπάρχει τρίτη έκβαση,
/// και ο λόγος είναι το κουμπί που την καλεί: κλειδώνει για δεκάδες
/// δευτερόλεπτα, χωρίς τρόπο να ξεκλειδωθεί νωρίτερα. Ένα κλείδωμα πάνω σε
/// εκκίνηση που δεν έγινε ποτέ θα ήταν χειρότερο από το πρόβλημα που λύνει.
class RemoteConnectionService {
  RemoteConnectionService(
    this._toolsRepo, {
    PortReachabilityProbe? portProbe,
    ProcessAliveProbe? aliveProbe,
    ProcessLauncher? launcher,
    Duration? aliveGrace,
  }) : _portProbe = portProbe ?? _probePortWithSocket,
       _aliveProbe = aliveProbe ?? _probeProcessWithTasklist,
       _launcher = launcher ?? _startDetachedProcess,
       _aliveGrace = aliveGrace ?? processAliveGrace;

  final RemoteToolsRepository _toolsRepo;
  final PortReachabilityProbe _portProbe;
  final ProcessAliveProbe _aliveProbe;
  final ProcessLauncher _launcher;
  final Duration _aliveGrace;

  /// Πόσο περιμένουμε πριν ρωτήσουμε «ζει ακόμη;».
  ///
  /// Αρκετά ώστε ένα πρόγραμμα που καταρρέει στην εκκίνηση να έχει προλάβει να
  /// πεθάνει, αρκετά λίγο ώστε ο χρήστης να μη νιώσει καθυστέρηση.
  static const Duration processAliveGrace = Duration(milliseconds: 800);

  /// Πόσο περιμένουμε τον απομακρυσμένο υπολογιστή να απαντήσει.
  static const Duration portProbeTimeout = Duration(milliseconds: 1500);

  /// Η θύρα στην οποία ακούει ο απομακρυσμένος υπολογιστής ανά εργαλείο, ή
  /// `null` όταν δεν υπάρχει θύρα να ρωτηθεί.
  ///
  /// Ο έλεγχος παραλείπεται όταν το εργαλείο ανοίγει **αρχείο σύνδεσης**: εκεί
  /// ο στόχος είναι διαδρομή στον δίσκο, όχι διεύθυνση δικτύου, και ο
  /// υπολογιστής προκύπτει από το περιεχόμενο του αρχείου.
  static int? probePortForTool(RemoteTool tool) {
    if (tool.acceptsFileParam) return null;
    return switch (tool.role) {
      ToolRole.vnc => 5900,
      ToolRole.rdp => 3389,
      _ => null,
    };
  }

  /// True για εργαλεία που κρατούν **δικό τους παράθυρο** όσο ζει η συνεδρία.
  ///
  /// Μόνο σε αυτά έχει νόημα να ρωτηθεί αν η διεργασία ζει. Το AnyDesk, όταν
  /// τρέχει ήδη, περνά την εντολή στο ανοιχτό στιγμιότυπο και **πεθαίνει
  /// νόμιμα** αμέσως μετά· εκεί ο ίδιος έλεγχος θα ανακοίνωνε αποτυχία τη
  /// στιγμή που η συνεδρία μόλις άνοιξε.
  static bool holdsOwnWindow(RemoteTool tool) =>
      tool.role == ToolRole.rdp || tool.role == ToolRole.vnc;

  /// Πρώτο υπαρκτό `.rdp` path από ενεργά ορίσματα (εκτός `__rdp_file__` template body).
  static String? firstExistingRdpPathFromArguments(RemoteTool tool) {
    for (final a in tool.arguments.where((x) => x.isActive)) {
      if (a.description.trim() == '__rdp_file__') continue;
      final v = a.value.trim();
      if (v.toLowerCase().endsWith('.rdp')) {
        try {
          if (File(v).existsSync()) return v;
        } catch (_) {}
      }
    }
    return null;
  }

  String? _resolvedFilePathForLaunch(
    RemoteTool tool,
    Map<String, String> remoteParams,
  ) {
    if (tool.acceptsFileParam) {
      final fromEquipment = _toolsRepo.resolveParamValue(
        remoteParams: remoteParams,
        tool: tool,
      );
      final v = fromEquipment?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return firstExistingRdpPathFromArguments(tool);
  }

  List<String> _resolvedLaunchArguments(
    RemoteTool tool, {
    required String? equipmentCode,
    required String resolvedTarget,
    required Map<String, String> remoteParams,
  }) {
    final fp = _resolvedFilePathForLaunch(tool, remoteParams);
    return tool.effectiveActiveArguments
        .where((a) => a.description.trim() != '__rdp_file__')
        .map(
          (a) => RemoteLauncherService.replaceAllPlaceholders(
            a.value,
            equipmentCode: equipmentCode,
            resolvedTarget: resolvedTarget,
            filePath: fp,
          ),
        )
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<String?> getValidPathForTool(RemoteTool tool) =>
      validExecutablePathForTool(repo: _toolsRepo, tool: tool, role: tool.role);

  static Future<bool> _probePortWithSocket(
    String host,
    int port,
    Duration timeout,
  ) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ρωτά τα Windows αν υπάρχει διεργασία με αυτό το αναγνωριστικό.
  ///
  /// Σε αδυναμία απάντησης επιστρέφει `true`: η άγνοια δεν επιτρέπεται να
  /// ακυρώσει μια εκκίνηση που πιθανότατα πέτυχε.
  static Future<bool> _probeProcessWithTasklist(int pid) async {
    if (!Platform.isWindows) return true;
    try {
      final result = await Process.run('tasklist', [
        '/FI',
        'PID eq $pid',
        '/NH',
      ]);
      final out = (result.stdout ?? '').toString();
      return out.contains('$pid');
    } catch (_) {
      return true;
    }
  }

  static Future<int?> _startDetachedProcess(
    String executable,
    List<String> arguments,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.detached,
    );
    return process.pid;
  }

  /// Γενική εκκίνηση με ανάλυση placeholders στα ορίσματα.
  ///
  /// Περνά από τέσσερις πύλες. Αν κάποια πέσει, πετάει με μήνυμα που εξηγεί
  /// **ποια** — ο καλών δεν κλειδώνει τίποτα και ο χρήστης ξαναπροσπαθεί
  /// αμέσως.
  Future<void> launchRemoteTool({
    required RemoteTool tool,
    required String resolvedTarget,
    required Map<String, String> remoteParams,
    String? equipmentCode,
  }) async {
    // Πύλη 1 — υπάρχει πρόγραμμα να τρέξει.
    final path = await validExecutablePathForTool(
      repo: _toolsRepo,
      tool: tool,
      role: tool.role,
    );
    if (path == null) {
      throw Exception(
        'Δεν βρέθηκε εκτελέσιμο για «${tool.name}». Ορίστε διαδρομή στη διαχείριση εργαλείων.',
      );
    }

    // Πύλη 2 — ο απομακρυσμένος υπολογιστής απαντά.
    final port = probePortForTool(tool);
    if (port != null) {
      final reachable = await _portProbe(
        resolvedTarget,
        port,
        portProbeTimeout,
      );
      if (!reachable) {
        throw Exception(
          'Ο υπολογιστής $resolvedTarget δεν απαντά ή το «${tool.name}» δεν τρέχει εκεί (θύρα $port).',
        );
      }
    }

    final arguments = _resolvedLaunchArguments(
      tool,
      equipmentCode: equipmentCode,
      resolvedTarget: resolvedTarget,
      remoteParams: remoteParams,
    );

    // Πύλη 3 — η διεργασία δημιουργήθηκε.
    final int? pid;
    try {
      pid = await _launcher(path, arguments);
    } catch (e) {
      throw Exception('Δεν ξεκίνησε το «${tool.name}»: $e');
    }
    if (pid == null || pid <= 0) {
      throw Exception(
        'Δεν ξεκίνησε το «${tool.name}» — τα Windows δεν επέστρεψαν διεργασία.',
      );
    }

    // Πύλη 4 — η διεργασία ζει ακόμη λίγο μετά.
    if (!holdsOwnWindow(tool)) return;
    await Future<void>.delayed(_aliveGrace);
    final alive = await _aliveProbe(pid);
    if (!alive) {
      throw Exception(
        'Το «${tool.name}» άνοιξε και έκλεισε αμέσως. Ελέγξτε τις παραμέτρους του εργαλείου.',
      );
    }
  }
}
