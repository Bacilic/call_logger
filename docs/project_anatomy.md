# Call Logger — Project Anatomy

**Ημερομηνία τροποποίησης εγγράφου:** 19 Απριλίου 2026

Συμπυκνωμένη «ακτινογραφία» για εξωτερικό LLM (Καθοδηγητής): Flutter για Windows 11, δομή ανά features/, Riverpod, SQLite μέσω sqflite_common_ffi.

---

## 1) DIRTREE (lib/)

Πλήρης λίστα αρχείων `.dart` (και `.gitkeep` όπου υπάρχουν) μέχρι τις επωνυμίες υποφακέλων· οι φάκελοι `core/debug/` και `lib/tool/` είναι κενοί placeholders και παραλείπονται.

```
lib/
├── main.dart
├── core/
│   ├── config/
│   │   ├── app_config.dart
│   │   └── audit_retention_config.dart
│   ├── database/
│   │   ├── calls_repository.dart
│   │   ├── database_access_probe.dart
│   │   ├── database_helper.dart
│   │   ├── database_init_progress_provider.dart
│   │   ├── database_init_result.dart
│   │   ├── database_init_runner.dart
│   │   ├── database_path_pick_flow.dart
│   │   ├── database_path_resolution.dart
│   │   ├── database_v1_schema.dart
│   │   ├── dictionary_repository.dart
│   │   ├── directory_audit_helpers.dart
│   │   ├── directory_repository.dart
│   │   ├── lock_diagnostic_service.dart
│   │   └── remote_tools_repository.dart
│   ├── errors/
│   │   ├── department_exists_exception.dart
│   │   └── dictionary_export_exception.dart
│   ├── init/
│   │   ├── app_init_provider.dart
│   │   └── app_initializer.dart
│   ├── models/
│   │   ├── building_map_floor.dart
│   │   ├── calls_screen_cards_visibility.dart
│   │   ├── dictionary_import_mode.dart
│   │   ├── remote_tool.dart
│   │   ├── remote_tool_arg.dart
│   │   └── remote_tool_role.dart
│   ├── providers/
│   │   ├── directory_tab_intent_provider.dart
│   │   ├── equipment_focus_intent_provider.dart
│   │   ├── greek_dictionary_provider.dart
│   │   ├── history_audit_immersive_provider.dart
│   │   ├── lexicon_categories_provider.dart
│   │   ├── lexicon_full_mode_provider.dart
│   │   ├── lexicon_language_recalc_provider.dart
│   │   ├── main_nav_request_provider.dart
│   │   ├── settings_provider.dart
│   │   ├── shell_navigation_intent_provider.dart
│   │   ├── spell_check_provider.dart
│   │   ├── task_focus_intent_provider.dart
│   │   └── user_form_edit_intent_provider.dart
│   ├── services/
│   │   ├── audit_retention_runner.dart
│   │   ├── audit_service.dart
│   │   ├── building_map_storage.dart
│   │   ├── default_remote_tool_display.dart
│   │   ├── dictionary_service.dart
│   │   ├── excel_parser.dart
│   │   ├── import_service.dart
│   │   ├── import_types.dart
│   │   ├── lookup_service.dart
│   │   ├── master_dictionary_service.dart
│   │   ├── remote_args_service.dart
│   │   ├── remote_connection_service.dart
│   │   ├── remote_launcher_service.dart
│   │   ├── remote_tools_paths_helper.dart
│   │   ├── settings_service.dart
│   │   └── spell_check_service.dart
│   ├── theme/
│   │   └── .gitkeep
│   ├── utils/
│   │   ├── date_parser_util.dart
│   │   ├── department_display_utils.dart
│   │   ├── file_picker_initial_directory.dart
│   │   ├── lexicon_word_metrics.dart
│   │   ├── name_parser.dart
│   │   ├── phone_list_parser.dart
│   │   ├── search_text_normalizer.dart
│   │   ├── spell_check.dart
│   │   └── user_identity_normalizer.dart
│   └── widgets/
│       ├── .gitkeep
│       ├── app_init_wrapper.dart
│       ├── app_shell_with_global_fatal_error.dart
│       ├── app_shortcuts.dart
│       ├── calendar_range_picker.dart
│       ├── database_error_screen.dart
│       ├── database_persistence_error_snackbar.dart
│       ├── global_fatal_error_notifier.dart
│       ├── lexicon_spell_menu_helper.dart
│       ├── lexicon_spell_text_form_field.dart
│       ├── main_nav_destination.dart
│       ├── main_shell.dart
│       └── spell_check_controller.dart
├── features/
│   ├── audit/
│   │   ├── audit.dart
│   │   ├── constants/
│   │   │   └── audit_ui_mappings.dart
│   │   ├── models/
│   │   │   ├── audit_filter_model.dart
│   │   │   ├── audit_log_model.dart
│   │   │   └── audit_page_result.dart
│   │   ├── providers/
│   │   │   └── audit_providers.dart
│   │   └── services/
│   │       ├── audit_entity_preview_resolver.dart
│   │       └── audit_formatter_service.dart
│   ├── calls/
│   │   ├── models/
│   │   │   ├── .gitkeep
│   │   │   ├── call_model.dart
│   │   │   ├── equipment_model.dart
│   │   │   └── user_model.dart
│   │   ├── provider/
│   │   │   ├── .gitkeep
│   │   │   ├── call_entry_provider.dart
│   │   │   ├── call_header_provider.dart
│   │   │   ├── calls_dashboard_providers.dart
│   │   │   ├── import_log_provider.dart
│   │   │   ├── lookup_provider.dart
│   │   │   ├── notes_field_hint_provider.dart
│   │   │   ├── remote_paths_provider.dart
│   │   │   └── smart_entity_selector_provider.dart
│   │   ├── screens/
│   │   │   ├── .gitkeep
│   │   │   ├── calls_screen.dart
│   │   │   └── widgets/
│   │   │       ├── call_header_form.dart
│   │   │       ├── call_status_bar.dart
│   │   │       ├── category_autocomplete_field.dart
│   │   │       ├── equipment_info_card.dart
│   │   │       ├── equipment_recent_calls_panel.dart
│   │   │       ├── global_recent_calls_list.dart
│   │   │       ├── import_console_widget.dart
│   │   │       ├── notes_sticky_field.dart
│   │   │       ├── recent_calls_list.dart
│   │   │       ├── remote_connection_buttons.dart
│   │   │       ├── smart_entity_selector_caller_presentational.dart
│   │   │       ├── smart_entity_selector_phone_presentational.dart
│   │   │       ├── smart_entity_selector_widget.dart
│   │   │       ├── sticky_note_widget.dart
│   │   │       └── user_info_card.dart
│   │   └── utils/
│   │       ├── call_remote_targets.dart
│   │       ├── equipment_remote_param_key.dart
│   │       ├── remote_target_rules.dart
│   │       └── vnc_remote_target.dart
│   ├── database/
│   │   ├── models/
│   │   │   ├── database_backup_settings.dart
│   │   │   └── database_stats.dart
│   │   ├── providers/
│   │   │   ├── backup_scheduler_provider.dart
│   │   │   ├── database_backup_settings_provider.dart
│   │   │   ├── database_browser_stats_provider.dart
│   │   │   └── database_maintenance_provider.dart
│   │   ├── screens/
│   │   │   └── database_browser_screen.dart
│   │   ├── services/
│   │   │   ├── database_backup_service.dart
│   │   │   ├── database_exit_backup.dart
│   │   │   ├── database_maintenance_service.dart
│   │   │   └── database_stats_service.dart
│   │   ├── utils/
│   │   │   ├── backup_destination_folder_validator.dart
│   │   │   ├── backup_destination_location_warnings.dart
│   │   │   ├── backup_location_hints.dart
│   │   │   └── backup_schedule_utils.dart
│   │   └── widgets/
│   │       ├── database_maintenance_panel.dart
│   │       ├── database_rename_failure_dialog.dart
│   │       └── database_settings_panel.dart
│   ├── dictionary/
│   │   ├── dictionary_table_layout.dart
│   │   ├── providers/
│   │   │   └── lexicon_scroll_provider.dart
│   │   ├── screens/
│   │   │   └── dictionary_manager_screen.dart
│   │   └── widgets/
│   │       ├── dictionary_grid_row.dart
│   │       └── dictionary_settings_dialog.dart
│   ├── directory/
│   │   ├── building_map/
│   │   │   ├── building_map_geometry.dart
│   │   │   ├── providers/
│   │   │   │   └── building_map_providers.dart
│   │   │   ├── screens/
│   │   │   │   └── building_map_dialog.dart
│   │   │   └── widgets/
│   │   │       └── building_map_sheet_painter.dart
│   │   ├── models/
│   │   │   ├── .gitkeep
│   │   │   ├── category_directory_column.dart
│   │   │   ├── category_model.dart
│   │   │   ├── department_directory_column.dart
│   │   │   ├── department_model.dart
│   │   │   ├── equipment_column.dart
│   │   │   ├── non_user_phone_entry.dart
│   │   │   ├── user_catalog_mode.dart
│   │   │   └── user_directory_column.dart
│   │   ├── providers/
│   │   │   ├── category_directory_provider.dart
│   │   │   ├── department_directory_provider.dart
│   │   │   ├── directory_provider.dart
│   │   │   └── equipment_directory_provider.dart
│   │   └── screens/
│   │       ├── .gitkeep
│   │       ├── directory_screen.dart
│   │       └── widgets/
│   │           ├── bulk_department_edit_dialog.dart
│   │           ├── bulk_equipment_edit_dialog.dart
│   │           ├── bulk_user_edit_dialog.dart
│   │           ├── catalog_column_selector_shell.dart
│   │           ├── categories_data_table.dart
│   │           ├── categories_tab.dart
│   │           ├── category_form_dialog.dart
│   │           ├── category_undo_snackbar.dart
│   │           ├── department_color_palette.dart
│   │           ├── department_form_dialog.dart
│   │           ├── department_transfer_confirm_dialog.dart
│   │           ├── departments_data_table.dart
│   │           ├── departments_tab.dart
│   │           ├── equipment_data_table.dart
│   │           ├── equipment_form_dialog.dart
│   │           ├── equipment_settings_dialog.dart
│   │           ├── equipment_tab.dart
│   │           ├── homonym_warning_dialog.dart
│   │           ├── miscellaneous_tab.dart
│   │           ├── non_user_phones_data_table.dart
│   │           ├── user_form_dialog.dart
│   │           ├── user_form_smart_text_field.dart
│   │           ├── user_name_change_confirm_dialog.dart
│   │           ├── users_data_table.dart
│   │           └── users_tab.dart
│   ├── history/
│   │   ├── models/
│   │   │   ├── dashboard_filter_model.dart
│   │   │   └── dashboard_summary_model.dart
│   │   ├── providers/
│   │   │   ├── dashboard_provider.dart
│   │   │   ├── history_application_audit_view_provider.dart
│   │   │   └── history_provider.dart
│   │   ├── screens/
│   │   │   ├── dashboard_screen.dart
│   │   │   └── history_screen.dart
│   │   └── widgets/
│   │       ├── application_audit_tab.dart
│   │       ├── audit_before_after_section.dart
│   │       ├── audit_entity_side_panel.dart
│   │       └── audit_entity_previews/
│   │           ├── audit_entity_preview_body.dart
│   │           ├── audit_preview_column.dart
│   │           ├── backup_preview_widget.dart
│   │           ├── call_preview_widget.dart
│   │           ├── equipment_preview_widget.dart
│   │           ├── settings_preview_widget.dart
│   │           ├── task_preview_widget.dart
│   │           └── user_preview_widget.dart
│   ├── settings/
│   │   ├── screens/
│   │   │   ├── remote_tools_management_screen.dart
│   │   │   └── settings_screen.dart
│   │   └── widgets/
│   │       ├── create_new_database_dialog.dart
│   │       └── remote_tool_form_dialog.dart
│   └── tasks/
│       ├── models/
│       │   ├── .gitkeep
│       │   ├── task.dart
│       │   ├── task_filter.dart
│       │   └── task_settings_config.dart
│       ├── providers/
│       │   ├── pending_task_delete_provider.dart
│       │   ├── task_service_provider.dart
│       │   ├── task_settings_config_provider.dart
│       │   └── tasks_provider.dart
│       ├── screens/
│       │   ├── .gitkeep
│       │   ├── task_card.dart
│       │   ├── task_close_dialog.dart
│       │   ├── task_filter_bar.dart
│       │   ├── task_form_dialog.dart
│       │   ├── task_settings_dialog.dart
│       │   └── tasks_screen.dart
│       ├── services/
│       │   └── task_service.dart
│       └── ui/
│           └── task_due_option_tooltips.dart
```

