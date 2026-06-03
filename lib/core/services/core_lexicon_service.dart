import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../config/app_config.dart';
import '../utils/bundled_dictionary_assets.dart';
import 'core_lexicon_validation.dart';
import 'dictionary_service.dart';
import 'settings_service.dart';

/// Κατάσταση λεξικού-πυρήνα στη μνήμη.
class CoreLexiconState {
  const CoreLexiconState({
    this.loaded = false,
    this.path,
    this.wordCount = 0,
    this.lastError,
  });

  final bool loaded;
  final String? path;
  final int wordCount;
  final String? lastError;

  static const unloaded = CoreLexiconState();
}

/// Φόρτωση / εγκατάσταση λεξικού-πυρήνα από δίσκο ή bundled assets.
class CoreLexiconService {
  CoreLexiconService._();

  static final CoreLexiconService instance = CoreLexiconService._();

  CoreLexiconState state = CoreLexiconState.unloaded;
  DictionaryService? dictionaryService;

  /// Σιωπηλή φόρτωση από αποθηκευμένη διαδρομή (εκκίνηση / μετά rollback).
  Future<bool> bootstrapFromSavedPath() async {
    final saved = await SettingsService().getDictionarySourcePath();
    if (saved == null || saved.trim().isEmpty) {
      _clearMemory();
      return false;
    }
    return loadFromDiskPath(saved.trim(), persistPath: false);
  }

  Future<bool> loadFromDiskPath(
    String path, {
    bool persistPath = true,
  }) async {
    final error = await validateCoreDictionaryFile(path);
    if (error != null) {
      _clearMemory();
      state = CoreLexiconState(lastError: error);
      return false;
    }
    final dict = DictionaryService();
    try {
      await dict.loadFromFile(path);
    } catch (e) {
      _clearMemory();
      state = CoreLexiconState(lastError: e.toString());
      return false;
    }
    if (persistPath) {
      await SettingsService().setDictionarySourcePath(path);
    }
    dictionaryService = dict;
    state = CoreLexiconState(
      loaded: true,
      path: path,
      wordCount: dict.wordCount,
    );
    return true;
  }

  Future<bool> installFromBundledAsset(String assetPath) async {
    try {
      final text = await rootBundle.loadString(assetPath);
      final dir = AppConfig.portableDictionariesDirectory;
      await Directory(dir).create(recursive: true);
      final target = p.normalize(p.join(dir, p.basename(assetPath)));
      await File(target).writeAsString(text, encoding: utf8);
      return loadFromDiskPath(target, persistPath: true);
    } catch (e) {
      state = CoreLexiconState(lastError: e.toString());
      return false;
    }
  }

  Future<bool> installFromExternalFile(String sourcePath) async {
    try {
      final error = await validateCoreDictionaryFile(sourcePath);
      if (error != null) {
        state = CoreLexiconState(lastError: error);
        return false;
      }
      final target = await copyFileToPortableDictionaries(sourcePath);
      return loadFromDiskPath(target, persistPath: true);
    } catch (e) {
      state = CoreLexiconState(lastError: e.toString());
      return false;
    }
  }

  Future<List<String>> listBundledTxtAssets() => listBundledDictionaryAssets();

  void unload() {
    _clearMemory();
  }

  void _clearMemory() {
    dictionaryService = null;
    state = CoreLexiconState.unloaded;
  }
}
