# Call Logger — Project Anatomy

**Ημερομηνία τροποποίησης εγγράφου:** 25 Μαρτίου 2026

Συμπυκνωμένη «ακτινογραφία» για εξωτερικό LLM (Καθοδηγητής): Flutter για Windows 11, καθαρή αρχιτεκτονική ανά `features/`, κατάσταση με Riverpod. Δεν περιέχει αυτούσιο κώδικα.

---

## 1) DIRTREE (`lib/`)

```text
lib/
├── main.dart
├── core/
│   ├── config/
│   │   └── app_config.dart
│   ├── database/
│   │   ├── database_helper.dart
│   │   ├── database_init_result.dart
│   │   ├── database_init_runner.dart
│   │   └── database_v1_schema.dart
│   ├── errors/
│   │   └── department_exists_exception.dart
│   ├── init/
│   │   ├── app_init_provider.dart
│   │   └── app_initializer.dart
│   ├── models/
│   │   └── remote_tool_arg.dart
│   ├── providers/
│   │   └── settings_provider.dart
│   ├── services/
│   │   ├── excel_parser.dart
│   │   ├── import_service.dart
│   │   ├── import_types.dart
│   │   ├── lookup_service.dart
│   │   ├── remote_args_service.dart
│   │   ├── remote_connection_service.dart
│   │   ├── remote_launcher_service.dart
│   │   └── settings_service.dart
│   ├── theme/
│   │   └── .gitkeep
│   ├── utils/
│   │   ├── department_display_utils.dart
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
│       ├── database_error_screen.dart
│       ├── global_fatal_error_notifier.dart
│       └── main_shell.dart
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
    │   └── screens/
    │       ├── calls_screen.dart
    │       └── widgets/
    │           ├── call_header_form.dart
    │           ├── call_status_bar.dart
    │           ├── category_autocomplete_field.dart
    │           ├── equipment_info_card.dart
    │           ├── import_console_widget.dart
    │           ├── notes_sticky_field.dart
    │           ├── recent_calls_list.dart
    │           ├── remote_connection_buttons.dart
    │           ├── smart_entity_selector_caller_presentational.dart
    │           ├── smart_entity_selector_phone_presentational.dart
    │           ├── smart_entity_selector_widget.dart
    │           ├── sticky_note_widget.dart
    │           └── user_info_card.dart
    ├── database/
    │   └── screens/
    │       └── database_browser_screen.dart
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
    │       └── widgets/
    │           ├── bulk_department_edit_dialog.dart
    │           ├── bulk_equipment_edit_dialog.dart
    │           ├── bulk_user_edit_dialog.dart
    │           ├── catalog_column_selector_shell.dart
    │           ├── department_color_palette.dart
    │           ├── department_form_dialog.dart
    │           ├── department_transfer_confirm_dialog.dart
    │           ├── departments_data_table.dart
    │           ├── departments_tab.dart
    │           ├── equipment_data_table.dart
    │           ├── equipment_form_dialog.dart
    │           ├── equipment_tab.dart
    │           ├── homonym_warning_dialog.dart
    │           ├── user_form_dialog.dart
    │           ├── user_form_smart_text_field.dart
    │           ├── user_name_change_confirm_dialog.dart
    │           ├── users_tab.dart
    │           └── users_data_table.dart
    ├── history/
    │   ├── providers/
    │   │   └── history_provider.dart
    │   └── screens/
    │       └── history_screen.dart
    ├── settings/
    │   ├── screens/
    │   │   └── settings_screen.dart
    │   └── widgets/
    │       └── remote_args_editor.dart
    └── tasks/
        ├── models/
        │   ├── task.dart
        │   ├── task_filter.dart
        │   └── task_snooze_config.dart
        ├── providers/
        │   ├── task_service_provider.dart
        │   ├── task_snooze_config_provider.dart
        │   └── tasks_provider.dart
        ├── screens/
        │   ├── task_card.dart
        │   ├── task_close_dialog.dart
        │   ├── task_filter_bar.dart
        │   ├── task_form_dialog.dart
        │   ├── task_snooze_settings_dialog.dart
        │   └── tasks_screen.dart
        └── services/
            └── task_service.dart
```

