# Call Logger — Project Anatomy

**Ημερομηνία τροποποίησης εγγράφου:** 6 Απριλιου 2026

Συμπυκνωμένη «ακτινογραφία» για εξωτερικό LLM (Καθοδηγητής): Flutter για Windows 11, δομή ανά features/, Riverpod, SQLite μέσω sqflite_common_ffi.

---

## 1) DIRTREE (lib/)

```
lib/
├── main.dart
├── core/
│   ├── config/
│   │   └── app_config.dart
│   ├── database/
│   │   ├── database_helper.dart
│   │   ├── database_init_progress_provider.dart
│   │   ├── database_init_result.dart
│   │   ├── database_init_runner.dart
│   │   ├── database_path_pick_flow.dart
│   │   ├── database_path_resolution.dart
│   │   ├── database_v1_schema.dart
│   │   └── lock_diagnostic_service.dart
│   ├── errors/
│   │   ├── department_exists_exception.dart
│   │   └── dictionary_export_exception.dart
│   ├── init/
│   │   ├── app_init_provider.dart
│   │   └── app_initializer.dart
│   ├── models/
│   │   ├── dictionary_import_mode.dart
│   │   └── remote_tool_arg.dart
│   ├── providers/
│   │   ├── greek_dictionary_provider.dart
│   │   ├── lexicon_categories_provider.dart
│   │   ├── lexicon_full_mode_provider.dart
│   │   ├── lexicon_language_recalc_provider.dart
│   │   ├── settings_provider.dart
│   │   ├── shell_navigation_intent_provider.dart
│   │   └── spell_check_provider.dart
│   ├── services/
│   │   ├── dictionary_service.dart
│   │   ├── excel_parser.dart
│   │   ├── import_service.dart
│   │   ├── import_types.dart
│   │   ├── lookup_service.dart
│   │   ├── master_dictionary_service.dart
│   │   ├── remote_args_service.dart
│   │   ├── remote_connection_service.dart
│   │   ├── remote_launcher_service.dart
│   │   ├── settings_service.dart
│   │   └── spell_check_service.dart
│   ├── theme/
│   │   └── .gitkeep
│   ├── utils/
│   │   ├── date_parser_util.dart
│   │   ├── department_display_utils.dart
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
│       ├── global_fatal_error_notifier.dart
│       ├── lexicon_spell_text_form_field.dart
│       ├── main_nav_destination.dart
│       ├── main_shell.dart
│       └── spell_check_controller.dart
└── features/
    ├── calls/
    │   ├── models/
    │   │   ├── call_model.dart
    │   │   ├── equipment_model.dart
    │   │   └── user_model.dart
    │   ├── provider/
    │   │   ├── call_entry_provider.dart
    │   │   ├── call_header_provider.dart
    │   │   ├── import_log_provider.dart
    │   │   ├── lookup_provider.dart
    │   │   ├── notes_field_hint_provider.dart
    │   │   ├── remote_paths_provider.dart
    │   │   └── smart_entity_selector_provider.dart
    │   ├── screens/
    │   │   ├── calls_screen.dart
    │   │   └── widgets/
    │   │       ├── call_header_form.dart
    │   │       ├── call_status_bar.dart
    │   │       ├── category_autocomplete_field.dart
    │   │       ├── equipment_info_card.dart
    │   │       ├── import_console_widget.dart
    │   │       ├── notes_sticky_field.dart
    │   │       ├── recent_calls_list.dart
    │   │       ├── remote_connection_buttons.dart
    │   │       ├── smart_entity_selector_caller_presentational.dart
    │   │       ├── smart_entity_selector_phone_presentational.dart
    │   │       ├── smart_entity_selector_widget.dart
    │   │       ├── sticky_note_widget.dart
    │   │       └── user_info_card.dart
    │   └── utils/
    │       ├── remote_target_rules.dart
    │       └── vnc_remote_target.dart
    ├── database/
    │   ├── models/
    │   │   ├── database_backup_settings.dart
    │   │   └── database_stats.dart
    │   ├── providers/
    │   │   ├── backup_scheduler_provider.dart
    │   │   ├── database_backup_settings_provider.dart
    │   │   ├── database_browser_stats_provider.dart
    │   │   └── database_maintenance_provider.dart
    │   ├── screens/
    │   │   └── database_browser_screen.dart
    │   ├── services/
    │   │   ├── database_backup_service.dart
    │   │   ├── database_exit_backup.dart
    │   │   ├── database_maintenance_service.dart
    │   │   └── database_stats_service.dart
    │   ├── utils/
    │   │   ├── backup_destination_folder_validator.dart
    │   │   ├── backup_destination_location_warnings.dart
    │   │   ├── backup_location_hints.dart
    │   │   └── backup_schedule_utils.dart
    │   └── widgets/
    │       ├── database_maintenance_panel.dart
    │       ├── database_rename_failure_dialog.dart
    │       └── database_settings_panel.dart
    ├── dictionary/
    │   ├── dictionary_table_layout.dart
    │   ├── providers/
    │   │   └── lexicon_scroll_provider.dart
    │   ├── screens/
    │   │   └── dictionary_manager_screen.dart
    │   └── widgets/
    │       ├── dictionary_grid_row.dart
    │       └── dictionary_settings_dialog.dart
    ├── directory/
    │   ├── models/
    │   │   ├── category_directory_column.dart
    │   │   ├── category_model.dart
    │   │   ├── department_directory_column.dart
    │   │   ├── department_model.dart
    │   │   ├── equipment_column.dart
    │   │   └── user_directory_column.dart
    │   ├── providers/
    │   │   ├── category_directory_provider.dart
    │   │   ├── department_directory_provider.dart
    │   │   ├── directory_provider.dart
    │   │   └── equipment_directory_provider.dart
    │   ├── screens/
    │   │   ├── directory_screen.dart
    │   │   └── widgets/
    │   │       ├── bulk_department_edit_dialog.dart
    │   │       ├── bulk_equipment_edit_dialog.dart
    │   │       ├── bulk_user_edit_dialog.dart
    │   │       ├── catalog_column_selector_shell.dart
    │   │       ├── categories_data_table.dart
    │   │       ├── categories_tab.dart
    │   │       ├── category_form_dialog.dart
    │   │       ├── department_color_palette.dart
    │   │       ├── department_form_dialog.dart
    │   │       ├── department_transfer_confirm_dialog.dart
    │   │       ├── departments_data_table.dart
    │   │       ├── departments_tab.dart
    │   │       ├── equipment_data_table.dart
    │   │       ├── equipment_form_dialog.dart
    │   │       ├── equipment_tab.dart
    │   │       ├── homonym_warning_dialog.dart
    │   │       ├── user_form_dialog.dart
    │   │       ├── user_form_smart_text_field.dart
    │   │       ├── user_name_change_confirm_dialog.dart
    │   │       ├── users_data_table.dart
    │   │       └── users_tab.dart
    ├── history/
    │   ├── providers/
    │   │   └── history_provider.dart
    │   └── screens/
    │       └── history_screen.dart
    ├── settings/
    │   ├── screens/
    │   │   └── settings_screen.dart
    │   └── widgets/
    │       ├── create_new_database_dialog.dart
    │       └── remote_args_editor.dart
    └── tasks/
        ├── models/
        │   ├── task.dart
        │   ├── task_filter.dart
        │   └── task_settings_config.dart
        ├── providers/
        │   ├── pending_task_delete_provider.dart
        │   ├── task_service_provider.dart
        │   ├── task_settings_config_provider.dart
        │   └── tasks_provider.dart
        ├── screens/
        │   ├── task_card.dart
        │   ├── task_close_dialog.dart
        │   ├── task_filter_bar.dart
        │   ├── task_form_dialog.dart
        │   ├── task_settings_dialog.dart
        │   └── tasks_screen.dart
        ├── services/
        │   └── task_service.dart
        └── ui/
            └── task_due_option_tooltips.dart
```

