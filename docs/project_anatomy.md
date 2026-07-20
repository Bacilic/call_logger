# Call Logger — Project Anatomy

**Ημερομηνία τροποποίησης εγγράφου:** 20 Ιουλίου 2026

Συμπυκνωμένη «ακτινογραφία» για εξωτερικό LLM (Καθοδηγητής): Flutter για Windows 11, δομή ανά features/, Riverpod, SQLite μέσω sqflite_common_ffi.

---

## 1) DIRTREE (lib/)

```
lib/
├── main.dart
├── core/
│   ├── about/
│   │   ├── models/changelog_entry.dart
│   │   ├── providers/app_version_provider.dart
│   │   ├── providers/changelog_provider.dart
│   │   ├── services/changelog_service.dart
│   │   ├── version_display.dart
│   │   └── widgets/changelog_dialog.dart, version_chip.dart
│   ├── config/
│   │   ├── app_config.dart
│   │   ├── audit_retention_config.dart
│   │   └── calls_layout_config.dart
│   ├── database/
│   │   ├── audit_diff_helper.dart
│   │   ├── audit_service.dart
│   │   ├── backup_destination_hint.dart
│   │   ├── building_map_repository.dart
│   │   ├── calls_repository.dart + _dashboard / _deletion / _lansweeper / _search_index
│   │   ├── category_repository.dart
│   │   ├── database_access_probe.dart
│   │   ├── database_file_classifier.dart
│   │   ├── database_helper.dart  ← Singleton SQLite
│   │   ├── database_init_progress_provider.dart
│   │   ├── database_init_result.dart
│   │   ├── database_init_runner.dart
│   │   ├── database_integrity_diagnostics.dart
│   │   ├── database_lexicon_open_normalizations.dart
│   │   ├── database_lock_recovery.dart
│   │   ├── database_maintenance_repository.dart
│   │   ├── database_path_pick_flow.dart
│   │   ├── database_path_resolution.dart
│   │   ├── database_restore_flow.dart
│   │   ├── database_schema_migrations.dart
│   │   ├── database_table_inspection.dart
│   │   ├── database_v1_schema.dart  ← SQL DDL + migrations
│   │   ├── department_floor_migration.dart
│   │   ├── department_name_key_migration.dart
│   │   ├── department_repository.dart
│   │   ├── dictionary_repository.dart
│   │   ├── directory_audit_helpers.dart
│   │   ├── directory_support.dart
│   │   ├── equipment_repository.dart
│   │   ├── integrity_service.dart
│   │   ├── lamp_migration_service.dart
│   │   ├── lock_diagnostic_service.dart
│   │   ├── omnisearch_service.dart
│   │   ├── phone_repository.dart
│   │   ├── remote_tools_repository.dart
│   │   ├── settings_repository.dart
│   │   ├── sqlite_types.dart
│   │   ├── tasks_repository.dart
│   │   ├── user_delete_phone_policy.dart
│   │   ├── user_repository.dart
│   │   └── old_database/  ← LAMP legacy (lamp_database_provider, lamp_issue_*, old_database_schema κ.λπ.)
│   ├── directory/
│   │   └── phone_department_policy.dart
│   ├── errors/
│   │   ├── app_error_result.dart
│   │   ├── call_save_exception.dart
│   │   ├── department_exists_exception.dart
│   │   ├── dictionary_export_exception.dart
│   │   └── task_save_exception.dart
│   ├── init/
│   │   ├── app_init_provider.dart
│   │   ├── app_initializer.dart
│   │   └── database_reopen_cache_reset.dart
│   ├── models/
│   │   ├── building_map_floor.dart
│   │   ├── calls_screen_cards_visibility.dart
│   │   ├── dictionary_import_mode.dart
│   │   ├── remote_tool.dart
│   │   ├── remote_tool_arg.dart
│   │   ├── remote_tool_role.dart
│   │   └── window_placement_mode.dart
│   ├── providers/
│   │   ├── app_profile_provider.dart
│   │   ├── application_reset_provider.dart
│   │   ├── call_department_prefill_intent_provider.dart
│   │   ├── core_lexicon_provider.dart
│   │   ├── directory_tab_intent_provider.dart
│   │   ├── equipment_focus_intent_provider.dart
│   │   ├── greek_dictionary_provider.dart
│   │   ├── history_audit_immersive_provider.dart
│   │   ├── lamp_db_comparison_provider.dart
│   │   ├── lamp_excel_path_health_provider.dart
│   │   ├── lamp_open_settings_intent_provider.dart
│   │   ├── lamp_read_path_health_provider.dart
│   │   ├── lexicon_categories_provider.dart
│   │   ├── lexicon_full_mode_provider.dart
│   │   ├── lexicon_language_recalc_provider.dart
│   │   ├── main_nav_request_provider.dart
│   │   ├── quick_call_providers.dart
│   │   ├── settings_provider.dart
│   │   ├── shell_navigation_intent_provider.dart
│   │   ├── spell_check_provider.dart
│   │   ├── task_focus_intent_provider.dart
│   │   └── user_form_edit_intent_provider.dart
│   ├── services/
│   │   ├── ai_model_cooldown_registry.dart
│   │   ├── ai_prompt_template_controller.dart
│   │   ├── ai_ticket_suggestion_service.dart
│   │   ├── application_reset_service.dart
│   │   ├── audit_retention_runner.dart
│   │   ├── core_lexicon_service.dart
│   │   ├── crash_log_service.dart
│   │   ├── default_remote_tool_display.dart
│   │   ├── desktop_window_service.dart
│   │   ├── dictionary_service.dart
│   │   ├── gemini_runtime_settings.dart
│   │   ├── gemini_ticket_service.dart
│   │   ├── gemini_ticket_suggestion_service.dart
│   │   ├── lansweeper_agent_api_probe.dart
│   │   ├── lansweeper_sync_service.dart
│   │   ├── lookup_service.dart  ← in-memory cache χρηστών/εξοπλισμού
│   │   ├── master_dictionary_service.dart
│   │   ├── portable_lamp_storage.dart
│   │   ├── remote_args_service.dart
│   │   ├── remote_connection_service.dart
│   │   ├── remote_launcher_service.dart
│   │   ├── settings_service.dart  (+ _analytics_filters / _catalogs / _remote_lansweeper / _window_ui)
│   │   ├── shutdown_coordinator.dart
│   │   ├── shutdown_trace_service.dart
│   │   ├── spell_check_service.dart
│   │   └── spelling_lookup_gemini_service.dart
│   ├── updates/
│   │   ├── build_environment.dart
│   │   ├── network_folder_classifier.dart
│   │   ├── update_check_result.dart
│   │   ├── update_providers.dart
│   │   ├── update_service.dart
│   │   ├── update_source_config.dart
│   │   └── updater_script_builder.dart
│   ├── utils/
│   │   ├── date_parser_util.dart
│   │   ├── name_parser.dart
│   │   ├── phone_list_parser.dart
│   │   ├── search_text_normalizer.dart
│   │   └── (άλλα utils: autocomplete_highlight_scroll, department_display, homoglyph_text_normalizer κ.λπ.)
│   └── widgets/
│       ├── app_init_wrapper.dart
│       ├── app_shell_with_global_fatal_error.dart
│       ├── main_shell.dart
│       ├── quick_call_fab.dart
│       └── (άλλα κοινά widgets)
│
├── features/
│   ├── audit/
│   │   ├── models/  audit_filter_model, audit_log_model, audit_page_result, audit_reference_labels
│   │   ├── providers/audit_providers.dart
│   │   └── services/  audit_formatter_service, audit_reference_label_resolver, audit_entity_preview_resolver
│   ├── calls/
│   │   ├── layout/  calls_field_groups_provider, calls_layout_engine, calls_screen_layout κ.λπ.
│   │   ├── models/  call_model, equipment_model, user_model
│   │   ├── provider/  call_entry_provider, call_header_provider, calls_dashboard_providers,
│   │   │              lookup_provider, remote_paths_provider, smart_entity_selector_provider κ.λπ.
│   │   ├── screens/  calls_screen.dart
│   │   └── screens/widgets/  (call_header_form, smart_entity_selector_*, recent_calls_list κ.λπ.)
│   ├── database/
│   │   ├── models/  database_backup_settings, database_integrity_finding/report, database_stats, integrity_fix_models
│   │   ├── providers/  backup_scheduler, database_backup_settings, database_browser_stats,
│   │   │               database_integrity, database_maintenance
│   │   ├── services/  database_backup_service, database_exit_backup, database_integrity_service/fix_service,
│   │   │               database_maintenance_service, database_stats_service
│   │   └── utils/  backup_destination_folder_validator, backup_schedule_utils κ.λπ.
│   ├── dictionary/
│   │   ├── models/lexicon_list_filters_model.dart
│   │   ├── providers/  dictionary_layout, lexicon_list_filters, lexicon_scroll, lexicon_spelling_panel
│   │   └── screens/  dictionary_manager_screen.dart
│   ├── directory/
│   │   ├── building_map/  controllers, providers, screens, services, widgets
│   │   ├── models/  category_model, department_model, equipment_column, department_directory_column,
│   │   │            user_directory_column, category_directory_column, non_user_phone_entry, user_catalog_mode
│   │   ├── providers/  category_directory, department_directory, directory_provider, equipment_directory
│   │   └── screens/  directory_screen.dart + widgets/
│   ├── floor_map/
│   │   └── services/floor_color_assignment_service.dart
│   ├── history/
│   │   ├── models/  dashboard_date_preset, dashboard_filter_model, dashboard_summary_model,
│   │   │            lansweeper_connection_status, lansweeper_sync_state
│   │   ├── providers/  ai_ticket_suggestion, dashboard_provider, gemini_settings, history_provider,
│   │   │               lansweeper_connection_probe, lansweeper_settings, lansweeper_sync
│   │   ├── screens/  dashboard_screen, history_screen + dashboard_cards/charts/filter_pane
│   │   └── widgets/  call_edit_dialog, lansweeper/*, audit_entity_previews/*
│   ├── lamp/
│   │   ├── controllers/  lamp_import_controller, lamp_issue_resolution_controller κ.λπ.
│   │   ├── screens/lamp_screen.dart
│   │   ├── services/  lamp_migration_service, lamp_transfer_preview
│   │   └── widgets/  lamp_transfer_wizard_dialog, lamp_resolution_progress_dialog κ.λπ.
│   ├── settings/
│   │   ├── screens/  settings_screen, remote_tools_management_screen
│   │   └── widgets/  remote_tool_form/* (controller, dialog, saver, sort, test_panel)
│   └── tasks/
│       ├── models/  task, task_analytics_filter, task_analytics_summary, task_filter,
│       │            task_settings_config, task_analytics_date_preset
│       ├── providers/  pending_task_delete, task_analytics_date, task_analytics, task_service,
│       │               task_settings_config, tasks_provider
│       ├── screens/  tasks_screen, task_card, task_form_dialog, task_close_dialog, task_filter_bar
│       └── services/task_service.dart
```

