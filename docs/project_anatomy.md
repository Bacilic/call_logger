# Call Logger — Project Anatomy

**Ημερομηνία τροποποίησης εγγράφου:** 2 Απριλίου 2026

Συμπυκνωμένη «ακτινογραφία» για εξωτερικό LLM (Καθοδηγητής): Flutter για Windows 11, δομή ανά `features/`, Riverpod, SQLite μέσω `sqflite_common_ffi`.

---

## 1) DIRTREE (`lib/`)

```text
lib/
├── main.dart
├── core/
│   ├── config/app_config.dart
│   ├── database/
│   │   ├── database_helper.dart
│   │   ├── database_init_progress_provider.dart
│   │   ├── database_init_result.dart
│   │   ├── database_init_runner.dart
│   │   ├── database_path_pick_flow.dart
│   │   ├── database_path_resolution.dart
│   │   ├── database_v1_schema.dart
│   │   └── lock_diagnostic_service.dart
│   ├── errors/department_exists_exception.dart
│   ├── init/app_init_provider.dart, app_initializer.dart
│   ├── models/remote_tool_arg.dart
│   ├── providers/
│   │   ├── greek_dictionary_provider.dart
│   │   ├── settings_provider.dart
│   │   └── spell_check_provider.dart
│   ├── services/
│   │   ├── dictionary_service.dart, excel_parser.dart
│   │   ├── import_service.dart, import_types.dart
│   │   ├── lookup_service.dart
│   │   ├── remote_args_service.dart, remote_connection_service.dart, remote_launcher_service.dart
│   │   ├── settings_service.dart, spell_check_service.dart
│   ├── theme/
│   ├── utils/ (date_parser, department_display, name_parser, phone_list_parser, search_text_normalizer, spell_check, user_identity_normalizer)
│   └── widgets/
│       ├── app_init_wrapper.dart, app_shell_with_global_fatal_error.dart, app_shortcuts.dart
│       ├── calendar_range_picker.dart, database_error_screen.dart
│       ├── global_fatal_error_notifier.dart
│       ├── lexicon_spell_text_form_field.dart, main_shell.dart, spell_check_controller.dart
└── features/
    ├── calls/
    │   ├── models/ (call_model, user_model, equipment_model)
    │   ├── provider/ (call_entry, call_header, import_log, lookup, notes_field_hint, remote_paths, smart_entity_selector)
    │   ├── screens/calls_screen.dart, widgets/ (φόρμα κλήσης, λίστες, import, remote, entity selector)
    │   └── utils/remote_target_rules.dart, vnc_remote_target.dart
    ├── database/
    │   ├── models/database_backup_settings.dart, database_stats.dart
    │   ├── providers/ (backup_scheduler, database_backup_settings, database_browser_stats, database_maintenance)
    │   ├── screens/database_browser_screen.dart
    │   ├── services/ (backup, exit_backup, maintenance, stats)
    │   ├── utils/ (backup schedule, validators, hints)
    │   └── widgets/ (panels, dialogs)
    ├── directory/
    │   ├── models/ (department_model, user_directory_column, department_directory_column, equipment_column)
    │   ├── providers/directory_provider.dart, department_directory_provider.dart, equipment_directory_provider.dart
    │   ├── screens/directory_screen.dart, widgets/ (tabs, tables, forms, bulk edit)
    ├── history/
    │   ├── providers/history_provider.dart
    │   └── screens/history_screen.dart
    ├── settings/
    │   ├── screens/settings_screen.dart
    │   └── widgets/create_new_database_dialog.dart, remote_args_editor.dart
    └── tasks/
        ├── models/task.dart, task_filter.dart, task_settings_config.dart
        ├── providers/tasks_provider.dart, task_service_provider.dart, task_settings_config_provider.dart, pending_task_delete_provider.dart
        ├── screens/ (tasks_screen, task_card, dialogs, filter_bar)
        ├── services/task_service.dart
        └── ui/task_due_option_tooltips.dart
```

---

## 2) DATABASE SCHEMA (SQLite)

**Πηγή CREATE TABLE:** `lib/core/database/database_v1_schema.dart` (`applyDatabaseV1Schema`).  
**Έκδοση σχήματος:** `databaseSchemaVersionV1 = 6` (βλ. ίδιο αρχείο και migrations στο `database_helper.dart`).

