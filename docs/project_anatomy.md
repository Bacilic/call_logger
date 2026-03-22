# Call Logger — Project Anatomy

**Ημερομηνία τροποποίησης εγγράφου:** 22 Μαρτίου 2025

Συμπυκνωμένη «ακτινογραφία» για εξωτερικό LLM (Καθοδηγητής), με βάση την τρέχουσα δομή του έργου (Flutter Windows, Clean Architecture, Riverpod). Δεν περιέχει αυτούσιο κώδικα.

---

## 1) DIRTREE (`lib/`)

```text
lib/
├── main.dart
├── tool/                          (άδειος ή placeholder)
├── core/
│   ├── config/
│   │   └── app_config.dart
│   ├── database/
│   │   ├── database_helper.dart
│   │   ├── database_init_result.dart
│   │   └── database_init_runner.dart
│   ├── init/
│   │   ├── app_initializer.dart
│   │   └── app_init_provider.dart
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
    │   │   ├── department_model.dart
    │   │   ├── equipment_column.dart
    │   │   └── user_directory_column.dart
    │   ├── providers/
    │   │   ├── directory_provider.dart
    │   │   └── equipment_directory_provider.dart
    │   └── screens/
    │       ├── directory_screen.dart
    │       └── widgets/
    │           ├── bulk_equipment_edit_dialog.dart
    │           ├── bulk_user_edit_dialog.dart
    │           ├── department_transfer_confirm_dialog.dart
    │           ├── equipment_data_table.dart
    │           ├── equipment_form_dialog.dart
    │           ├── equipment_tab.dart
    │           ├── user_form_dialog.dart
    │           ├── user_form_smart_text_field.dart
    │           ├── user_name_change_confirm_dialog.dart
    │           ├── users_data_table.dart
    │           └── users_tab.dart
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

---

## 2) DATABASE SCHEMA (SQLite)

Πηγή: `lib/core/database/database_helper.dart` — `_onCreate` (έκδοση βάσης **1**), `_onUpgrade`, one-time `migrateDepartmentsIfNeeded()`, και runtime συμπληρώσεις όπως `search_index` σε παλιές εγκαταστάσεις.

### Πίνακες νέας εγκατάστασης (`_onCreate`)

- **calls**  
`id` INTEGER PRIMARY KEY AUTOINCREMENT, `date` TEXT, `time` TEXT, `caller_id` INTEGER, `equipment_id` INTEGER, `caller_text` TEXT, `phone_text` TEXT, `department_text` TEXT, `equipment_text` TEXT, `issue` TEXT, `solution` TEXT, `category_text` TEXT, `category_id` INTEGER, `status` TEXT, `duration` INTEGER, `is_priority` INTEGER DEFAULT 0, `search_index` TEXT, `is_deleted` INTEGER DEFAULT 0
- **users**  
`id` INTEGER PRIMARY KEY AUTOINCREMENT, `last_name` TEXT NOT NULL, `first_name` TEXT NOT NULL, `department_id` INTEGER, `location` TEXT, `notes` TEXT, `is_deleted` INTEGER DEFAULT 0  
*(χωρίς στήλη `phone`· τα τηλέφωνα σε M2M πίνακες παρακάτω)*
- **phones**  
`id` INTEGER PRIMARY KEY AUTOINCREMENT, `number` TEXT UNIQUE NOT NULL
- **user_phones**  
`user_id` INTEGER NOT NULL, `phone_id` INTEGER NOT NULL, PRIMARY KEY (`user_id`, `phone_id`)
- **equipment**  
`id` INTEGER PRIMARY KEY AUTOINCREMENT, `code_equipment` TEXT, `type` TEXT, `notes` TEXT, `custom_ip` TEXT, `anydesk_id` TEXT, `default_remote_tool` TEXT, `is_deleted` INTEGER DEFAULT 0  
*(χωρίς `user_id`· σχέση χρήστη–εξοπλισμού στον `user_equipment`)*
- **user_equipment**  
`user_id` INTEGER NOT NULL, `equipment_id` INTEGER NOT NULL, PRIMARY KEY (`user_id`, `equipment_id`)
- **categories**  
`id` INTEGER PRIMARY KEY AUTOINCREMENT, `name` TEXT, `is_deleted` INTEGER DEFAULT 0
- **tasks**  
`id` INTEGER PRIMARY KEY AUTOINCREMENT, `title` TEXT, `description` TEXT, `due_date` TEXT, `snooze_history_json` TEXT, `status` TEXT, `call_id` INTEGER, `priority` INTEGER, `solution_notes` TEXT, `snooze_until` TEXT, `caller_id` INTEGER, `equipment_id` INTEGER, `department_id` INTEGER, `phone_id` INTEGER, `phone_text` TEXT, `user_text` TEXT, `equipment_text` TEXT, `department_text` TEXT, `created_at` TEXT, `updated_at` TEXT, `search_index` TEXT, `is_deleted` INTEGER DEFAULT 0
- **knowledge_base**  
`id` INTEGER PRIMARY KEY AUTOINCREMENT, `topic` TEXT, `content` TEXT, `tags` TEXT
- **audit_log**  
`id` INTEGER PRIMARY KEY AUTOINCREMENT, `action` TEXT, `timestamp` TEXT, `user_performing` TEXT, `details` TEXT
- **app_settings**  
`key` TEXT PRIMARY KEY, `value` TEXT
- **remote_tool_args**  
`id` INTEGER PRIMARY KEY AUTOINCREMENT, `tool_name` TEXT, `arg_flag` TEXT, `description` TEXT, `is_active` INTEGER DEFAULT 0

### Πίνακας **departments** (`migrateDepartmentsIfNeeded` / `_ensureDepartmentsTable`)

`id` INTEGER PRIMARY KEY AUTOINCREMENT, `name` TEXT UNIQUE NOT NULL, `building` TEXT, `color` TEXT DEFAULT '#1976D2', `notes` TEXT, `map_floor` TEXT, `map_x` REAL DEFAULT 0.0, `map_y` REAL DEFAULT 0.0, `map_width` REAL DEFAULT 0.0, `map_height` REAL DEFAULT 0.0, `is_deleted` INTEGER DEFAULT 0

### Σημειώσεις σχήματος

- Σε **αναβαθμισμένες** βάσεις ενδέχεται να υπάρχουν προσωρινά legacy στήλες (π.χ. παλιό `users.phone`, `equipment.user_id`) μέχρι να ολοκληρωθούν migrations· το τρέχον `_onCreate` αντιστοιχεί στο σχήμα v17.
- Μεταφορά παλιού `users.phone` → `phones` / `user_phones` μέσω migration (idempotent, σημαία σε `app_settings`).
- Πολύ παλιά σχήματα `users.name` / `department` μετασχηματίζονται σε `first_name` / `last_name` και `department_id`.

---

## 3) MODELS (πεδία)

### Calls — `lib/features/calls/models/`

- **CallModel**: `id`, `date`, `time`, `callerId`, `equipmentId`, `callerText`, `phoneText`, `departmentText`, `equipmentText`, `issue`, `solution`, `category` (αντιστοίχιση σε `category_text` στη DB), `status`, `duration`, `isPriority`, `isDeleted`.
- **UserModel**: `id`, `firstName`, `lastName`, `phones` (λίστα αριθμών, M2M), `departmentId`, `notes`, `isDeleted`· getters: `phoneJoined`, `name`, `departmentName`, `fullNameWithDepartment`· υποστηρίζει legacy `phone` / `name` στο `fromMap`.
- **EquipmentModel**: `id`, `code` (↔ στήλη `code_equipment`), `type`, `notes`, `customIp`, `anydeskId`, `defaultRemoteTool`, `isDeleted`· getters: `displayLabel`, `vncTarget`, `anydeskTarget`· χωρίς `userId` (M2M `user_equipment`).

### Directory — `lib/features/directory/models/`

- **DepartmentModel**: `id`, `name`, `building`, `color`, `notes`, `mapFloor`, `mapX`, `mapY`, `mapWidth`, `mapHeight`, `isDeleted`.
- **UserDirectoryColumn**: σταθερές στήλες UI (`key`, `label`, `sortKey`) — επιλογή, id, επώνυμο, όνομα, τηλέφωνο, τμήμα, σημειώσεις· βοηθητικά `fromKey`, `editFocusField`, `searchText(UserModel)`.
- **EquipmentColumn**: `key`, `label`, `displayValue(EquipmentRow)`, `sortValue(EquipmentRow)?` — ορισμός στηλών πίνακα εξοπλισμού.
- **EquipmentRow** (typedef): `(EquipmentModel, UserModel?)`.

### Tasks — `lib/features/tasks/models/`

- **Task**: `id`, `callId`, `callerId`, `equipmentId`, `departmentId`, `phoneId`, `phoneText`, `userText`, `equipmentText`, `departmentText`, `title`, `description`, `dueDate`, `snoozeUntil`, `snoozeHistoryJson`, `status`, `priority`, `solutionNotes`, `createdAt`, `updatedAt`, `isDeleted`· βοηθητικά/snooze helpers στο ίδιο αρχείο.
- **TaskStatus** (enum): `open`, `snoozed`, `closed`.
- **TaskFilter**: `searchQuery`, `statuses`, `startDate`, `endDate`, `sortBy` (TaskSortOption), `sortAscending`· getter `allFiltersOff`.
- **TaskSortOption** (enum): `createdAt`, `dueAt`, `priority`, `department`, `user`, `equipment`.
- **TaskSnoozeConfig**: `dayEndTime`, `nextBusinessHour`, `skipWeekends`, `defaultSnoozeOption`, `maxSnoozeDays` (αποθήκευση JSON σε `app_settings`).

### History — `lib/features/history/providers/history_provider.dart`

- **HistoryFilterModel**: `keyword`, `dateFrom`, `dateTo`, `category`· βοηθητικά `dateFromSql` / `dateToSql` για SQL.

### Core — `lib/core/models/` και database

- **RemoteToolArg**: `id`, `toolName`, `argFlag`, `description`, `isActive`.
- **DatabaseInitResult** / **DatabaseStatus** (`database_init_result.dart`): αποτέλεσμα ελέγχου/αρχικοποίησης βάσης (κατάσταση, μηνύματα, διαδρομή, τεχνικές λεπτομέρειες).

---

## 4) STATE MANAGEMENT — Βασικοί Providers (Riverpod)

- **appInitProvider**: εκκίνηση εφαρμογής (`AppInitResult`).
- **showActiveTimerProvider**, **showAnyDeskRemoteProvider**, **showTasksBadgeProvider**: ρυθμίσεις UI από `SettingsService` (χρονόμετρο, AnyDesk, badge εκκρεμοτήτων).
- **lookupServiceProvider**: ασύγχρονη φόρτωση `LookupLoadResult` / in-memory `LookupService` (χρήστες, τμήματα, εξοπλισμός, M2M).
- **callSmartEntityProvider**: κατάσταση «έξυπνης» οντότητας φόρμας κλήσης (καλών, εξοπλισμός, τμήμα, τηλέφωνο, υποψήφιοι, manual flags).
- **taskSmartEntityProvider**: ίδια λογική notifier/state για ροές εκκρεμοτήτων.
- **callHeaderProvider**: alias του `callSmartEntityProvider`.
- **callEntryProvider**: σημειώσεις, κατηγορία, εκκρεμότητα, χρονόμετρο, υποβολή κλήσης/task.
- **notesFieldHintTickProvider**: tick για υπόδειξη πεδίου σημειώσεων.
- **recentCallsProvider**: πρόσφατες κλήσεις ανά `callerId` (`FutureProvider.family`).
- **importLogProvider**: κονσόλα μηνυμάτων import.
- **remoteArgsServiceProvider**, **validRemotePathsProvider**, **remoteLauncherStatusProvider**, **remoteConnectionServiceProvider**, **remoteLauncherServiceProvider**: ορίσματα/διαδρομές VNC–AnyDesk και εκκίνηση απομακρυσμένης σύνδεσης.
- **directoryProvider**: κατάλογος χρηστών (λίστα, φίλτρο, ταξινόμηση, επιλογές, διάταξη στηλών).
- **equipmentDirectoryProvider**: κατάλογος εξοπλισμού με join κάτοχου.
- **catalogContinuousScrollProvider**: ρύθμιση συνεχούς κύλισης πίνακα από `app_settings`.
- **historyFilterProvider**, **historyCallsProvider**, **historyCategoriesProvider**: φίλτρα και δεδομένα ιστορικού κλήσεων.
- **historyTableZoomProvider**: ορίζεται στην οθόνη ιστορικού (`history_screen.dart`) — επίπεδο ζουμ πίνακα.
- **taskServiceProvider**: πρόσβαση σε `TaskService`.
- **taskFilterProvider**: φίλτρα λίστας εκκρεμοτήτων.
- **tasksProvider**: λίστα `Task` (`AsyncNotifier`).
- **taskStatusCountsProvider**: μετρητές ανά status για chips.
- **globalPendingTasksCountProvider**: συνολικό πλήθος εκκρεμοτήτων για badge.
- **orphanCallsProvider**: κλήσεις χωρίς συσχετισμένο task.
- **taskSnoozeConfigProvider**: ρυθμίσεις αναβολών (`TaskSnoozeConfig`).

---

## 5) DEPENDENCIES (`pubspec.yaml`)

**Environment:** `sdk: ^3.10.7`

**Dependencies:** `flutter` (sdk), `flutter_localizations` (sdk), `cupertino_icons: ^1.0.8`, `flutter_riverpod: ^3.2.1`, `sqflite_common_ffi: ^2.3.3`, `sqlite3_flutter_libs: ^0.6.0`, `path_provider: ^2.1.2`, `path: ^1.9.0`, `google_fonts: ^8.0.2`, `intl: ^0.20.2`, `window_manager: ^0.5.1`, `screen_retriever: ^0.2.0`, `shared_preferences: ^2.3.3`, `url_launcher: ^6.3.0`, `excel: ^4.0.6`, `file_picker: ^8.0.0`

**Dev dependencies:** `flutter_test` (sdk), `integration_test` (sdk), `riverpod: ^3.2.1`, `flutter_lints: ^6.0.0`