---

## 2) DATABASE SCHEMA (SQLite)

**Τρέχουσα έκδοση σχήματος:** `databaseSchemaVersionV1 = 36`

| Πίνακας | Βασικές στήλες |
|---------|----------------|
| **calls** | id INTEGER PK, date TEXT, time TEXT, caller_id INTEGER, equipment_id INTEGER, caller_text TEXT, phone_text TEXT, department_text TEXT, equipment_text TEXT, issue TEXT, category_text TEXT, category_id INTEGER, status TEXT, duration INTEGER, is_priority INTEGER DEFAULT 0, search_index TEXT, lansweeper_state TEXT DEFAULT 'unsent', lansweeper_main_ticket_id TEXT, lansweeper_last_sync_at TEXT, is_deleted INTEGER DEFAULT 0 |
| **call_external_links** | id INTEGER PK, call_id INTEGER, external_id TEXT, provider TEXT, created_at TEXT, metadata TEXT |
| **users** | id INTEGER PK, last_name TEXT, first_name TEXT, department_id INTEGER, location TEXT, notes TEXT, is_deleted INTEGER DEFAULT 0 |
| **phones** | id INTEGER PK, number TEXT UNIQUE, department_id INTEGER, is_deleted INTEGER DEFAULT 0 |
| **department_phones** | department_id INTEGER, phone_id INTEGER (PK σύνθετο) |
| **user_phones** | user_id INTEGER, phone_id INTEGER (PK σύνθετο) |
| **equipment** | id INTEGER PK, code_equipment TEXT, type TEXT, notes TEXT, remote_params TEXT (JSON), default_remote_tool TEXT, department_id INTEGER, location TEXT, is_deleted INTEGER DEFAULT 0 |
| **user_equipment** | user_id INTEGER, equipment_id INTEGER (PK σύνθετο) |
| **departments** | id INTEGER PK, name TEXT, name_key TEXT UNIQUE, building TEXT, color TEXT DEFAULT '#1976D2', notes TEXT, map_floor TEXT, map_x/y/width/height/rotation REAL, map_label_offset_x/y REAL, map_anchor_offset_x/y REAL, map_custom_name TEXT, map_label_font_scale REAL, map_label_width REAL DEFAULT 150.0, map_label_height REAL DEFAULT 50.0, group_name TEXT, floor_id INTEGER, is_deleted INTEGER DEFAULT 0, map_hidden INTEGER DEFAULT 0 |
| **building_map_floors** | id INTEGER PK, sort_order INTEGER, label TEXT, floor_group TEXT, image_path TEXT, rotation_degrees REAL DEFAULT 0 |
| **categories** | id INTEGER PK, name TEXT, is_deleted INTEGER DEFAULT 0 |
| **tasks** | id INTEGER PK, title TEXT, description TEXT, due_date TEXT, snooze_history_json TEXT, status TEXT, call_id INTEGER, priority INTEGER, solution_notes TEXT, snooze_until TEXT, caller_id INTEGER, equipment_id INTEGER, department_id INTEGER, phone_id INTEGER, phone_text TEXT, user_text TEXT, equipment_text TEXT, department_text TEXT, created_at TEXT, updated_at TEXT, origin TEXT DEFAULT 'legacy', search_index TEXT, is_deleted INTEGER DEFAULT 0 |
| **knowledge_base** | id INTEGER PK, topic TEXT, content TEXT, tags TEXT |
| **audit_log** | id INTEGER PK, action TEXT, timestamp TEXT, user_performing TEXT, details TEXT, entity_type TEXT, entity_id INTEGER, entity_name TEXT, search_text TEXT, old_values_json TEXT, new_values_json TEXT |
| **app_settings** | key TEXT PK, value TEXT |
| **remote_tools** | id INTEGER PK, name TEXT, role TEXT, executable_path TEXT, sort_order INTEGER, is_active INTEGER, suggested_values TEXT, icon_asset_key TEXT, arguments_json TEXT, test_target_ip TEXT, is_exclusive INTEGER, deleted_at TEXT |
| **remote_tool_args** | id INTEGER PK, remote_tool_id INTEGER FK, tool_name TEXT, arg_flag TEXT, description TEXT, is_active INTEGER |
| **user_dictionary** | word TEXT PK, display_word TEXT, language TEXT, letters_count INTEGER, diacritic_mark_count INTEGER |
| **full_dictionary** | id INTEGER PK, word TEXT UNIQUE, normalized_word TEXT, source TEXT, language TEXT, category TEXT, created_at TEXT, letters_count INTEGER, diacritic_mark_count INTEGER |

