# Call Logger — Project Anatomy

**Ημερομηνία τροποποίησης εγγράφου:** 4 Απριλίου 2026

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
│   │   ├── settings_provider.dart
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
│   ├── utils/
│   │   ├── date_parser_util.dart
│   │   ├── department_display_utils.dart
│   │   ├── name_parser.dart
│   │   ├── phone_list_parser.dart
│   │   ├── search_text_normalizer.dart
│   │   ├── spell_check.dart
│   │   └── user_identity_normalizer.dart
│   └── widgets/
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
    │   │   └── widgets/  (πολλά widget κλήσης, επιλογέας οντότητας, εισαγωγή, απομακρυσμένη σύνδεση, κ.λπ.)
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
    │   └── screens/
    │       └── dictionary_manager_screen.dart
    ├── directory/
    │   ├── models/
    │   │   ├── department_directory_column.dart
    │   │   ├── department_model.dart
    │   │   ├── equipment_column.dart
    │   │   └── user_directory_column.dart
    │   ├── providers/
    │   │   ├── department_directory_provider.dart
    │   │   ├── directory_provider.dart
    │   │   └── equipment_directory_provider.dart
    │   └── screens/
    │       ├── directory_screen.dart
    │       └── widgets/  (κατάλογοι χρηστών/εξοπλισμού/τμημάτων, φόρμες, μαζική επεξεργασία, κ.λπ.)
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

*Σύνολο: περίπου 138 αρχεία `.dart` κάτω από `lib/` (συμπεριλαμβανομένων των widget υποφακέλων).*

---

## 2) DATABASE SCHEMA (SQLite)

**Τρέχουσα έκδοση σχήματος (user_version / εφαρμογή):** `7` (`databaseSchemaVersionV1` στο `database_v1_schema.dart`, ίδια τιμή στο `DatabaseHelper`).

**Σημείωση:** Υπάρχουν επίσης **μοναδικό ευρετήριο (unique index)** στο `departments(name_key)` από μετάβαση σχήματος (v4), και **ευρετήρια** στο `full_dictionary` (`normalized_word`, και `language, source, category`).


| Πίνακας               | Στήλες (όνομα → τύπος SQLite)                                                                                                                                                                                                                                                                                          |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **calls**             | id → INTEGER PK AUTOINCREMENT; date, time, caller_text, phone_text, department_text, equipment_text, issue, solution, category_text, status → TEXT; caller_id, equipment_id, category_id, duration, is_priority, is_deleted, search_index → INTEGER (ημερ/ώρα ως TEXT)                                                 |
| **users**             | id → INTEGER PK AUTOINCREMENT; last_name, first_name, location, notes → TEXT NOT NULL όπου σημειώνεται στο σχήμα για ονόματα; department_id, is_deleted → INTEGER                                                                                                                                                      |
| **phones**            | id → INTEGER PK AUTOINCREMENT; number → TEXT UNIQUE NOT NULL; department_id → INTEGER                                                                                                                                                                                                                                  |
| **department_phones** | department_id, phone_id → INTEGER, σύνθετο PRIMARY KEY                                                                                                                                                                                                                                                                 |
| **user_phones**       | user_id, phone_id → INTEGER, σύνθετο PRIMARY KEY                                                                                                                                                                                                                                                                       |
| **equipment**         | id → INTEGER PK AUTOINCREMENT; code_equipment, type, notes, custom_ip, anydesk_id, default_remote_tool, location → TEXT; department_id, is_deleted → INTEGER                                                                                                                                                           |
| **user_equipment**    | user_id, equipment_id → INTEGER, σύνθετο PRIMARY KEY                                                                                                                                                                                                                                                                   |
| **departments**       | id → INTEGER PK AUTOINCREMENT; name, name_key → TEXT NOT NULL (name_key UNIQUE); building, color, notes, map_floor → TEXT; map_x, map_y, map_width, map_height → REAL; is_deleted → INTEGER                                                                                                                            |
| **categories**        | id → INTEGER PK AUTOINCREMENT; name → TEXT; is_deleted → INTEGER                                                                                                                                                                                                                                                       |
| **tasks**             | id → INTEGER PK AUTOINCREMENT; title, description, due_date, snooze_history_json, status, solution_notes, snooze_until, phone_text, user_text, equipment_text, department_text, created_at, updated_at, search_index → TEXT; call_id, priority, caller_id, equipment_id, department_id, phone_id, is_deleted → INTEGER |
| **knowledge_base**    | id → INTEGER PK AUTOINCREMENT; topic, content, tags → TEXT                                                                                                                                                                                                                                                             |
| **audit_log**         | id → INTEGER PK AUTOINCREMENT; action, timestamp, user_performing, details → TEXT                                                                                                                                                                                                                                      |
| **app_settings**      | key → TEXT PRIMARY KEY; value → TEXT                                                                                                                                                                                                                                                                                   |
| **remote_tool_args**  | id → INTEGER PK AUTOINCREMENT; tool_name, arg_flag, description → TEXT; is_active → INTEGER                                                                                                                                                                                                                            |
| **user_dictionary**   | word → TEXT PRIMARY KEY                                                                                                                                                                                                                                                                                                |
| **full_dictionary**   | id → INTEGER PK AUTOINCREMENT; word, normalized_word, source, language, category → TEXT NOT NULL; created_at → TEXT NOT NULL (προεπιλογή `datetime('now')`)                                                                                                                                                            |


