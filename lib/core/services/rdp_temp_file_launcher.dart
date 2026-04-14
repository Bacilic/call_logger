import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../database/database_v1_schema.dart';

/// Εκκίνηση RDP μέσω προσωρινού αρχείου `.rdp` (launcher, όχι πλήρης RDP client).
abstract final class RdpTempFileLauncher {
  RdpTempFileLauncher._();

  static const String fileNamePrefix = 'call_logger_rdp_';

  /// Καθαρισμός ορφανών `.rdp` στο temp (μετά από crash / lock).
  static void sweepOrphanTempRdpFiles() {
    try {
      final dir = Directory.systemTemp;
      if (!dir.existsSync()) return;
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.startsWith(fileNamePrefix) && name.toLowerCase().endsWith('.rdp')) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Περιεχόμενο `.rdp` με αντικατάσταση placeholders· αφαιρεί κενή γραμμή `username:s:`.
  static String buildRdpFileContent({
    required String template,
    required String serverIp,
    String? username,
  }) {
    var text = template
        .replaceAll('{server_ip}', serverIp.trim())
        .replaceAll('{username}', username?.trim() ?? '');
    final lines = text.split(RegExp(r'\r\n|\n|\r'));
    final out = <String>[];
    for (final line in lines) {
      final trimmed = line.trimRight();
      if (trimmed.startsWith('username:s:')) {
        final rest = trimmed.substring('username:s:'.length).trim();
        if (rest.isEmpty) continue;
      }
      out.add(line);
    }
    return out.join('\r\n');
  }

  /// Γράφει temp `.rdp`, εκκινεί [mstscPath], προγραμματίζει διαγραφή μετά από 5 s.
  /// Σε σφάλμα εκκίνησης διαγράφει το αρχείο αμέσως.
  static Future<void> launch({
    required String mstscPath,
    required String serverIp,
    String? username,
    String? configTemplate,
  }) async {
    final template = (configTemplate?.trim().isNotEmpty ?? false)
        ? configTemplate!
        : kDefaultRdpConfigTemplate;
    final content = buildRdpFileContent(
      template: template,
      serverIp: serverIp,
      username: username,
    );
    final dir = Directory.systemTemp;
    final name =
        '$fileNamePrefix${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 30)}.rdp';
    final file = File(p.join(dir.path, name));
    await file.writeAsString(content, flush: true);
    try {
      await Process.start(
        mstscPath,
        [file.path],
        mode: ProcessStartMode.detached,
      );
    } catch (e, st) {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
      Error.throwWithStackTrace(e, st);
    }
    final pathToDelete = file.path;
    unawaited(
      Future<void>.delayed(const Duration(seconds: 5), () {
        try {
          final f = File(pathToDelete);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }),
    );
  }
}