---

## 2) DATABASE SCHEMA (SQLite)

Πηγή: `database_v1_schema.dart` (δημιουργία αρχικού σχήματος / migrations) και `database_helper.dart` (squashed `onCreate` / `onUpgrade`, user_version = σταθερά `databaseSchemaVersionV1`).

**Τρέχουσα έκδοση σχήματος (user_version):** 20 (`databaseSchemaVersionV1`).

**Πίνακες και στήλες (όνομα → τύπος SQLite)** — κατά την **νέα εγκατάσταση** (`applyDatabaseV1Schema`), χωρίς τις legacy στήλες που αφαιρούνται σε αναβάθμιση v19 σε παλιές βάσεις:

- **calls** — id INTEGER PK AUTOINCREMENT, date TEXT, time TEXT, caller_id INTEGER, equipment_id INTEGER, caller_text TEXT, phone_text TEXT, department_text TEXT, equipment_text TEXT, issue TEXT, solution TEXT, category_text TEXT, category_id INTEGER, status TEXT, duration INTEGER, is_priority INTEGER DEFAULT 0, search_index TEXT, is_deleted INTEGER DEFAULT 0  
- **users** — id INTEGER PK AUTOINCREMENT, last_name TEXT NOT NULL, first_name TEXT NOT NULL, department_id INTEGER, location TEXT, notes TEXT, is_deleted INTEGER DEFAULT 0  
- **phones** — id INTEGER PK AUTOINCREMENT, number TEXT UNIQUE NOT NULL, department_id INTEGER  
- **department_phones** — department_id INTEGER NOT NULL, phone_id INTEGER NOT NULL, PRIMARY KEY (department_id, phone_id)  
- **user_phones** — user_id INTEGER NOT NULL, phone_id INTEGER NOT NULL, PRIMARY KEY (user_id, phone_id)  
- **equipment** — id INTEGER PK AUTOINCREMENT, code_equipment TEXT, type TEXT, notes TEXT, custom_ip TEXT, anydesk_id TEXT, remote_params TEXT, default_remote_tool TEXT, department_id INTEGER, location TEXT, is_deleted INTEGER DEFAULT 0  
- **user_equipment** — user_id INTEGER NOT NULL, equipment_id INTEGER NOT NULL, PRIMARY KEY (user_id, equipment_id)  
- **departments** — id INTEGER PK AUTOINCREMENT, name TEXT NOT NULL, name_key TEXT UNIQUE NOT NULL, building TEXT, color TEXT DEFAULT '#1976D2', notes TEXT, map_floor TEXT, map_x REAL DEFAULT 0.0, map_y REAL DEFAULT 0.0, map_width REAL DEFAULT 0.0, map_height REAL DEFAULT 0.0, map_rotation REAL DEFAULT 0.0, is_deleted INTEGER DEFAULT 0  
- **building_map_floors** — id INTEGER PK AUTOINCREMENT, sort_order INTEGER NOT NULL DEFAULT 0, label TEXT NOT NULL, floor_group TEXT, image_path TEXT NOT NULL, rotation_degrees REAL NOT NULL DEFAULT 0  
- **categories** — id INTEGER PK AUTOINCREMENT, name TEXT, is_deleted INTEGER DEFAULT 0  
- **tasks** — id INTEGER PK AUTOINCREMENT, title TEXT, description TEXT, due_date TEXT, snooze_history_json TEXT, status TEXT, call_id INTEGER, priority INTEGER, solution_notes TEXT, snooze_until TEXT, caller_id INTEGER, equipment_id INTEGER, department_id INTEGER, phone_id INTEGER, phone_text TEXT, user_text TEXT, equipment_text TEXT, department_text TEXT, created_at TEXT, updated_at TEXT, search_index TEXT, is_deleted INTEGER DEFAULT 0  
- **knowledge_base** — id INTEGER PK AUTOINCREMENT, topic TEXT, content TEXT, tags TEXT  
- **audit_log** — id INTEGER PK AUTOINCREMENT, action TEXT, timestamp TEXT, user_performing TEXT, details TEXT, entity_type TEXT, entity_id INTEGER, entity_name TEXT, old_values_json TEXT, new_values_json TEXT  
  - Ευρετήρια: idx_audit_log_timestamp, idx_audit_log_action, idx_audit_log_entity_type_entity_id  