---

## 3) MODELS

### Βήμα Α — Κατάλογοι `models/`

**`lib/features/calls/models/`**

- **CallModel** — Μοντέλο κλήσης: id, date, time, callerId, equipmentId, callerText, phoneText, departmentText, equipmentText, issue, category, categoryId, status, duration, isPriority, lansweeperState, lansweeperMainTicketId, lansweeperLastSyncAt, isDeleted, callerLinkedDeleted, equipmentLinkedDeleted.
- **UserModel** — Μοντέλο χρήστη: id, firstName, lastName, phones (List\<String\>), departmentId, location, notes, isDeleted. Computed: name, phoneJoined, fullNameWithDepartment.
- **EquipmentModel** — Μοντέλο εξοπλισμού: id, code, type, notes, remoteParams (Map\<String,String\>), defaultRemoteTool, departmentId, location, isDeleted. Computed: displayLabel, vncTargetResolved, rdpHostResolved, anydeskIdResolved.

**`lib/features/directory/models/`**

- **DepartmentModel** — id, name, building, color, notes, groupName, floorId, mapFloor, mapX/Y/Width/Height/Rotation, mapLabel*/mapAnchor* REAL, mapCustomName, mapLabelFontScale, mapLabelWidth/Height, directPhones, isDeleted, isHiddenOnMap.
- **CategoryModel** — id, name, isDeleted.
- **UserCatalogMode** (enum) — Λειτουργία εμφάνισης καταλόγου χρηστών.
- **NonUserPhoneEntry** — Εγγραφή τηλεφώνου χωρίς κάτοχο χρήστη.
- **UserDirectoryColumn** / **DepartmentDirectoryColumn** / **CategoryDirectoryColumn** / **DepartmentFloorDisplayExtension** — Στήλες πίνακα UI καταλόγου.
- **EquipmentColumn** — typedef `EquipmentRow = (EquipmentModel, UserModel?)` + helper συνάρτηση μορφοποίησης τοποθεσίας.