---

## 3) MODELS

### `lib/features/calls/models/`


| Τύπος              | Πεδία / περιεχόμενο                                                                                                                                             |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **CallModel**      | id, date, time, callerId, equipmentId, callerText, phoneText, departmentText, equipmentText, issue, solution, category, status, duration, isPriority, isDeleted |
| **UserModel**      | id, firstName, lastName, phones (λίστα), departmentId, location, notes, isDeleted· υπολογιζόμενα: phoneJoined, name, departmentName, fullNameWithDepartment     |
| **EquipmentModel** | id, code, type, notes, customIp, anydeskId, defaultRemoteTool, departmentId, location, isDeleted· υπολογιζόμενα: displayLabel, vncTarget, anydeskTarget         |


### `lib/features/directory/models/`


| Τύπος                         | Πεδία / περιεχόμενο                                                                                                                     |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| **DepartmentModel**           | id, name, building, color, notes, mapFloor, mapX, mapY, mapWidth, mapHeight, directPhones, isDeleted                                    |
| **DepartmentDirectoryColumn** | σταθερές στήλες καταλόγου: key, label, sortKey (π.χ. επιλογή, id, όνομα, κτίριο, χρώμα, τηλέφωνα, εξοπλισμός, σημειώσεις)               |
| **UserDirectoryColumn**       | όπως πάνω για πίνακα χρηστών (επώνυμο, όνομα, τηλέφωνο, τμήμα, κ.λπ.)                                                                   |
| **EquipmentRow** (typedef)    | ζεύγος (EquipmentModel, UserModel?)· το αρχείο `equipment_column.dart` περιέχει και βοηθητικές συναρτήσεις εμφάνισης τοποθεσίας γραμμής |


### `lib/features/tasks/models/`


| Τύπος                     | Πεδία / περιεχόμενο                                                                                                                                                                                                                         |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **TaskStatus** (enum)     | open, snoozed, closed                                                                                                                                                                                                                       |
| **Task**                  | id, callId, callerId, equipmentId, departmentId, phoneId, phoneText, userText, equipmentText, departmentText, title, description, dueDate, snoozeUntil, snoozeHistoryJson, status, priority, solutionNotes, createdAt, updatedAt, isDeleted |
| **TaskSortOption** (enum) | createdAt, dueAt, priority, department, user, equipment                                                                                                                                                                                     |
| **TaskFilter**            | searchQuery, statuses, startDate, endDate, sortBy, sortAscending                                                                                                                                                                            |
| **TaskSettingsConfig**    | dayEndTime, nextBusinessHour, skipWeekends, defaultSnoozeOption, maxSnoozeDays, autoCloseQuickAdds (+ σταθερές κλειδιά app_settings)                                                                                                        |


### `lib/features/database/models/`