- **app_settings** — key TEXT PK, value TEXT  
- **remote_tools** — id INTEGER PK AUTOINCREMENT, name TEXT NOT NULL, role TEXT NOT NULL, executable_path TEXT NOT NULL, launch_mode TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, is_active INTEGER NOT NULL DEFAULT 1, suggested_values TEXT, icon_asset_key TEXT, arguments_json TEXT, test_target_ip TEXT, is_exclusive INTEGER NOT NULL DEFAULT 0, deleted_at TEXT  
  - Ευρετήριο: idx_remote_tools_role  
- **remote_tool_args** — id INTEGER PK AUTOINCREMENT, remote_tool_id INTEGER, tool_name TEXT, arg_flag TEXT, description TEXT, is_active INTEGER DEFAULT 0, FK(remote_tool_id → remote_tools.id)  
- **user_dictionary** — word TEXT PK, language TEXT, letters_count INTEGER NOT NULL DEFAULT 0, diacritic_mark_count INTEGER NOT NULL DEFAULT 0  
- **full_dictionary** — id INTEGER PK AUTOINCREMENT, word TEXT NOT NULL UNIQUE, normalized_word TEXT NOT NULL, source TEXT NOT NULL, language TEXT NOT NULL, category TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now')), letters_count INTEGER NOT NULL DEFAULT 0, diacritic_mark_count INTEGER NOT NULL DEFAULT 0  
  - Ευρετήρια: idx_full_dictionary_norm, idx_full_dictionary_filters, idx_full_dictionary_letters_count, idx_full_dictionary_diacritic_mark_count  