| Πίνακας | Στήλες (όνομα → τύπος SQLite) |
|--------|-------------------------------|
| **calls** | `id` INTEGER PK AI, `date` TEXT, `time` TEXT, `caller_id` INTEGER, `equipment_id` INTEGER, `caller_text` TEXT, `phone_text` TEXT, `department_text` TEXT, `equipment_text` TEXT, `issue` TEXT, `solution` TEXT, `category_text` TEXT, `category_id` INTEGER, `status` TEXT, `duration` INTEGER, `is_priority` INTEGER DEFAULT 0, `search_index` TEXT, `is_deleted` INTEGER DEFAULT 0 |
| **users** | `id` INTEGER PK AI, `last_name` TEXT NOT NULL, `first_name` TEXT NOT NULL, `department_id` INTEGER, `location` TEXT, `notes` TEXT, `is_deleted` INTEGER DEFAULT 0 |
| **phones** | `id` INTEGER PK AI, `number` TEXT UNIQUE NOT NULL, `department_id` INTEGER |
| **department_phones** | `department_id` INTEGER NOT NULL, `phone_id` INTEGER NOT NULL, PK (`department_id`,`phone_id`) |
| **user_phones** | `user_id` INTEGER NOT NULL, `phone_id` INTEGER NOT NULL, PK (`user_id`,`phone_id`) |
| **equipment** | `id` INTEGER PK AI, `code_equipment` TEXT, `type` TEXT, `notes` TEXT, `custom_ip` TEXT, `anydesk_id` TEXT, `default_remote_tool` TEXT, `department_id` INTEGER, `location` TEXT, `is_deleted` INTEGER DEFAULT 0 |
| **user_equipment** | `user_id` INTEGER NOT NULL, `equipment_id` INTEGER NOT NULL, PK (`user_id`,`equipment_id`) |
| **departments** | `id` INTEGER PK AI, `name` TEXT NOT NULL, `name_key` TEXT UNIQUE NOT NULL, `building` TEXT, `color` TEXT DEFAULT '#1976D2', `notes` TEXT, `map_floor` TEXT, `map_x` REAL DEFAULT 0, `map_y` REAL DEFAULT 0, `map_width` REAL DEFAULT 0, `map_height` REAL DEFAULT 0, `is_deleted` INTEGER DEFAULT 0 |
| **categories** | `id` INTEGER PK AI, `name` TEXT, `is_deleted` INTEGER DEFAULT 0 |
| **tasks** | `id` INTEGER PK AI, `title` TEXT, `description` TEXT, `due_date` TEXT, `snooze_history_json` TEXT, `status` TEXT, `call_id` INTEGER, `priority` INTEGER, `solution_notes` TEXT, `snooze_until` TEXT, `caller_id` INTEGER, `equipment_id` INTEGER, `department_id` INTEGER, `phone_id` INTEGER, `phone_text` TEXT, `user_text` TEXT, `equipment_text` TEXT, `department_text` TEXT, `created_at` TEXT, `updated_at` TEXT, `search_index` TEXT, `is_deleted` INTEGER DEFAULT 0 |
| **knowledge_base** | `id` INTEGER PK AI, `topic` TEXT, `content` TEXT, `tags` TEXT |
| **audit_log** | `id` INTEGER PK AI, `action` TEXT, `timestamp` TEXT, `user_performing` TEXT, `details` TEXT |
| **app_settings** | `key` TEXT PK, `value` TEXT |
| **remote_tool_args** | `id` INTEGER PK AI, `tool_name` TEXT, `arg_flag` TEXT, `description` TEXT, `is_active` INTEGER DEFAULT 0 |
| **user_dictionary** | `word` TEXT PK |

---

## 3) MODELS (πεδία / ρόλος)

### `lib/features/calls/models/`

- **CallModel:** `id`, `date`, `time`, `callerId`, `equipmentId`, `callerText`, `phoneText`, `departmentText`, `equipmentText`, `issue`, `solution`, `category`, `status`, `duration`, `isPriority`, `isDeleted`.
- **UserModel:** `id`, `firstName`, `lastName`, `phones` (λίστα από M2M), `departmentId`, `location`, `notes`, `isDeleted`· υπολογιζόμενα: `name`, `phoneJoined`, `departmentName`, `fullNameWithDepartment`.
- **EquipmentModel:** `id`, `code` (DB: `code_equipment`), `type`, `notes`, `customIp`, `anydeskId`, `defaultRemoteTool`, `departmentId`, `location`, `isDeleted`· υπολογιζόμενα: `displayLabel`, `vncTarget`, `anydeskTarget`.