**`lib/features/audit/models/`**

- **AuditLogModel** — id, action, timestamp, userPerforming, details, entityType, entityId, entityName, oldValuesJson, newValuesJson. Computed: hasAnyDeltaJson, isTechnicalTableDetailsOnly, oldValuesMap, newValuesMap.
- **AuditFilterModel** — keyword, action, entityType, dateFrom, dateTo. Helpers: dateFromInclusiveIso, dateToExclusiveIso.
- **AuditPageResult** — items (List\<AuditLogModel\>), totalCount.
- **AuditReferenceLabels** — departmentNames (Map\<int,String\>), remoteToolNames (Map\<int,String\>). Μέθοδος: merge.

**`lib/features/history/models/`**

- **DashboardFilterModel** — Ενεργό φίλτρο dashboard (dateFrom, dateTo, departmentFilter, κ.λπ.).
- **DashboardSummaryModel** — Αποτέλεσμα συνάθροισης: totalCalls, totalDurationSeconds, departmentStats, issueStats, dailyTrends, callerStats, longestCalls, hourlyBuckets κ.λπ. Συνυπάρχοντες τύποι: `DepartmentStat`, `IssueStat`, `DailyTrendPoint`, `CallerStat`, `LongestCallEntry`, `HourlyBucket`, `KpiBarSparklinePoint`.
- **DashboardDatePreset** (enum) — Χρονικές προεπιλογές (σήμερα, εβδομάδα, μήνας κ.λπ.).
- **LansweeperConnectionStatus** / **LansweeperSyncState** — Κατάσταση σύνδεσης και συγχρονισμού Lansweeper.

