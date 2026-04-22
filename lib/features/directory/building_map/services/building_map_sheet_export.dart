import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/utils/file_picker_initial_directory.dart';
import '../building_map_sheet_export_key.dart';
import 'building_map_sheet_export_save_path.dart';

/// Ασφαλές όνομα αρχείου (χωρίς `\\ / : * ? " < > |`).
String buildingMapExportSanitizedFileBaseName(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return 'floor_map';
  const forbidden = r'\/:*?"<>|';
  final buf = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (forbidden.contains(c)) {
      buf.write('_');
    } else {
      buf.write(c);
    }
  }
  s = buf.toString().replaceAll(RegExp(r'_+'), '_').trim();
  if (s.isEmpty || s == '.') return 'floor_map';
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s;
}

Future<String?> _defaultExportDirectoryPath() async {
  try {
    final d = await getDownloadsDirectory();
    if (d != null && Directory(d.path).existsSync()) return d.path;
  } catch (_) {}
  return initialDirectoryForFilePicker(null);
}

bool _isJpegPath(String path) {
  final e = p.extension(path).toLowerCase();
  return e == '.jpg' || e == '.jpeg';
}

Future<Uint8List> _encodePngBytes(ui.Image image) async {
  final bd =
      await image.toByteData(format: ui.ImageByteFormat.png);
  if (bd == null) {
    throw StateError('PNG byte data');
  }
  return bd.buffer.asUint8List();
}

Future<void> _writePng(String path, ui.Image image) async {
  final bytes = await _encodePngBytes(image);
  await File(path).writeAsBytes(bytes, flush: true);
}

Future<void> _writeJpeg(String path, ui.Image image) async {
  final pngBytes = await _encodePngBytes(image);
  final decoded = img.decodePng(pngBytes);
  if (decoded == null) {
    throw StateError('decode PNG');
  }

  // Το JPEG δεν υποστηρίζει άλφα· συνθέτουμε πρώτα πάνω σε λευκό φόντο.
  final flattened = img.Image(
    width: decoded.width,
    height: decoded.height,
    numChannels: 3,
  );
  img.fill(flattened, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(flattened, decoded, blend: img.BlendMode.alpha);

  await File(path).writeAsBytes(
    img.encodeJpg(flattened, quality: 92),
    flush: true,
  );
}

String _ensureImageExtension(String path, {required bool jpeg}) {
  final e = p.extension(path).toLowerCase();
  if (e == '.png' || e == '.jpg' || e == '.jpeg') return path;
  return path + (jpeg ? '.jpg' : '.png');
}

/// Εξαγωγή bitmap του φύλλου (εικόνα κατόψης + περιοχές τμημάτων, σύμφωνα με ορατότητα).
Future<void> exportBuildingMapSheetToImageFile({
  required BuildContext context,
  required String defaultFloorBaseName,
}) async {
  final boundary = buildingMapSheetExportRepaintKey.currentContext
      ?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ο χάρτης δεν είναι διαθέσιμος για εξαγωγή.')),
    );
    return;
  }

  final safeBase = buildingMapExportSanitizedFileBaseName(defaultFloorBaseName);
  final initialDirectory = await _defaultExportDirectoryPath();

  if (!context.mounted) return;
  final picked = await promptBuildingMapExportSavePath(
    context: context,
    sanitizedBaseName: safeBase,
    initialDirectoryPath: initialDirectory,
  );
  if (picked == null) return;
  if (!context.mounted) return;

  final pixelRatio = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 2.5);
  final ui.Image raster;
  try {
    raster = await boundary.toImage(pixelRatio: pixelRatio);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Σφάλμα εξαγωγής: $e')),
    );
    return;
  }

  final jpeg = _isJpegPath(picked);
  var outPath = _ensureImageExtension(picked, jpeg: jpeg);

  try {
    if (jpeg) {
      await _writeJpeg(outPath, raster);
    } else {
      await _writePng(outPath, raster);
    }
    raster.dispose();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Αποθηκεύτηκε: $outPath')),
    );
  } catch (e) {
    raster.dispose();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Αποτυχία εγγραφής: $e')),
    );
  }
}