### `lib/features/directory/models/`

- **DepartmentModel:** `id`, `name`, `building`, `color`, `notes`, `mapFloor`, `mapX`, `mapY`, `mapWidth`, `mapHeight`, `directPhones` (όχι στήλη DB· φόρτωση από `department_phones`), `isDeleted`.
- **UserDirectoryColumn / DepartmentDirectoryColumn / EquipmentColumn:** μεταδεδομένα στηλών πίνακα (κλειδί, ετικέτα, ταξινόμηση, εμφάνιση). **EquipmentRow** = `(EquipmentModel, UserModel?)` (typedef).

### `lib/features/tasks/models/`

- **Task:** `id`, `callId`, `callerId`, `equipmentId`, `departmentId`, `phoneId`, `phoneText`, `userText`, `equipmentText`, `departmentText`, `title`, `description`, `dueDate`, `snoozeUntil`, `snoozeHistoryJson`, `status`, `priority`, `solutionNotes`, `createdAt`, `updatedAt`, `isDeleted`· στατικά/βοηθητικά για quick-add και εμφάνιση τίτλου.
- **TaskStatus (enum):** `open`, `snoozed`, `closed`.
- **TaskSnoozeEntry:** `snoozedAt`, `dueAt` (ιστορικό αναβολών από JSON).
- **TaskFilter:** `searchQuery`, `statuses`, `startDate`, `endDate`, `sortBy` (`TaskSortOption`), `sortAscending`.
- **TaskSortOption (enum):** `createdAt`, `dueAt`, `priority`, `department`, `user`, `equipment`.
- **TaskSettingsConfig:** `dayEndTime`, `nextBusinessHour`, `skipWeekends`, `defaultSnoozeOption`, `maxSnoozeDays`, `autoCloseQuickAdds` (αποθήκευση JSON σε `app_settings`).

### `lib/features/database/models/`

- **DatabaseStats:** `fileSizeBytes`, `dbPath`, `rowCountsByTable`, `lastBackupTime`.
- **DatabaseBackupSettings:** `destinationDirectory`, `namingFormat`, `zipOutput`, `backupOnExit`, `interval`, `backupDays`, `backupTime`, `lastBackupAttempt`, `lastBackupStatus`, flags/limit retention· enums `DatabaseBackupNamingFormat`, `DatabaseBackupInterval`.

### `lib/core/models/`

- **RemoteToolArg:** `id`, `toolName`, `argFlag`, `description`, `isActive`.

### Άλλα (εκτός φακέλου `models/`)

- **HistoryFilterModel** (`features/history/providers/history_provider.dart`): `keyword`, `dateFrom`, `dateTo`, `category`.
- **OrphanCall** (`features/tasks/services/task_service.dart`): ελαφρύ μοντέλο κλήσης χωρίς task (για orphan UI).
- **SmartEntitySelectorState** (`features/calls/provider/smart_entity_selector_provider.dart`): κατάσταση φόρμας τηλεφώνου/καλούντα/εξοπλισμού/τμήματος (όχι πίνακας DB).

---

## 4) STATE MANAGEMENT — PROVIDERS (Riverpod)