**`lib/features/tasks/models/`**

- **Task** — id, callId, callerId, equipmentId, departmentId, phoneId, phoneText, userText, equipmentText, departmentText, title, description, dueDate, snoozeUntil, snoozeHistoryJson, status (TaskStatus), priority, solutionNotes, createdAt, updatedAt, origin, isDeleted + joined-deleted flags. Nested: `TaskSnoozeEntry` (από snoozeHistoryJson). Constants: originManualFab, originCallLinked, originQuickAdd, originLegacy.
- **TaskStatus** (enum) — open, snoozed, closed.
- **TaskFilter** — Φίλτρο λίστας εργασιών (status, keyword, dateFrom/To κ.λπ.).
- **TaskSettingsConfig** — Ρυθμίσεις εργασιών (snooze intervals, default due days κ.λπ.).
- **TaskAnalyticsFilter** / **TaskAnalyticsSummary** / **TaskAnalyticsDatePreset** — Δεδομένα analytics εκκρεμοτήτων.

**`lib/features/database/models/`**

- **DatabaseBackupSettings** — Ρυθμίσεις backup: enabled, targetFolder, scheduleInterval, keepCount κ.λπ.
- **DatabaseStats** — Στατιστικά πινάκων (αριθμός εγγραφών ανά πίνακα).
- **DatabaseIntegrityFinding** / **DatabaseIntegrityReport** — Ευρήματα ελέγχου ακεραιότητας.
- **IntegrityFixModels** — Βοηθητικά μοντέλα αποτελεσμάτων επιδιόρθωσης.

**`lib/features/dictionary/models/`**

- **LexiconListFiltersModel** — Φίλτρα εμφάνισης λεξικού (γλώσσα, πηγή, κατηγορία, κ.λπ.).

**`lib/core/models/`**