**Σημείωση:** Σε βάσεις που πέρασαν από παλαιότερες εκδόσεις, ο πίνακας `remote_tools` μπορεί ακόμα να περιέχει επιπλέον στήλες (π.χ. legacy πριν το v19)· το μοντέλο εφαρμογής τις αγνοεί όπου χρειάζεται.

---

## 3) MODELS

**features/calls/models/**

- **CallModel** — id, date, time, callerId, equipmentId, callerText, phoneText, departmentText, equipmentText, issue, solution, category, categoryId, status, duration, isPriority, isDeleted  
- **UserModel** — id, firstName, lastName, phones, departmentId, location, notes, isDeleted (υπολογιζόμενα: phoneJoined, name, departmentName, fullNameWithDepartment)  
- **EquipmentModel** — id, code, type, notes, customIp, anydeskId, remoteParams, defaultRemoteTool, departmentId, location, isDeleted  

**features/directory/models/**

- **DepartmentModel** — id, name, building, color, notes, mapFloor, mapX, mapY, mapWidth, mapHeight, mapRotation, directPhones, isDeleted  
- **CategoryModel** — id, name  
- **NonUserPhoneEntry** — phoneId, number, departmentNamesDisplay, primaryDepartmentId  
- **UserCatalogMode** (enum) — personal, shared  
- **DepartmentDirectoryColumn / UserDirectoryColumn / CategoryDirectoryColumn** — στατικοί ορισμοί στηλών UI (key, label, sortKey)  
- **equipment_column.dart** — τύπος γραμμής EquipmentRow (tuple εξοπλισμός + κάτοχος), κλάση EquipmentColumn (στήλες πίνακα με display/sort lambdas), βοηθητική μορφοποίηση τοποθεσίας  

**features/tasks/models/**

- **Task** — id, callId, callerId, equipmentId, departmentId, phoneId, phoneText, userText, equipmentText, departmentText, title, description, dueDate, snoozeUntil, snoozeHistoryJson, status, priority, solutionNotes, createdAt, updatedAt, isDeleted · εσωτερικά **TaskSnoozeEntry** (snoozedAt, dueAt) για ιστορικό αναβολών  
- **TaskStatus** (enum) — open, snoozed, closed  
- **TaskFilter** — searchQuery, statuses, startDate, endDate, sortBy, sortAscending  
- **TaskSortOption** (enum) — createdAt, dueAt, priority, department, user, equipment  
- **TaskSettingsConfig** — dayEndTime, nextBusinessHour, skipWeekends, defaultSnoozeOption, maxSnoozeDays, autoCloseQuickAdds  

**features/database/models/**

- **DatabaseStats** — fileSizeBytes, dbPath, lastBackupTime, rowCountsByTable  
- **DatabaseBackupSettings** — destinationDirectory, namingFormat, zipOutput, backupOnExit, interval, backupDays, backupTime, lastBackupAttempt, lastBackupStatus, retentionMaxCopiesEnabled, retentionMaxCopies, retentionMaxAgeEnabled, retentionMaxAgeDays  
- **DatabaseBackupNamingFormat / DatabaseBackupInterval** (enum)  

**features/audit/models/**

- **AuditLogModel** — id, action, timestamp, userPerforming, details, entityType, entityId, entityName, oldValuesJson, newValuesJson  
- **AuditFilterModel** — keyword, action, entityType, dateFrom, dateTo  
- **AuditPageResult** — items, totalCount  

**features/history/models/**

- **DashboardFilterModel** — keyword, dateFrom, dateTo, department, userName, equipmentCode, topN  
- **DashboardSummaryModel** — totalCalls, totalDurationSeconds, avgDurationSeconds, KPIs προηγούμενης περιόδου, dailyTrend, sparklineLast7Days, topCallers, longestCalls, hourlyDistribution, byDepartment, byIssue · βοηθητικοί τύποι: **DepartmentStat**, **IssueStat**, **DailyTrendPoint**, **CallerStat**, **LongestCallEntry**, **HourlyBucket**  

**core/models/**

- **BuildingMapFloor** — id, sortOrder, label, floorGroup, imagePath, rotationDegrees  
- **RemoteToolArgument** — value, description, isActive  
- **RemoteTool** — id, name, role, executablePath, launchMode, sortOrder, isActive, deletedAt, suggestedValuesJson, iconAssetKey, arguments (λίστα RemoteToolArgument από JSON), testTargetIp, isExclusive  
- **RemoteToolArg** — id, remoteToolId, toolName, argFlag, description, isActive (legacy αντιστοιχία πίνακα remote_tool_args)  
- **ToolRole** (enum) — vnc, rdp, anydesk, generic  
- **DictionaryImportMode** (enum) — enrich, replace  
- **CallsScreenCardsVisibility** — showUserCard, showEquipmentCard, showEmployeeRecentCard, showEquipmentRecentPanel, showGlobalRecentCard  

---

## 4) STATE MANAGEMENT — PROVIDERS (Riverpod)

Σύνοψη βασικών providers (όνομα + ρόλος):

- **appInitProvider** — αρχικοποίηση εφαρμογής (βάση, ρυθμίσεις, προγραμματισμένα backups).  
- **databaseInitProgressProvider** — βήματα/μηνύματα κατά το άνοιγμα βάσης.  
- **lookupServiceProvider** — φόρτωση in-memory cache χρηστών/τμημάτων/τηλεφώνων/εξοπλισμού για γρήγορα lookups.  
- **directoryProvider / departmentDirectoryProvider / categoryDirectoryProvider / equipmentDirectoryProvider** — κατάσταση καταλόγου (CRUD λίστες, soft delete, undo).  
- **buildingMapDirectoryRepositoryProvider** — lazy `DirectoryRepository` για την οθόνη χάρτη κτιρίου.  
- **buildingMapSelectedSheetIdProvider** — επιλεγμένο id φύλλου κατόψης (`building_map_floors`).  
- **buildingMapSelectedDepartmentIdToMapProvider** — επιλεγμένο τμήμα για σχεδίαση στο χάρτη.  
- **buildingMapToolProvider** — ενεργό εργαλείο χάρτη (Select / Draw / Edit).  
- **buildingMapDraftShapeProvider** — προσωρινό ορθογώνιο τμήματος πάνω στην εικόνα.  
- **buildingMapUndoProvider** — ένα βήμα αναίρεσης τελευταίας γεωμετρίας τμήματος στο χάρτη.  
- **Προβολή vs επεξεργασία χάρτη** — τοπική κατάσταση στο widget `BuildingMapDialog` (`_isEditingMode`), όχι ξεχωριστό Riverpod provider.  
- **callSmartEntityProvider / taskSmartEntityProvider** — επιλογή καλούντα/εξοπλισμού στη φόρμα κλήσεων και σε εκκρεμότητες.  
- **callHeaderProvider** — alias προς callSmartEntityProvider.  
- **callEntryProvider** — κατάσταση ενεργής κλήσης (σημειώσεις, χρονόμετρο, αποστολή κλήσης).  
- **recentCallsProvider / recentCallsByEquipmentProvider / globalRecentCallsProvider / showGlobalCallsToggleProvider** — πρόσφατες κλήσεις και εναλλαγές UI.  
- **importLogProvider** — καταγραφή μηνυμάτων εισαγωγής.  
- **tasksProvider / taskFilterProvider / taskStatusCountsProvider / globalPendingTasksCountProvider / orphanCallsProvider** — λίστα εκκρεμοτήτων, φίλτρα, μετρητές, ορφανές κλήσεις.  
- **taskSettingsConfigProvider / taskServiceProvider / pendingTaskDeleteProvider** — ρυθμίσεις snooze/ωραρίου, υπηρεσία εργασιών, εκκρεμής διαγραφής.  
- **historyFilterProvider / historyCallsProvider / historyCategoriesProvider / historyCategoryEntriesProvider** — φίλτρα και δεδομένα ιστορικού κλήσεων.  
- **historyTableZoomProvider** (στο history_screen) — επίπεδο zoom πίνακα ιστορικού.  
- **historyApplicationAuditViewProvider / historyAuditImmersiveProvider** — εναλλαγή προβολής audit στο ιστορικό.  
- **dashboardFilterProvider / dashboardStatsProvider / dashboardDepartmentsProvider** — φίλτρα και δεδομένα οθόνης στατιστικών (ιστορικό).  
- **auditServiceAsyncProvider / auditFormatterServiceProvider / auditFilterProvider / auditPageIndexProvider / auditListProvider / selectedAuditEntryIdProvider / auditSidePanelOpenProvider / auditEntityPreviewProvider** — λίστα και φίλτρα audit log.  
- **databaseBackupSettingsProvider / backupSchedulerProvider / databaseMaintenanceServiceProvider / databaseBrowserStatsProvider** — backups, χρονοδιάγραμμα, συντήρηση, στατιστικά browser πινάκων.  
- **remoteArgsServiceProvider / remoteToolsRepositoryProvider / remoteToolsCatalogProvider / remoteToolsAllCatalogProvider / remoteToolFormPairsProvider / remotePathsProvider / validRemoteToolPathsByIdProvider / validRemotePathsProvider / remoteLauncherStatusesByIdProvider / remoteLauncherStatusProvider / remoteConnectionServiceProvider / remoteLauncherServiceProvider / callsRemoteUiConfigProvider** — εργαλεία και διαδρομές απομακρυσμένης σύνδεσης.  
- **settings_provider** (πολλαπλά): showActiveTimerProvider, showTasksBadgeProvider, enableSpellCheckProvider, showDatabaseNavProvider, showDictionaryNavProvider, callsScreenCardsVisibilityProvider.  
- **shellNavigationIntentProvider / mainNavRequestProvider / directoryTabIntentProvider / taskFocusIntentProvider / equipmentFocusIntentProvider / userFormEditIntentProvider** — πλοήγηση και εστίαση από shortcuts ή intents.  
- **greekDictionaryServiceProvider / spellCheckServiceProvider / lexiconCategoriesProvider / lexiconFullModeProvider / lexiconLanguageRecalcProvider / lexiconMasterDataRevisionProvider** — λεξικό και ορθογραφία.  
- **lexiconContinuousScrollProvider / lexiconPageSizeProvider** — συμπεριφορά κύλισης/σελίδας σε λίστες λεξικού.  
- **catalogEquipmentContinuousScrollProvider / catalogUsersContinuousScrollProvider / catalogDepartmentsContinuousScrollProvider** — συνεχής κύλιση vs σελίδα ανά πίνακα καταλόγου.  
- **databaseBrowserZoomByTableProvider** (οθόνη browser) — zoom ανά πίνακα.  
- **notesFieldHintTickProvider** — tick για υποδείξεις πεδίου σημειώσεων.  

---

## 5) DEPENDENCIES (pubspec.yaml)

**dependencies**

- flutter (sdk)  
- flutter_localizations (sdk)  
- cupertino_icons: ^1.0.8  
- flutter_riverpod: ^3.2.1  
- sqflite_common: ^2.5.6  
- sqflite_common_ffi: ^2.3.3  
- sqlite3_flutter_libs: ^0.6.0  
- path_provider: ^2.1.2  
- path: ^1.9.0  
- google_fonts: ^8.0.2  
- intl: ^0.20.2  
- characters: ^1.4.0  
- window_manager: ^0.5.1  
- screen_retriever: ^0.2.0  
- shared_preferences: ^2.3.3  
- url_launcher: ^6.3.0  
- excel: ^4.0.6  
- file_picker: ^8.0.0  
- fl_chart: ^1.1.1  
- archive: ^3.6.1  
- win32: ^5.15.0  
- ffi: ^2.2.0  

**dev_dependencies**

- flutter_test (sdk)  
- integration_test (sdk)  
- riverpod: ^3.2.1  
- flutter_lints: ^6.0.0  

---

*Τέλος εγγράφου — ενημερώστε την ημερομηνία όταν αλλάζει ουσιαστικά το σχήμα ή η δομή.*