| Provider | Σκοπός (σύντομα) |
|----------|------------------|
| `appInitProvider` | Αρχικοποίηση εφαρμογής (βάση, λεξικό, ρυθμίσεις). |
| `databaseInitProgressProvider` | Πρόοδος/μηνύματα κατά το άνοιγμα αρχείου βάσης. |
| `greekDictionaryServiceProvider` | Φόρτωση `DictionaryService` (λεξικό). |
| `spellCheckServiceProvider` | Υπηρεσία ορθογραφίας βασισμένη σε λεξικό. |
| `showActiveTimerProvider`, `showAnyDeskRemoteProvider`, `showTasksBadgeProvider`, `enableSpellCheckProvider` | Ρυθμίσεις UI από `SettingsService` / `app_settings`. |
| `lookupServiceProvider` | Async φόρτωση `LookupService` (χρήστες, τηλέφωνα, τμήματα, εξοπλισμός). |
| `callSmartEntityProvider`, `taskSmartEntityProvider` | Κατάσταση έξυπνου επιλογέα οντοτήτων (κλήσεις vs tasks). |
| `callHeaderProvider` | Alias του `callSmartEntityProvider` για τη γραμμή κεφαλίδας κλήσης. |
| `callEntryProvider` | Φόρμα κλήσης: εσωτερικό, σημειώσεις, κατηγορία, χρονόμετρο, υποβολή. |
| `recentCallsProvider` (family) | Πρόσφατες κλήσεις ανά `callerId`. |
| `notesFieldHintTickProvider` | Tick για hints πεδίου σημειώσεων. |
| `importLogProvider` | Καταχωρήσεις log εισαγωγής Excel. |
| `remoteArgsServiceProvider`, `validRemotePathsProvider`, `remoteLauncherStatusProvider`, `remoteConnectionServiceProvider`, `remoteLauncherServiceProvider` | Διαδρομές/ορίσματα VNC & AnyDesk και εκκίνηση. |
| `directoryProvider` | Κατάλογος χρηστών: λίστα, επιλογή, στήλες, CRUD, undo διαγραφών. |
| `departmentDirectoryProvider` | Ίδια για τμήματα. |
| `equipmentDirectoryProvider` | Ίδια για εξοπλισμό + M2M με χρήστες. |
| `catalogContinuousScrollProvider` | Ρύθμιση συνεχούς κύλισης στους πίνακες καταλόγου. |
| `historyFilterProvider`, `historyCallsProvider`, `historyCategoriesProvider` | Φίλτρα και δεδομένα ιστορικού κλήσεων. |
| `taskServiceProvider` | Ανάλυση `TaskService` (singleton-style). |
| `taskFilterProvider` | Κατάσταση φίλτρου λίστας εκκρεμοτήτων. |
| `taskStatusCountsProvider` | Μετρητές ανά status για chips. |
| `tasksProvider` | Λίστα εκκρεμοτήτων (async) + refresh/update. |
| `globalPendingTasksCountProvider` | Συνολικό πλήθος open+snoozed (badge μενού). |
| `orphanCallsProvider` | Κλήσεις χωρίς αντίστοιχο task. |
| `taskSettingsConfigProvider` | Ρυθμίσεις εκκρεμοτήτων από `app_settings`. |
| `pendingTaskDeleteProvider` | `taskId` εκκρεμούς διαγραφής με countdown (μπλοκάρισμα νέων διαγραφών). |
| `databaseMaintenanceServiceProvider` | Πρόσβαση σε `DatabaseMaintenanceService`. |
| `databaseBrowserStatsProvider` | Στατιστικά για οθόνη περιήγησης βάσης. |
| `databaseBackupSettingsProvider` | Ρυθμίσεις αντιγράφων ασφαλείας. |
| `backupSchedulerProvider` | Χρονοπρόγραμμα/έλεγχος periodic backup ενώ τρέχει η εφαρμογή. |

**Σημείωση:** `globalFatalErrorNotifier` (`ValueNotifier`) στο `core/widgets` — όχι Riverpod, για καθολικά σφάλματα εκκίνησης.

---

## 5) DEPENDENCIES (`pubspec.yaml`)

- **Environment:** `sdk: ^3.10.7`
- **Κύριες (dependencies):**  
  `flutter` / `flutter_localizations` (sdk), `cupertino_icons: ^1.0.8`, `flutter_riverpod: ^3.2.1`, `sqflite_common: ^2.5.6`, `sqflite_common_ffi: ^2.3.3`, `sqlite3_flutter_libs: ^0.6.0`, `path_provider: ^2.1.2`, `path: ^1.9.0`, `google_fonts: ^8.0.2`, `intl: ^0.20.2`, `window_manager: ^0.5.1`, `screen_retriever: ^0.2.0`, `shared_preferences: ^2.3.3`, `url_launcher: ^6.3.0`, `excel: ^4.0.6`, `file_picker: ^8.0.0`, `archive: ^3.6.1`, `win32: ^5.15.0`, `ffi: ^2.2.0`
- **Dev:** `flutter_test`, `integration_test` (sdk), `riverpod: ^3.2.1`, `flutter_lints: ^6.0.0`

---

*Τέλος εγγράφου — ενημερώστε την ημερομηνία στην κεφαλίδα όταν αλλάζει ουσιαστικά το σχήμα ή η δομή του έργου.*