*(Ενδέχεται να υπάρχουν κενοί φάκελοι· δεν περιλαμβάνονται.)*

---

## 2) Σχήμα βάσης δεδομένων (SQLite)

**Πηγή ορισμού πινάκων:** `lib/core/database/database_v1_schema.dart` — συνάρτηση `applyDatabaseV1Schema` (σταθερά `databaseSchemaVersionV1 = 2`). Το `lib/core/database/database_helper.dart` ανοίγει τη βάση, στο `_onCreate` καλεί `applyDatabaseV1Schema`, και διαχειρίζεται αναβαθμίσεις (`_onUpgradeSquashed` κ.λπ.).

Τύποι όπως στο `CREATE TABLE`:

| Πίνακας | Στήλες (όνομα → τύπος SQLite) |
|--------|--------------------------------|
| **calls** | `id` INTEGER PK AUTOINCREMENT, `date` TEXT, `time` TEXT, `caller_id` INTEGER, `equipment_id` INTEGER, `caller_text` TEXT, `phone_text` TEXT, `department_text` TEXT, `equipment_text` TEXT, `issue` TEXT, `solution` TEXT, `category_text` TEXT, `category_id` INTEGER, `status` TEXT, `duration` INTEGER, `is_priority` INTEGER DEFAULT 0, `search_index` TEXT, `is_deleted` INTEGER DEFAULT 0 |
| **users** | `id` INTEGER PK AUTOINCREMENT, `last_name` TEXT NOT NULL, `first_name` TEXT NOT NULL, `department_id` INTEGER, `location` TEXT, `notes` TEXT, `is_deleted` INTEGER DEFAULT 0 |
| **phones** | `id` INTEGER PK AUTOINCREMENT, `number` TEXT UNIQUE NOT NULL |
| **user_phones** | `user_id` INTEGER NOT NULL, `phone_id` INTEGER NOT NULL, PRIMARY KEY (`user_id`, `phone_id`) |
| **equipment** | `id` INTEGER PK AUTOINCREMENT, `code_equipment` TEXT, `type` TEXT, `notes` TEXT, `custom_ip` TEXT, `anydesk_id` TEXT, `default_remote_tool` TEXT, `department_id` INTEGER, `location` TEXT, `is_deleted` INTEGER DEFAULT 0 |
| **user_equipment** | `user_id` INTEGER NOT NULL, `equipment_id` INTEGER NOT NULL, PRIMARY KEY (`user_id`, `equipment_id`) |
| **departments** | `id` INTEGER PK AUTOINCREMENT, `name` TEXT UNIQUE NOT NULL, `building` TEXT, `color` TEXT DEFAULT '#1976D2', `notes` TEXT, `map_floor` TEXT, `map_x` REAL DEFAULT 0.0, `map_y` REAL DEFAULT 0.0, `map_width` REAL DEFAULT 0.0, `map_height` REAL DEFAULT 0.0, `is_deleted` INTEGER DEFAULT 0 |
| **categories** | `id` INTEGER PK AUTOINCREMENT, `name` TEXT, `is_deleted` INTEGER DEFAULT 0 |
| **tasks** | `id` INTEGER PK AUTOINCREMENT, `title` TEXT, `description` TEXT, `due_date` TEXT, `snooze_history_json` TEXT, `status` TEXT, `call_id` INTEGER, `priority` INTEGER, `solution_notes` TEXT, `snooze_until` TEXT, `caller_id` INTEGER, `equipment_id` INTEGER, `department_id` INTEGER, `phone_id` INTEGER, `phone_text` TEXT, `user_text` TEXT, `equipment_text` TEXT, `department_text` TEXT, `created_at` TEXT, `updated_at` TEXT, `search_index` TEXT, `is_deleted` INTEGER DEFAULT 0 |
| **knowledge_base** | `id` INTEGER PK AUTOINCREMENT, `topic` TEXT, `content` TEXT, `tags` TEXT |
| **audit_log** | `id` INTEGER PK AUTOINCREMENT, `action` TEXT, `timestamp` TEXT, `user_performing` TEXT, `details` TEXT |
| **app_settings** | `key` TEXT PK, `value` TEXT |
| **remote_tool_args** | `id` INTEGER PK AUTOINCREMENT, `tool_name` TEXT, `arg_flag` TEXT, `description` TEXT, `is_active` INTEGER DEFAULT 0 |

