# Call Logger — Project Anatomy

**Ημερομηνία τροποποίησης εγγράφου:** 27 Μαρτίου 2026

Συμπυκνωμένη «ακτινογραφία» για εξωτερικό LLM (Καθοδηγητής): Flutter για Windows 11, Καθαρή Αρχιτεκτονική (Clean Architecture) ανά `features/`, διαχείριση κατάστασης με Riverpod.

---

## 1) DIRTREE (`lib/`)

```text
lib/
├── main.dart
├── core/
│   ├── config/
│   ├── database/
│   │   ├── database_helper.dart
│   │   ├── database_init_result.dart
│   │   ├── database_init_runner.dart
│   │   └── database_v1_schema.dart
│   ├── errors/
│   ├── init/
│   │   ├── app_init_provider.dart
│   │   └── app_initializer.dart
│   ├── models/
│   ├── providers/
│   │   ├── greek_dictionary_provider.dart
│   │   ├── settings_provider.dart
│   │   └── spell_check_provider.dart
│   ├── services/
│   ├── utils/
│   └── widgets/
│       ├── app_init_wrapper.dart
│       ├── app_shell_with_global_fatal_error.dart
│       ├── app_shortcuts.dart
│       ├── database_error_screen.dart
│       ├── global_fatal_error_notifier.dart
│       ├── lexicon_spell_text_form_field.dart
│       ├── main_shell.dart
│       └── spell_check_controller.dart
└── features/
    ├── calls/
    │   ├── models/
    │   ├── provider/
    │   └── screens/
    │       └── widgets/
    ├── database/
    │   └── screens/
    ├── directory/
    │   ├── models/
    │   ├── providers/
    │   └── screens/
    │       └── widgets/
    ├── history/
    │   ├── providers/
    │   └── screens/
    ├── settings/
    │   ├── screens/
    │   └── widgets/
    └── tasks/
        ├── models/
        ├── providers/
        ├── screens/
        └── services/
```

---

## 2) DATABASE SCHEMA (SQLite)

**Πηγές:** `lib/core/database/database_v1_schema.dart` + `lib/core/database/database_helper.dart`  
**Τρέχουσα έκδοση σχήματος (schema version):** `6`

> Τα παρακάτω είναι τα ακριβή tables/columns/types όπως ορίζονται στο `CREATE TABLE` του `applyDatabaseV1Schema`.

| Πίνακας | Στήλες (column → type) |
|---|---|
| `calls` | `id` INTEGER, `date` TEXT, `time` TEXT, `caller_id` INTEGER, `equipment_id` INTEGER, `caller_text` TEXT, `phone_text` TEXT, `department_text` TEXT, `equipment_text` TEXT, `issue` TEXT, `solution` TEXT, `category_text` TEXT, `category_id` INTEGER, `status` TEXT, `duration` INTEGER, `is_priority` INTEGER, `search_index` TEXT, `is_deleted` INTEGER |
| `users` | `id` INTEGER, `last_name` TEXT, `first_name` TEXT, `department_id` INTEGER, `location` TEXT, `notes` TEXT, `is_deleted` INTEGER |
| `phones` | `id` INTEGER, `number` TEXT, `department_id` INTEGER |
| `department_phones` | `department_id` INTEGER, `phone_id` INTEGER |
| `user_phones` | `user_id` INTEGER, `phone_id` INTEGER |
| `equipment` | `id` INTEGER, `code_equipment` TEXT, `type` TEXT, `notes` TEXT, `custom_ip` TEXT, `anydesk_id` TEXT, `default_remote_tool` TEXT, `department_id` INTEGER, `location` TEXT, `is_deleted` INTEGER |
| `user_equipment` | `user_id` INTEGER, `equipment_id` INTEGER |
| `departments` | `id` INTEGER, `name` TEXT, `name_key` TEXT, `building` TEXT, `color` TEXT, `notes` TEXT, `map_floor` TEXT, `map_x` REAL, `map_y` REAL, `map_width` REAL, `map_height` REAL, `is_deleted` INTEGER |
| `categories` | `id` INTEGER, `name` TEXT, `is_deleted` INTEGER |
| `tasks` | `id` INTEGER, `title` TEXT, `description` TEXT, `due_date` TEXT, `snooze_history_json` TEXT, `status` TEXT, `call_id` INTEGER, `priority` INTEGER, `solution_notes` TEXT, `snooze_until` TEXT, `caller_id` INTEGER, `equipment_id` INTEGER, `department_id` INTEGER, `phone_id` INTEGER, `phone_text` TEXT, `user_text` TEXT, `equipment_text` TEXT, `department_text` TEXT, `created_at` TEXT, `updated_at` TEXT, `search_index` TEXT, `is_deleted` INTEGER |
| `knowledge_base` | `id` INTEGER, `topic` TEXT, `content` TEXT, `tags` TEXT |
| `audit_log` | `id` INTEGER, `action` TEXT, `timestamp` TEXT, `user_performing` TEXT, `details` TEXT |
| `app_settings` | `key` TEXT, `value` TEXT |
| `remote_tool_args` | `id` INTEGER, `tool_name` TEXT, `arg_flag` TEXT, `description` TEXT, `is_active` INTEGER |
| `user_dictionary` | `word` TEXT |

---

## 3) MODELS

### `lib/features/calls/models/`