- **RemoteTool** — id, name, role (ToolRole), executablePath, sortOrder, isActive, suggestedValues, iconAssetKey, argumentsJson, testTargetIp, isExclusive, deletedAt.
- **RemoteToolArg** — id, remoteToolId, toolName, argFlag, description, isActive.
- **RemoteToolRole** (enum) — vnc, rdp, anydesk, generic.
- **BuildingMapFloor** — id, sortOrder, label, floorGroup, imagePath, rotationDegrees.
- **CallsScreenCardsVisibility** — Ορατότητα καρτών οθόνης κλήσεων.
- **DictionaryImportMode** (enum) — Λειτουργία εισαγωγής λεξικού.
- **WindowPlacementMode** (enum) — Τρόπος τοποθέτησης παραθύρου.

### Βήμα Β — Μοντέλα εκτός `models/`

- **HistoryFilterModel** (`lib/features/history/providers/history_provider.dart`) — Φίλτρα ιστορικού κλήσεων: keyword, dateFrom/To, category, status, departmentFilter, showDeleted.

### Βήμα Γ — Τύποι δεδομένων χωρίς επίθημα Model

| Τύπος | Αρχείο | Πεδία |
|-------|--------|-------|
| `DatabaseStatus` (enum) | `core/database/database_init_result.dart` | success, fileNotFound, accessDenied, corruptedOrInvalid, applicationError |
| `DatabaseInitResult` | `core/database/database_init_result.dart` | status, message, details, path, originalExceptionText, stackTraceText, technicalCode, recoveryKind |
| `DatabaseInitRecoveryKind` (enum) | ίδιο | wrongDatabaseLamp, wrongDatabaseUnknown, corruptedOrMigration, locked, timeout, generic |
| `DatabaseInitException` | ίδιο | result (DatabaseInitResult) |
| `AppInitResult` | `core/init/app_initializer.dart` | result (DatabaseInitResult), isLocalDevMode, spellCheckReady |
| `AuditRetentionConfig` | `core/config/audit_retention_config.dart` | Ρυθμίσεις διατήρησης audit log |
| `LookupResult` | `core/services/lookup_service.dart` | user (UserModel), equipment (List\<EquipmentModel\>) |
| `LookupLoadResult` | `features/calls/provider/lookup_provider.dart` | service (LookupService), loadError, loadErrorDetails |
| `ConnectionCheckResult` | `core/database/database_helper.dart` | success, isLocalDev |
| `TablePreviewResult` | `core/database/database_helper.dart` | columns (List\<String\>), rows (List\<Map\>) |
| `DatabaseInitProgressState` | `core/database/database_init_progress_provider.dart` | Βήμα και μήνυμα προόδου αρχικοποίησης |
| `CallEntryState` | `features/calls/provider/call_entry_provider.dart` | notes, category, categoryId, isPending, durationSeconds, isCallTimerRunning, retainPlayPauseAfterManualZero, isSubmitting |
| `SmartEntitySelectorState` | `features/calls/provider/smart_entity_selector_state.dart` | selectedPhone, selectedCaller, selectedEquipment, phoneCandidates, callerCandidates, equipmentCandidates, isPhoneAmbiguous, callerNoMatch, equipmentNoMatch, hasAnyContent, equipmentText, callerDisplayText, departmentText, selectedDepartmentId, conflicts |
| `SelectorField` (enum) | ίδιο | phone, caller, department, equipment |
| `ConflictSeverity` (enum) | ίδιο | mismatch, unknown |
| `FieldConflict` | ίδιο | severity, message |
| `OrphanQuickAddResult` | `features/calls/provider/smart_entity_selector_provider.dart` | Αποτέλεσμα γρήγορης προσθήκης ορφανής οντότητας |
| `DirectoryState` | `features/directory/providers/directory_provider.dart` | Κατάσταση καταλόγου (users, equipment, search, selectedTab) |
| `CategoryDirectoryState` | `features/directory/providers/category_directory_provider.dart` | Λίστα κατηγοριών + φίλτρο |
| `DepartmentDirectoryState` | `features/directory/providers/department_directory_provider.dart` | Λίστα τμημάτων + φίλτρο + ταξινόμηση |
| `EquipmentDirectoryState` | `features/directory/providers/equipment_directory_provider.dart` | Λίστα εξοπλισμού + φίλτρα |
| `EquipmentDeleteUndoEntry` | `features/directory/providers/equipment_directory_provider.dart` | Εγγραφή αναίρεσης διαγραφής εξοπλισμού |
| `BuildingMapFloorDeleteChoice` (enum) | `features/directory/building_map/controllers/building_map_controller.dart` | Επιλογή ενέργειας κατά διαγραφή ορόφου |
| `DatabaseBackupResult` | `features/database/services/database_backup_service.dart` | success, filePath, errorMessage, failureCode |
| `ReplaceDatabaseResult` | `features/database/services/database_maintenance_service.dart` | success, message, details |
| `BackupDestinationValidationResult` | `features/database/utils/backup_destination_folder_validator.dart` | Αποτέλεσμα ελέγχου φακέλου backup (kind, matchingFileCount, latestModified) |
| `TaskStatus` (enum) | `features/tasks/models/task.dart` | open, snoozed, closed |
| `GeminiTextModel` / `GeminiModelProbeResult` / `GeminiModelsQuotaProbeResult` / `GeminiModelsProbeCache` | `core/services/gemini_ticket_service.dart` | Μοντέλα Gemini API (αναγνωριστικά, quota, cache αποτελεσμάτων probe) |