Μετά τη δημιουργία σχήματος καλείται `seedRemoteToolArgsIfEmpty` για προεπιλεγμένα ορίσματα VNC/AnyDesk αν ο πίνακας `remote_tool_args` είναι άδειος.

---

## 3) Μοντέλα (MODELS)

### `lib/features/calls/models/`

- **CallModel:** `id`, `date`, `time`, `callerId`, `equipmentId`, `callerText`, `phoneText`, `departmentText`, `equipmentText`, `issue`, `solution`, `category` (αντιστοίχιση στη DB: `category_text`), `status`, `duration`, `isPriority`, `isDeleted`.
- **UserModel:** `id`, `firstName`, `lastName`, `phones` (λίστα από M2M), `departmentId`, `location`, `notes`, `isDeleted`· υπολογιζόμενα/helpers: `phoneJoined`, `name`, `departmentName`, `fullNameWithDepartment`.
- **EquipmentModel:** `id`, `code` (στήλη `code_equipment`), `type`, `notes`, `customIp`, `anydeskId`, `defaultRemoteTool`, `departmentId`, `location`, `isDeleted`· helpers: `displayLabel`, `vncTarget`, `anydeskTarget`.

### `lib/features/directory/models/`

- **DepartmentModel:** `id`, `name`, `building`, `color`, `notes`, `mapFloor`, `mapX`, `mapY`, `mapWidth`, `mapHeight`, `isDeleted`.
- **UserDirectoryColumn / DepartmentDirectoryColumn:** μεταδεδομένα στηλών πίνακα καταλόγου (`key`, `label`, `sortKey`) και σταθερές στήλες (επιλογή, id, κ.λπ.).
- **EquipmentColumn:** ορισμοί στηλών πίνακα εξοπλισμού· **EquipmentRow** = `(EquipmentModel, UserModel?)`.

### `lib/features/tasks/models/`

- **Task:** `id`, `callId`, `callerId`, `equipmentId`, `departmentId`, `phoneId`, `phoneText`, `userText`, `equipmentText`, `departmentText`, `title`, `description`, `dueDate`, `snoozeUntil`, `snoozeHistoryJson`, `status`, `priority`, `solutionNotes`, `createdAt`, `updatedAt`, `isDeleted` (+ βοηθητικά snooze/search στο ίδιο αρχείο).
- **TaskStatus** (enum): `open`, `snoozed`, `closed`.
- **TaskFilter:** `searchQuery`, `statuses`, `startDate`, `endDate`, `sortBy` (**TaskSortOption**), `sortAscending`.
- **TaskSortOption** (enum): `createdAt`, `dueAt`, `priority`, `department`, `user`, `equipment`.
- **TaskSnoozeConfig:** `dayEndTime`, `nextBusinessHour`, `skipWeekends`, `defaultSnoozeOption`, `maxSnoozeDays` (αποθήκευση JSON σε `app_settings`).

### Λοιπά αρχεία «μοντέλου» / κατάστασης

- **`lib/features/history/providers/history_provider.dart` — HistoryFilterModel:** `keyword`, `dateFrom`, `dateTo`, `category` (+ `dateFromSql` / `dateToSql`).
- **`lib/core/models/remote_tool_arg.dart` — RemoteToolArg:** `id`, `toolName`, `argFlag`, `description`, `isActive`.
- **`lib/core/database/database_init_result.dart`:** τύποι αποτελέσματος αρχικοποίησης/σφάλματος βάσης (`DatabaseInitResult`, `DatabaseStatus`, κ.λπ.).

---

## 4) Διαχείριση κατάστασης — Πάροχοι (Riverpod)