- **CallModel:** `id`, `date`, `time`, `callerId`, `equipmentId`, `callerText`, `phoneText`, `departmentText`, `equipmentText`, `issue`, `solution`, `category`, `status`, `duration`, `isPriority`, `isDeleted`.
- **UserModel:** `id`, `firstName`, `lastName`, `phones`, `departmentId`, `location`, `notes`, `isDeleted`.
- **EquipmentModel:** `id`, `code`, `type`, `notes`, `customIp`, `anydeskId`, `defaultRemoteTool`, `departmentId`, `location`, `isDeleted`.

### `lib/features/directory/models/`

- **DepartmentModel:** `id`, `name`, `building`, `color`, `notes`, `mapFloor`, `mapX`, `mapY`, `mapWidth`, `mapHeight`, `directPhones`, `isDeleted`.
- **UserDirectoryColumn:** μεταδεδομένα στήλης (`key`, `label`, `sortKey`) για table χρηστών.
- **DepartmentDirectoryColumn:** μεταδεδομένα στήλης (`key`, `label`, `sortKey`) για table τμημάτων.
- **EquipmentColumn:** μεταδεδομένα στήλης (`key`, `label`, `displayValue`, `sortValue`) και alias γραμμής `EquipmentRow = (EquipmentModel, UserModel?)`.

### `lib/features/tasks/models/`

- **Task:** `id`, `callId`, `callerId`, `equipmentId`, `departmentId`, `phoneId`, `phoneText`, `userText`, `equipmentText`, `departmentText`, `title`, `description`, `dueDate`, `snoozeUntil`, `snoozeHistoryJson`, `status`, `priority`, `solutionNotes`, `createdAt`, `updatedAt`, `isDeleted`.
- **TaskStatus (enum):** `open`, `snoozed`, `closed`.
- **TaskSnoozeEntry:** `snoozedAt`, `dueAt`.
- **TaskFilter:** `searchQuery`, `statuses`, `startDate`, `endDate`, `sortBy`, `sortAscending`.
- **TaskSortOption (enum):** `createdAt`, `dueAt`, `priority`, `department`, `user`, `equipment`.
- **TaskSettingsConfig:** `dayEndTime`, `nextBusinessHour`, `skipWeekends`, `defaultSnoozeOption`, `maxSnoozeDays`, `autoCloseQuickAdds`.

### Άλλα μοντέλα πυρήνα

- **RemoteToolArg** (`lib/core/models/remote_tool_arg.dart`): `id`, `toolName`, `argFlag`, `description`, `isActive`.
- **HistoryFilterModel** (`lib/features/history/providers/history_provider.dart`): `keyword`, `dateFrom`, `dateTo`, `category`.

---

## 4) STATE MANAGEMENT — PROVIDERS (Riverpod)

- **`appInitProvider`**: αρχικοποίηση εφαρμογής (βάση, λεξικό ορθογραφίας, υπηρεσίες).
- **`greekDictionaryServiceProvider`, `spellCheckServiceProvider`**: φόρτωση λεξικού και υπηρεσίας ορθογραφίας (spell check).
- **`showActiveTimerProvider`, `showAnyDeskRemoteProvider`, `showTasksBadgeProvider`, `enableSpellCheckProvider`**: UI settings από `SettingsService`.
- **`lookupServiceProvider`**: preload/lookups για users, phones, departments, equipment.
- **`callSmartEntityProvider`, `taskSmartEntityProvider`, `callHeaderProvider`**: κατάσταση έξυπνης επιλογής οντοτήτων στη φόρμα.
- **`callEntryProvider`**: κατάσταση/υποβολή φόρμας κλήσης (notes, category, timer, save).
- **`notesFieldHintTickProvider`, `recentCallsProvider`, `importLogProvider`**: βοηθητική κατάσταση κλήσεων.
- **`remoteArgsServiceProvider`, `validRemotePathsProvider`, `remoteLauncherStatusProvider`, `remoteConnectionServiceProvider`, `remoteLauncherServiceProvider`**: απομακρυσμένη σύνδεση (VNC/AnyDesk).
- **`directoryProvider`, `departmentDirectoryProvider`, `equipmentDirectoryProvider`, `catalogContinuousScrollProvider`**: κατάσταση καταλόγων (πίνακες, φίλτρα, επιλογές, CRUD).
- **`historyFilterProvider`, `historyCallsProvider`, `historyCategoriesProvider`**: φίλτρα/δεδομένα ιστορικού κλήσεων.
- **`taskServiceProvider`, `taskFilterProvider`, `tasksProvider`, `taskStatusCountsProvider`, `globalPendingTasksCountProvider`, `orphanCallsProvider`, `taskSettingsConfigProvider`**: ροή εκκρεμοτήτων (tasks list, φίλτρα, counters, ρυθμίσεις).

---

## 5) DEPENDENCIES (`pubspec.yaml`)

- **Dart SDK:** `^3.10.7`
- **Κύριες βιβλιοθήκες (runtime):**
  - `flutter_riverpod: ^3.2.1`
  - `sqflite_common: ^2.5.6`
  - `sqflite_common_ffi: ^2.3.3`
  - `sqlite3_flutter_libs: ^0.6.0`
  - `shared_preferences: ^2.3.3`
  - `window_manager: ^0.5.1`
  - `screen_retriever: ^0.2.0`
  - `path: ^1.9.0`, `path_provider: ^2.1.2`
  - `intl: ^0.20.2`
  - `excel: ^4.0.6`
  - `file_picker: ^8.0.0`
  - `url_launcher: ^6.3.0`
  - `google_fonts: ^8.0.2`
  - `cupertino_icons: ^1.0.8`
- **Dev dependencies:**
  - `riverpod: ^3.2.1`
  - `flutter_lints: ^6.0.0`
  - `flutter_test` (sdk), `integration_test` (sdk)
