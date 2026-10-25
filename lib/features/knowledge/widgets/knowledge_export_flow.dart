import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/database/knowledge_base_repository.dart';
import '../../../core/utils/desktop_directory.dart';
import '../../../core/utils/file_picker_session.dart';
import '../../../core/utils/user_facing_error_messages.dart';
import '../services/knowledge_ai_prompt_store.dart';
import '../services/knowledge_export_markdown.dart';

/// Επιλογή θέσης αποθήκευσης — αντικαθίσταται στα τεστ.
typedef KnowledgeExportSavePathPicker =
    Future<String?> Function(
      String suggestedFileName,
      String? initialDirectory,
    );

Future<String?> _pickWithSystemDialog(
  String suggestedFileName,
  String? initialDirectory,
) async {
  final uri = (await FilePickerSession.run(
    () async => FilePicker.saveFile(
      dialogTitle: 'Εξαγωγή Βάσης Γνώσης για ΤΝ',
      fileName: suggestedFileName,
      initialDirectory: initialDirectory,
      type: FileType.custom,
      allowedExtensions: const ['md'],
      bytes: Uint8List(0),
    ),
  )).value;
  return uri?.toFilePath();
}

/// «Εξαγωγή για ΤΝ»: όλα τα άρθρα με την οδηγία του χρήστη σε ένα αρχείο, για
/// επικόλληση σε όποια ΤΝ θέλει. Τις προτάσεις τις εφαρμόζει ο ίδιος.
///
/// Ο messenger κρατιέται **πριν** από κάθε αναμονή: ο διάλογος αποθήκευσης
/// κρατά αρκετά ώστε ο `context` να μην ισχύει πια.
Future<void> runKnowledgeExport({
  required BuildContext context,
  required KnowledgeBaseRepository repository,
  KnowledgeExportSavePathPicker pickSavePath = _pickWithSystemDialog,
  DateTime Function() now = DateTime.now,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));

  final articles = await repository.listArticles();
  if (articles.isEmpty) {
    say('Η Βάση Γνώσης δεν έχει ακόμη άρθρα για εξαγωγή.');
    return;
  }
  final markdown = buildKnowledgeExportMarkdown(
    instruction: await KnowledgePrompt.export.read(),
    articles: articles,
  );

  final fileName =
      'Βάση Γνώσης για ΤΝ ${DateFormat('dd-MM-yyyy').format(now())}.md';
  final path = await pickSavePath(fileName, desktopDirectory());
  if (path == null || path.trim().isEmpty) return;
  final target = path.toLowerCase().endsWith('.md') ? path : '$path.md';

  try {
    await File(target).writeAsString(markdown, flush: true);
  } on FileSystemException catch (e) {
    say('Δεν αποθηκεύτηκε η εξαγωγή: ${humanizeUserFacingError(e)}');
    return;
  }
  say('Εξήχθησαν ${articles.length} άρθρα στο $target');
}
