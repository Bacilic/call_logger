import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/dictionary_repository.dart';
import '../../../core/errors/dictionary_export_exception.dart';
import '../../../core/models/dictionary_import_mode.dart';
import '../../../core/providers/core_lexicon_provider.dart';
import '../../../core/providers/lexicon_categories_provider.dart';
import '../../../core/providers/lexicon_language_recalc_provider.dart';
import '../../../core/providers/spell_check_provider.dart';
import '../../../core/services/master_dictionary_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/file_picker_session.dart';
import '../../../core/utils/picker_location_memory.dart';
import '../../../core/utils/user_facing_error_messages.dart';
import '../services/lexicon_row_writer.dart';
import '../widgets/add_custom_words_dialog.dart';
import 'dictionary_manager_screen.dart';

/// Οι ενέργειες πάνω στις λέξεις του λεξικού: προσθήκη, επεξεργασία (με
/// προαγωγή από το πρόχειρο), διαγραφή, εισαγωγή αρχείου TXT, μεταγλώττιση.
///
/// Συνεργάτης της [DictionaryManagerScreenState] (Σύνθεση): η λίστα, η
/// κατάστασή της και η τοπική ενημέρωση γραμμών ανήκουν στην οθόνη· εδώ ζουν
/// μόνο οι διάλογοι επιβεβαίωσης και οι εγγραφές στη βάση.
class DictionaryManagerActions {
  DictionaryManagerActions(this.host);

  final DictionaryManagerScreenState host;

  BuildContext get context => host.context;

  WidgetRef get ref => host.ref;

  MasterDictionaryService get _master => host.master;

  /// Ο ένας δρόμος εγγραφής λέξεων — κοινός με τον μαζικό έλεγχο με ΤΝ.
  late final LexiconRowWriter writer = LexiconRowWriter(_master);

  String _addCustomWordErrorMessage(Object e) => humanizeUserFacingError(e);

  Future<void> openAddCustomWordDialog() async {
    List<String> categories;
    try {
      categories = await ref.read(lexiconCategoriesProvider.future);
    } catch (_) {
      categories = SettingsService.defaultLexiconCategoriesList;
    }
    if (categories.isEmpty) {
      categories = SettingsService.defaultLexiconCategoriesList;
    }
    categories = categories
        .where((c) => c != AppConfig.lexiconCategoryUnspecified)
        .toList();
    if (categories.isEmpty) {
      categories = SettingsService.defaultLexiconCategoriesList;
    }
    if (!context.mounted) return;

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AddCustomWordsDialog(
        categories: categories,
        master: _master,
        addCustomWordErrorMessage: _addCustomWordErrorMessage,
      ),
    );

    if (added == true && context.mounted) {
      ref.invalidate(coreLexiconProvider);
      ref.invalidate(spellCheckServiceProvider);
      flushLexiconProviderChain(ref);
      ref.read(lexiconMasterDataRevisionProvider.notifier).bump();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Οι λέξεις προστέθηκαν στο λεξικό'),
          duration: Duration(seconds: 3),
        ),
      );
      await host.refreshList();
    }
  }

  Future<void> importTxtFile() async {
    const memory = PickerLocationMemory('lexicon_txt');
    final r = (await FilePickerSession.run(
      () async => FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        initialDirectory: await memory.initialDirectory(),
      ),
    )).value;
    final path = r?.path;
    if (path == null) return;
    await memory.remember(path);
    if (!context.mounted) return;
    final mode = await showDialog<DictionaryImportMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Εισαγωγή αρχείου'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, DictionaryImportMode.enrich),
            child: const Text('Εμπλουτισμός'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, DictionaryImportMode.replace),
            child: const Text('Αντικατάσταση'),
          ),
        ],
      ),
    );
    if (mode == null || !context.mounted) return;
    if (mode == DictionaryImportMode.replace) {
      final existing = await DictionaryRepository(
        await DatabaseHelper.instance.database,
      ).countFullDictionaryTotal();
      final lines = await File(path).readAsLines();
      var newCount = 0;
      for (final line in lines) {
        final t = line.trim();
        if (t.isNotEmpty && !t.startsWith('#')) newCount++;
      }
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Αντικατάσταση'),
          content: Text(
            'Πρόκειται να αντικαταστήσετε $existing λέξεις με $newCount νέες. Να γίνει η αντικατάσταση;',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Άκυρο'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Συνέχεια'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await _master.importFromTxtFile(path, mode);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Εισαγωγή αρχείου ολοκληρώθηκε')),
        );
        await host.refreshList();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Σφάλμα: ${humanizeUserFacingError(e)}')),
        );
      }
    }
  }

  Future<void> compileExport() async {
    try {
      await _master.compileExportToTxt();
      ref.invalidate(coreLexiconProvider);
      ref.invalidate(spellCheckServiceProvider);
      flushLexiconProviderChain(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Compile ολοκληρώθηκε. Αν χρησιμοποιείτε custom πηγή, βεβαιωθείτε ότι η διαδρομή πηγής δείχνει στο νέο αρχείο.',
            ),
          ),
        );
        await host.refreshList();
      }
    } on DictionaryExportPathMissingException catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ορίστε διαδρομή εξαγωγής (Compile).'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Σφάλμα Compile: ${humanizeUserFacingError(e)}'),
          ),
        );
      }
    }
  }

  Future<void> updateLexiconRow(
    Map<String, dynamic> row,
    String displayWord,
    String category,
  ) async {
    try {
      final written = await writer.update(row, displayWord, category);
      if (written == null || !context.mounted) return;
      host.patchLexiconRowLocally(
        entryId: row['entry_id'] as int?,
        oldNormKey: row['norm_key'] as String? ?? '',
        displayWord: displayWord,
        category: category,
        written: written,
      );
    } catch (e) {
      if (context.mounted) {
        final msg = humanizeUserFacingError(e);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
      // Propagate so [DictionaryGridRow] can revert the word field and category UI.
      rethrow;
    }
  }

  Future<void> deleteRow(Map<String, dynamic> row) async {
    final entryId = row['entry_id'] as int?;
    final normKey = row['norm_key'] as String? ?? '';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή'),
        content: Text('Διαγραφή «${row['display_word']}»;'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await writer.delete(row);
      if (!context.mounted) return;
      host.removeLexiconRowLocally(entryId: entryId, normKey: normKey);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Σφάλμα: ${humanizeUserFacingError(e)}')),
        );
      }
    }
  }
}