| Πάροχος | Σύντομη περιγραφή |
|--------|-------------------|
| **appInitProvider** | Ασύγχρονη εκκίνηση εφαρμογής (`AppInitResult`). |
| **showActiveTimerProvider**, **showAnyDeskRemoteProvider**, **showTasksBadgeProvider** | Ρυθμίσεις UI από `SettingsService` (χρονόμετρο φόρμας κλήσεων, κουμπί AnyDesk, badge εκκρεμοτήτων). |
| **lookupServiceProvider** | Φόρτωση δεδομένων lookup (`LookupLoadResult`) και in-memory `LookupService`. |
| **callSmartEntityProvider** | Κατάσταση φόρμας κλήσης: τηλέφωνο, καλών, τμήμα, εξοπλισμός, επιλογές/υποψήφιοι. |
| **taskSmartEntityProvider** | Ίδια ιδέα notifier για ροές εκκρεμοτήτων. |
| **callHeaderProvider** | Alias του `callSmartEntityProvider`. |
| **callEntryProvider** | Φόρμα εισαγωγής κλήσης: σημειώσεις, κατηγορία, εκκρεμότητα, διάρκεια, `isCallTimerRunning`, υποβολή κλήσης/εκκρεμότητας. |
| **notesFieldHintTickProvider** | Tick για οπτική υπόδειξη πεδίου σημειώσεων. |
| **recentCallsProvider** | Πρόσφατες κλήσεις ανά `callerId` (`FutureProvider.family`). |
| **importLogProvider** | Μηνύματα κονσόλας εισαγωγής δεδομένων. |
| **remoteArgsServiceProvider**, **validRemotePathsProvider**, **remoteLauncherStatusProvider**, **remoteConnectionServiceProvider**, **remoteLauncherServiceProvider** | Ορίσματα/διαδρομές εργαλείων απομακρυσμένης σύνδεσης και εκκίνηση. |
| **directoryProvider** | Κατάλογος χρηστών: λίστα, φίλτρο, ταξινόμηση, επιλογή, ορατές στήλες. |
| **departmentDirectoryProvider** | Κατάλογος τμημάτων (CRUD, φίλτρα, soft delete). |
| **equipmentDirectoryProvider** | Κατάλογος εξοπλισμού με join κάτοχου. |
| **catalogContinuousScrollProvider** | Συνεχής κύλιση πινάκων καταλόγου από `app_settings`. |
| **historyFilterProvider**, **historyCallsProvider**, **historyCategoriesProvider** | Φίλτρα και δεδομένα ιστορικού κλήσεων. |
| **historyTableZoomProvider** | Ορίζεται στην `history_screen.dart` — επίπεδο ζουμ πίνακα ιστορικού. |
| **taskServiceProvider** | Διάθεση `TaskService`. |
| **taskFilterProvider** | Κριτήρια λίστας εκκρεμοτήτων. |
| **tasksProvider** | Λίστα εργασιών (`Task`). |
| **taskStatusCountsProvider** | Μετρητές ανά κατάσταση για chips φίλτρου. |
| **globalPendingTasksCountProvider** | Συνολικό πλήθος για badge πλοήγησης. |
| **orphanCallsProvider** | Κλήσεις χωρίς συσχετισμένη εργασία. |
| **taskSnoozeConfigProvider** | Ρυθμίσεις αναβολών (`TaskSnoozeConfig`). |

---

## 5) Εξαρτήσεις (`pubspec.yaml`)

- **Environment:** `sdk: ^3.10.7`
- **Dependencies:** `flutter` (sdk), `flutter_localizations` (sdk), `cupertino_icons: ^1.0.8`, `flutter_riverpod: ^3.2.1`, `sqflite_common: ^2.5.6`, `sqflite_common_ffi: ^2.3.3`, `sqlite3_flutter_libs: ^0.6.0`, `path_provider: ^2.1.2`, `path: ^1.9.0`, `google_fonts: ^8.0.2`, `intl: ^0.20.2`, `window_manager: ^0.5.1`, `screen_retriever: ^0.2.0`, `shared_preferences: ^2.3.3`, `url_launcher: ^6.3.0`, `excel: ^4.0.6`, `file_picker: ^8.0.0`
- **Dev dependencies:** `flutter_test` (sdk), `integration_test` (sdk), `riverpod: ^3.2.1`, `flutter_lints: ^6.0.0`