---

## 4) STATE MANAGEMENT — PROVIDERS (Riverpod)

| Provider | Τύπος | Περιγραφή |
|----------|-------|-----------|
| `appInitProvider` | `FutureProvider<AppInitResult>` | Αρχικοποίηση εφαρμογής: άνοιγμα βάσης + bootstrap λεξικού |
| `lookupServiceProvider` | `FutureProvider<LookupLoadResult>` | In-memory cache χρηστών/εξοπλισμού για lookup < 50ms |
| `callEntryProvider` | `NotifierProvider<CallEntryNotifier, CallEntryState>` | Φόρμα εισαγωγής κλήσης (notes, κατηγορία, χρονόμετρο, submit) |
| `callSmartEntityProvider` / `taskSmartEntityProvider` / `historyEditSmartEntityProvider` | `NotifierProvider<SmartEntitySelectorNotifier, SmartEntitySelectorState>` | Επιλογέας οντοτήτων (τηλέφωνο→χρήστης→εξοπλισμός→τμήμα) |
| `directoryProvider` | `NotifierProvider<DirectoryNotifier, DirectoryState>` | Κατάλογος χρηστών/εξοπλισμού (CRUD + αναζήτηση + ταξινόμηση) |
| `departmentDirectoryProvider` | `NotifierProvider<DepartmentDirectoryNotifier, DepartmentDirectoryState>` | Κατάλογος τμημάτων με φίλτρα και αναζήτηση |
| `equipmentDirectoryProvider` | `NotifierProvider<EquipmentDirectoryNotifier, EquipmentDirectoryState>` | Κατάλογος εξοπλισμού με φίλτρα, undo διαγραφής |
| `categoryDirectoryProvider` | `NotifierProvider<CategoryDirectoryNotifier, CategoryDirectoryState>` | Κατάλογος κατηγοριών προβλημάτων |
| `tasksProvider` | `AsyncNotifierProvider<TasksNotifier, List<Task>>` | Λίστα εκκρεμοτήτων (CRUD, φίλτρα, ταξινόμηση) |
| `taskFilterProvider` | `NotifierProvider<TaskFilterNotifier, TaskFilter>` | Ενεργό φίλτρο οθόνης εκκρεμοτήτων |
| `historyFilterProvider` | `NotifierProvider<HistoryFilterNotifier, HistoryFilterModel>` | Ενεργό φίλτρο ιστορικού κλήσεων |
| `historyCallsProvider` | `FutureProvider.autoDispose` | Σελιδοποιημένη λίστα κλήσεων από DB με βάση τα φίλτρα |
| `dashboardFilterProvider` | `NotifierProvider.autoDispose<DashboardFilterNotifier, DashboardFilterModel>` | Φίλτρα dashboard (ημερομηνίες, τμήμα) |
| `dashboardStatsProvider` | `FutureProvider.autoDispose<DashboardSummaryModel>` | Στατιστικά dashboard (κλήσεις, τάσεις, κατανομές) |
| `auditFilterProvider` | `NotifierProvider<AuditFilterNotifier, AuditFilterModel>` | Φίλτρα ιστορικού εφαρμογής (audit log) |
| `auditListProvider` | `FutureProvider.autoDispose<AuditPageResult>` | Σελιδοποιημένο audit log με βάση τα φίλτρα |
| `databaseInitProgressProvider` | `NotifierProvider<DatabaseInitProgressNotifier, DatabaseInitProgressState>` | Πρόοδος αρχικοποίησης βάσης (για SplashScreen) |
| `databaseBackupSettingsProvider` | `NotifierProvider<DatabaseBackupSettingsNotifier, DatabaseBackupSettings>` | Ρυθμίσεις backup (φάκελος, χρονοδιάγραμμα) |
| `backupSchedulerProvider` | `NotifierProvider<BackupSchedulerNotifier, int>` | Αυτόματος χρονοπρογραμματιστής backup |
| `databaseIntegrityProvider` | `NotifierProvider<DatabaseIntegrityNotifier, DatabaseIntegrityState>` | Ελέγχος + επιδιόρθωση ακεραιότητας βάσης |
| `remoteToolsCatalogProvider` | `FutureProvider<List<RemoteTool>>` | Κατάλογος ενεργών εργαλείων απομακρυσμένης σύνδεσης |
| `coreLexiconProvider` | `NotifierProvider` | Κεντρικό λεξικό ορθογραφίας (πυρήνας) |
| `spellCheckServiceProvider` | `FutureProvider<LexiconSpellCheckService>` | Υπηρεσία ορθογραφικού ελέγχου |
| `buildingMapFloorsCatalogProvider` | `FutureProvider<List<BuildingMapFloor>>` | Κατάλογος ορόφων χάρτη κτιρίου |
| `buildingMapSelectedSheetIdProvider` | `NotifierProvider<_, int?>` | Ενεργό φύλλο κατόψης |
| `geminiPrimaryModelProvider` / `geminiFallbackModelProvider` | `NotifierProvider.autoDispose<_, String>` | Επιλεγμένα μοντέλα Gemini API |
| `lansweeperSyncProvider` | `AsyncNotifierProvider.autoDispose` | Χειροκίνητος/αυτόματος συγχρονισμός με Lansweeper |
| `lansweeperConnectionProbeProvider` | `NotifierProvider.autoDispose` | Έλεγχος σύνδεσης Lansweeper |
| `updateCheckProvider` | `FutureProvider<UpdateCheckResult>` | Έλεγχος διαθέσιμης ενημέρωσης από φάκελο δικτύου |
| `settingsProvider` (σύνολο) | `FutureProvider<bool>` × πολλαπλοί | UI preferences: showActiveTimer, showTasksBadge, enableSpellCheck, showDatabaseNav, showLampNav κ.λπ. |