| Τύπος                      | Πεδία / περιεχόμενο                                                                                                                                                                                |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **DatabaseStats**          | fileSizeBytes, dbPath, lastBackupTime, rowCountsByTable                                                                                                                                            |
| **DatabaseBackupSettings** | destinationDirectory, namingFormat, zipOutput, backupOnExit, interval, backupDays, backupTime, lastBackupAttempt, lastBackupStatus, ρυθμίσεις retention (ενεργοποίηση/όρια αντιγράφων και ηλικίας) |


### `lib/core/models/`


| Τύπος                           | Πεδία / περιεχόμενο                                                              |
| ------------------------------- | -------------------------------------------------------------------------------- |
| **DictionaryImportMode** (enum) | enrich (INSERT OR IGNORE), replace (καθάρισμα full_dictionary πριν την εισαγωγή) |
| **RemoteToolArg**               | id, toolName, argFlag, description, isActive                                     |


*Άλλα «μοντέλα» φίλτρων UI (π.χ. ιστορικό) μπορεί να ορίζονται στο ίδιο αρχείο με τον provider (`history_provider.dart`).*

---

## 4) STATE MANAGEMENT — PROVIDERS (Riverpod)


| Provider                                                                                                                                                                         | Ρόλος                                                                                                               |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| **appInitProvider**                                                                                                                                                              | Μία φορά στην εκκίνηση: `AppInitializer` + notifier προόδου βάσης· σε επιτυχία ενεργοποίηση προγραμματισμού backup. |
| **databaseInitProgressProvider**                                                                                                                                                 | Βήματα/μετρητής και διαγνωστικά κατά το άνοιγμα της βάσης.                                                          |
| **lookupServiceProvider**                                                                                                                                                        | Φόρτωση `LookupService` από τη βάση (κατάλογος χρηστών/εξοπλισμού)· αποτέλεσμα με πληροφορία σφάλματος αν αποτύχει. |
| **callEntryProvider**                                                                                                                                                            | Κατάσταση φόρμας καταχώρισης κλήσης.                                                                                |
| **recentCallsProvider**                                                                                                                                                          | Πρόσφατες κλήσεις ανά caller (family).                                                                              |
| **callSmartEntityProvider** / **taskSmartEntityProvider**                                                                                                                        | Κατάσταση «έξυπνου» επιλογέα (καλών / εκκρεμότητα)· μεγάλη λογική UI+ανίχνευση.                                     |
| **callHeaderProvider**                                                                                                                                                           | Ίδιο με `callSmartEntityProvider` (alias).                                                                          |
| **lookup_provider** (πάνω)                                                                                                                                                       | —                                                                                                                   |
| **remoteArgsServiceProvider**, **validRemotePathsProvider**, **remoteLauncherStatusProvider**, **remoteConnectionServiceProvider**, **remoteLauncherServiceProvider**            | Διαδρομές/ορίσματα VNC & AnyDesk και εκκίνηση απομακρυσμένης σύνδεσης.                                              |
| **importLogProvider**                                                                                                                                                            | Λίστα γραμμών log για κονσόλα εισαγωγής.                                                                            |
| **notesFieldHintTickProvider**                                                                                                                                                   | Αντίστροφη ανανέωση για οπτική υπόδειξη πεδίου σημειώσεων.                                                          |
| **directoryProvider**                                                                                                                                                            | Κατάσταση οθόνης καταλόγου (ρυθμίσεις στηλών, καρτέλες).                                                            |
| **catalogContinuousScrollProvider**                                                                                                                                              | Ρύθμιση συνεχούς κύλισης καταλόγου από `app_settings`.                                                              |
| **departmentDirectoryProvider**                                                                                                                                                  | Πίνακας/επεξεργασία τμημάτων στον κατάλογο.                                                                         |
| **equipmentDirectoryProvider**                                                                                                                                                   | Πίνακας/επεξεργασία εξοπλισμού.                                                                                     |
| **tasksProvider**                                                                                                                                                                | Λίστα εκκρεμοτήτων (AsyncNotifier) με refresh/CRUD.                                                                 |
| **taskFilterProvider**                                                                                                                                                           | Κριτήρια φίλτρου εκκρεμοτήτων.                                                                                      |
| **taskStatusCountsProvider**                                                                                                                                                     | Μετρητές ανά κατάσταση για τα τρέχοντα φίλτρα.                                                                      |
| **globalPendingTasksCountProvider**                                                                                                                                              | Πλήθος ανοικτών+αναβληθέντων για badge μενού.                                                                       |
| **orphanCallsProvider**                                                                                                                                                          | Κλήσεις χωρίς αντίστοιχο task.                                                                                      |
| **pendingTaskDeleteProvider**                                                                                                                                                    | Id εκκρεμότητας σε αντίστροφη μέτρηση διαγραφής (undo).                                                             |
| **taskServiceProvider**                                                                                                                                                          | Ανάλυση `TaskService`.                                                                                              |
| **taskSettingsConfigProvider**                                                                                                                                                   | Ρυθμίσεις εκκρεμοτήτων από `app_settings`.                                                                          |
| **historyFilterProvider**, **historyCallsProvider**, **historyCategoriesProvider**                                                                                               | Φίλτρα ιστορικού, αποτελέσματα κλήσεων, ονόματα κατηγοριών.                                                         |
| **historyTableZoomProvider**                                                                                                                                                     | Επίπεδο ζουμ πίνακα ιστορικού (οθόνη).                                                                              |
| **databaseBrowserStatsProvider**                                                                                                                                                 | Στατιστικά αρχείου/πινάκων για περιήγηση βάσης.                                                                     |
| **databaseBrowserZoomByTableProvider**                                                                                                                                           | Ζουμ ανά πίνακα στην προβολή βάσης.                                                                                 |
| **databaseMaintenanceServiceProvider**                                                                                                                                           | Υπηρεσία συντήρησης βάσης.                                                                                          |
| **databaseBackupSettingsProvider**                                                                                                                                               | Φόρτωση/αποθήκευση ρυθμίσεων backup (JSON σε `app_settings`).                                                       |
| **backupSchedulerProvider**                                                                                                                                                      | Περιοδικός έλεγχος χρονοδιαγράμματος αντιγράφων.                                                                    |
| **showActiveTimerProvider**, **showAnyDeskRemoteProvider**, **showTasksBadgeProvider**, **enableSpellCheckProvider**, **showDatabaseNavProvider**, **showDictionaryNavProvider** | Σημαίες UI/λειτουργιών από `SettingsService`.                                                                       |
| **spellCheckServiceProvider**                                                                                                                                                    | Υπηρεσία ορθογραφικού ελέγχου λεξικού.                                                                              |
| **greekDictionaryServiceProvider**                                                                                                                                               | Υπηρεσία λεξικού (`DictionaryService`).                                                                             |