---

## 2) DATABASE SCHEMA (SQLite)

**Τρέχουσα schema version:** `9` (`databaseSchemaVersionV1` στο `database_v1_schema.dart`).

Πίνακες και στήλες (τύπος SQLite όπως στο DDL του `applyDatabaseV1Schema` + σχόλια migrations όπου εφαρμόζονται μέσω `database_helper`):


| Πίνακας               | Στήλες                                                                                                                                                                                                                                                                                                |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **calls**             | id (INTEGER PK AUTOINCREMENT), date, time, caller_id, equipment_id, caller_text, phone_text, department_text, equipment_text, issue, solution, category_text, category_id, status, duration, is_priority, search_index, is_deleted                                                                    |
| **users**             | id (INTEGER PK AUTOINCREMENT), last_name, first_name, department_id, location, notes, is_deleted                                                                                                                                                                                                      |
| **phones**            | id (INTEGER PK AUTOINCREMENT), number (TEXT UNIQUE NOT NULL), department_id                                                                                                                                                                                                                           |
| **department_phones** | department_id (NOT NULL), phone_id (NOT NULL), PK (department_id, phone_id)                                                                                                                                                                                                                           |
| **user_phones**       | user_id (NOT NULL), phone_id (NOT NULL), PK (user_id, phone_id)                                                                                                                                                                                                                                       |
| **equipment**         | id (INTEGER PK AUTOINCREMENT), code_equipment, type, notes, custom_ip, anydesk_id, default_remote_tool, department_id, location, is_deleted                                                                                                                                                           |
| **user_equipment**    | user_id (NOT NULL), equipment_id (NOT NULL), PK (user_id, equipment_id)                                                                                                                                                                                                                               |
| **departments**       | id (INTEGER PK AUTOINCREMENT), name, name_key (TEXT UNIQUE NOT NULL), building, color, notes, map_floor, map_x, map_y, map_width, map_height, is_deleted                                                                                                                                              |
| **categories**        | id (INTEGER PK AUTOINCREMENT), name, is_deleted                                                                                                                                                                                                                                                       |
| **tasks**             | id (INTEGER PK AUTOINCREMENT), title, description, due_date, snooze_history_json, status, call_id, priority, solution_notes, snooze_until, caller_id, equipment_id, department_id, phone_id, phone_text, user_text, equipment_text, department_text, created_at, updated_at, search_index, is_deleted |
| **knowledge_base**    | id (INTEGER PK AUTOINCREMENT), topic, content, tags                                                                                                                                                                                                                                                   |
| **audit_log**         | id (INTEGER PK AUTOINCREMENT), action, timestamp, user_performing, details                                                                                                                                                                                                                            |
| **app_settings**      | key (TEXT PK), value                                                                                                                                                                                                                                                                                  |
| **remote_tool_args**  | id (INTEGER PK AUTOINCREMENT), tool_name, arg_flag, description, is_active                                                                                                                                                                                                                            |
| **user_dictionary**   | word (TEXT PK), language, letters_count (INTEGER NOT NULL DEFAULT 0), diacritic_mark_count (INTEGER NOT NULL DEFAULT 0)                                                                                                                                                                               |
| **full_dictionary**   | id (INTEGER PK AUTOINCREMENT), word (TEXT NOT NULL UNIQUE), normalized_word, source, language, category, created_at, letters_count, diacritic_mark_count                                                                                                                                              |