---

## 5) DEPENDENCIES (pubspec.yaml)

**Έκδοση εφαρμογής:** `0.24.5+38`  
**SDK:** `^3.10.7`

### dependencies

| Πακέτο | Έκδοση |
|--------|--------|
| flutter_riverpod | ^3.3.1 |
| sqflite_common | ^2.5.11 |
| sqflite_common_ffi | ^2.4.2 |
| sqlite3_flutter_libs | ^0.6.0+eol |
| path_provider | ^2.1.2 |
| path | ^1.9.0 |
| google_fonts | ^8.1.0 |
| intl | ^0.20.2 |
| characters | ^1.4.0 |
| window_manager | ^0.5.1 |
| screen_retriever | ^0.2.0 |
| shared_preferences | ^2.5.5 |
| url_launcher | ^6.3.2 |
| http | ^1.2.0 |
| justkawal_excel_updated | ^5.0.0 |
| file_picker | ^12.0.0-beta.4 |
| fl_chart | ^1.2.0 |
| archive | ^4.0.9 |
| crypto | ^3.0.7 |
| win32 | ^6.3.0 |
| ffi | ^2.2.0 |
| custom_mouse_cursor | ^1.1.3 |
| package_info_plus | ^10.2.0 |
| image | ^4.9.1 |

### dev_dependencies

| Πακέτο | Έκδοση |
|--------|--------|
| flutter_lints | ^6.0.0 |
| riverpod | ^3.2.1 |
| leak_tracker_flutter_testing | ^3.0.10 |

---

*Τέλος εγγράφου — ενημερώστε την ημερομηνία όταν αλλάζει ουσιαστικά το σχήμα ή η δομή.*