---

## 5) DEPENDENCIES (pubspec.yaml)

**dependencies**


| Πακέτο                | Έκδοση  |
| --------------------- | ------- |
| flutter               | sdk     |
| flutter_localizations | sdk     |
| cupertino_icons       | ^1.0.8  |
| flutter_riverpod      | ^3.2.1  |
| sqflite_common        | ^2.5.6  |
| sqflite_common_ffi    | ^2.3.3  |
| sqlite3_flutter_libs  | ^0.6.0  |
| path_provider         | ^2.1.2  |
| path                  | ^1.9.0  |
| google_fonts          | ^8.0.2  |
| intl                  | ^0.20.2 |
| window_manager        | ^0.5.1  |
| screen_retriever      | ^0.2.0  |
| shared_preferences    | ^2.3.3  |
| url_launcher          | ^6.3.0  |
| excel                 | ^4.0.6  |
| file_picker           | ^8.0.0  |
| archive               | ^3.6.1  |
| win32                 | ^5.15.0 |
| ffi                   | ^2.2.0  |


**dev_dependencies**


| Πακέτο           | Έκδοση |
| ---------------- | ------ |
| flutter_test     | sdk    |
| integration_test | sdk    |
| riverpod         | ^3.2.1 |
| flutter_lints    | ^6.0.0 |


---

*Τέλος εγγράφου — ενημερώστε την ημερομηνία όταν αλλάζει ουσιαστικά το σχήμα ή η δομή.*