Ευρετήρια `full_dictionary`: `normalized_word`; σύνθετο `(language, source, category)`; `letters_count`; `diacritic_mark_count`.

---

## 3) MODELS

### features/calls/models/

- **CallModel:** id, date, time, callerId, equipmentId, callerText, phoneText, departmentText, equipmentText, issue, solution, category, categoryId, status, duration, isPriority, isDeleted.
- **EquipmentModel:** id, code, type, notes, customIp, anydeskId, defaultRemoteTool, departmentId, location, isDeleted (υπολογιζόμενα: displayLabel, vncTarget, anydeskTarget).
- **UserModel:** id, firstName, lastName, phones, departmentId, location, notes, isDeleted (υπολογιζόμενα: phoneJoined, name, departmentName, fullNameWithDepartment).

### features/directory/models/

- **CategoryModel:** id, name.
- **DepartmentModel:** id, name, building, color, notes, mapFloor, mapX, mapY, mapWidth, mapHeight, directPhones (runtime από join), isDeleted.
- **CategoryDirectoryColumn:** σταθερές στήλης (key, label, sortKey) για πίνακα κατηγοριών.
- **DepartmentDirectoryColumn:** idem για τμήματα.
- **UserDirectoryColumn:** idem για χρήστες.
- **equipment_column.dart:** τύπος **EquipmentRow** (ζεύγος EquipmentModel + UserModel? κάτοχος) και βοηθητικές συναρτήσεις μορφοποίησης τοποθεσίας/στήλης (όχι κλασικό data class με πεδία εγγραφής).

### features/tasks/models/

