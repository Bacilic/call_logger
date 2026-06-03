import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/app_config.dart';
import 'dictionary_service.dart';

/// Μέγιστο μέγεθος αρχείου πυρήνα λεξικού (bytes).
const int kCoreLexiconMaxFileBytes = 50 * 1024 * 1024;

/// Επιστρέφει μήνυμα σφάλματος ή `null` αν το αρχείο είναι έγκυρο πυρήνας.
Future<String?> validateCoreDictionaryFile(String path) async {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return 'Δεν επιλέχθηκε διαδρομή αρχείου.';
  }
  if (!trimmed.toLowerCase().endsWith('.txt')) {
    return 'Το αρχείο πρέπει να έχει επέκταση .txt';
  }
  final file = File(trimmed);
  if (!await file.exists()) {
    return 'Το αρχείο δεν βρέθηκε:\n$trimmed';
  }
  final length = await file.length();
  if (length == 0) {
    return 'Το αρχείο είναι κενό.';
  }
  if (length > kCoreLexiconMaxFileBytes) {
    return 'Το αρχείο υπερβαίνει το επιτρεπτό μέγεθος (50 MB).';
  }

  String text;
  try {
    text = await file.readAsString(encoding: utf8);
  } catch (_) {
    return 'Δεν ήταν δυνατή η ανάγνωση του αρχείου (αναμενόμενο UTF-8).';
  }
  if (text.trim().isEmpty) {
    return 'Το αρχείο είναι κενό.';
  }

  var validLines = 0;
  for (final line in const LineSplitter().convert(text)) {
    final display = line.trim();
    if (display.isEmpty || display.startsWith('#')) continue;
    if (DictionaryService.canonicalLexiconKey(display).length < 2) continue;
    validLines++;
    if (validLines >= 1) break;
  }
  if (validLines < 1) {
    return 'Το αρχείο δεν περιέχει έγκυρες λέξεις (τουλάχιστον μία γραμμή, όχι σχόλιο #).';
  }
  return null;
}

/// Αντίγραφο σε portable `dictionaries/` με διατήρηση ονόματος αρχείου.
Future<String> copyFileToPortableDictionaries(String sourcePath) async {
  final normSource = p.normalize(p.absolute(sourcePath.trim()));
  final dir = AppConfig.portableDictionariesDirectory;
  await Directory(dir).create(recursive: true);
  final target = p.normalize(p.join(dir, p.basename(normSource)));
  if (normSource != target) {
    await File(normSource).copy(target);
  }
  return target;
}