- **TaskStatus** (enum): open, snoozed, closed.
- **Task:** id, callId, callerId, equipmentId, departmentId, phoneId, phoneText, userText, equipmentText, departmentText, title, description, dueDate, snoozeUntil, snoozeHistoryJson, status, priority, solutionNotes, createdAt, updatedAt, isDeleted.
- **TaskSortOption** (enum): createdAt, dueAt, priority, department, user, equipment.
- **TaskFilter:** searchQuery, statuses, startDate, endDate, sortBy, sortAscending.
- **TaskSettingsConfig:** dayEndTime, nextBusinessHour, skipWeekends, defaultSnoozeOption, maxSnoozeDays, autoCloseQuickAdds.

### features/database/models/

- **DatabaseStats:** fileSizeBytes, dbPath, lastBackupTime, rowCountsByTable.
- **DatabaseBackupSettings (+ enums μορφής/διαστήματος):** destinationDirectory, namingFormat, zipOutput, backupOnExit, interval, backupDays, backupTime, lastBackupAttempt, lastBackupStatus, retention flags/αριθμοί.

### core/models/

- **DictionaryImportMode** (enum): enrich, replace.
- **RemoteToolArg:** id, toolName, argFlag, description, isActive.

---

## 4) STATE MANAGEMENT — PROVIDERS (Riverpod)

Βασικοί providers (όνομα → ρόλος):

- **appInitProvider** — αρχικοποίηση εφαρμογής / αποτέλεσμα εκκίνησης.
- **databaseInitProgressProvider** — πρόοδος/κατάσταση ανοίγματος βάσης.
- **lookupServiceProvider** — φόρτωση LookupService (τμήματα, χρήστες, κ.λπ.).
- **callEntryProvider** — κατάσταση φόρμας τρέχουσας κλήσης.
- **recentCallsProvider** — πρόσφατες κλήσεις (family ανά όριο).
- **callSmartEntityProvider / taskSmartEntityProvider** — επιλογή καλούντος/τηλεφώνου/εξοπλισμού (έξυπνο UI).
- **callHeaderProvider** — alias προς callSmartEntityProvider.
- **importLogProvider** — καταγραφή/κατάσταση εισαγωγών.
- **notesFieldHintTickProvider** — tick για hints πεδίου σημειώσεων.
- **remoteArgsServiceProvider, validRemotePathsProvider, remoteLauncherStatusProvider, remoteConnectionServiceProvider, remoteLauncherServiceProvider** — απομακρυσμένη σύνδεση και διαδρομές εργαλείων.
- **directoryProvider, catalogContinuousScrollProvider** — κατάλογος (tabs, συγχώνευση καταστάσεων), ρύθμιση συνεχούς κύλισης καταλόγου.
- **departmentDirectoryProvider, equipmentDirectoryProvider, categoryDirectoryProvider** — πίνακες/φίλτρα ανά ενότητα καταλόγου (Notifier providers)· χρήστες μέσω της ίδιας ροής καταλόγου (`directory_provider`).
- **historyFilterProvider, historyCallsProvider, historyCategoriesProvider, historyCategoryEntriesProvider** — ιστορικό κλήσεων και φίλτρα.
- **tasksProvider, taskFilterProvider, taskStatusCountsProvider, globalPendingTasksCountProvider, orphanCallsProvider** — λίστα εκκρεμοτήτων, φίλτρα, μετρητές.
- **taskServiceProvider, taskSettingsConfigProvider, pendingTaskDeleteProvider** — υπηρεσία εργασιών, ρυθμίσεις snooze/ωραρίου, εκκρεμής διαγραφή.
- **settings providers (showActiveTimerProvider, showAnyDeskRemoteProvider, showTasksBadgeProvider, enableSpellCheckProvider, showDatabaseNavProvider, showDictionaryNavProvider)** — διακόπτες UI από ρυθμίσεις.
- **greekDictionaryServiceProvider, spellCheckServiceProvider** — λεξικό/ορθογραφία.
- **lexiconCategoriesProvider, lexiconFullModeProvider, lexiconLanguageRecalcProvider, lexiconMasterDataRevisionProvider** — λεξικό (κατηγορίες, πλήρης οθόνη, επανυπολογισμός γλωσσών, revision).
- **lexiconContinuousScrollProvider, lexiconPageSizeProvider** — κύλιση/μέγεθος σελίδας λεξικού.
- **shellNavigationIntentProvider** — ενδιάμεση πρόθεση πλοήγησης (π.χ. από immersive λεξικό).
- **databaseBrowserStatsProvider, databaseMaintenanceServiceProvider, databaseBackupSettingsProvider, backupSchedulerProvider** — περιήγηση βάσης, συντήρηση, backups.

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