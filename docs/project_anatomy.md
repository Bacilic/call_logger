# Call Logger — Project Anatomy

**Ημερομηνία τροποποίησης εγγράφου:** 21 Μαρτίου 2026

Συμπυκνωμένη «ακτινογραφία» για εξωτερικό LLM (Καθοδηγητής), με βάση την τρέχουσα δομή του έργου (Flutter Windows, Clean Architecture, Riverpod). Δεν περιέχει αυτούσιο κώδικα.

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
│   ├── utils/
│   │   ├── name_parser.dart
│   │   ├── phone_list_parser.dart
│   │   ├── search_text_normalizer.dart
│   │   └── spell_check.dart
│   └── widgets/
│       ├── app_init_wrapper.dart
│       ├── app_shortcuts.dart
│       ├── database_error_screen.dart
│       └── main_shell.dart
├── features/
│   ├── calls/
│   │   ├── models/
│   │   │   ├── call_model.dart
│   │   │   ├── equipment_model.dart
│   │   │   └── user_model.dart
│   │   ├── provider/
│   │   │   ├── call_entry_provider.dart
│   │   │   ├── call_header_provider.dart
│   │   │   ├── import_log_provider.dart
│   │   │   ├── lookup_provider.dart
│   │   │   ├── notes_field_hint_provider.dart
│   │   │   ├── remote_paths_provider.dart
│   │   │   └── smart_entity_selector_provider.dart
│   │   └── screens/
│   │       ├── calls_screen.dart
│   │       └── widgets/
│   │           ├── call_header_form.dart
│   │           ├── call_status_bar.dart
│   │           ├── category_autocomplete_field.dart
│   │           ├── equipment_info_card.dart
│   │           ├── import_console_widget.dart
│   │           ├── notes_sticky_field.dart
│   │           ├── recent_calls_list.dart
│   │           ├── remote_connection_buttons.dart
│   │           ├── smart_entity_selector_widget.dart
│   │           ├── sticky_note_widget.dart
│   │           └── user_info_card.dart
│   ├── database/
│   │   └── screens/
│   │       └── database_browser_screen.dart
│   ├── directory/
│   │   ├── models/
│   │   │   ├── department_model.dart
│   │   │   └── equipment_column.dart
│   │   ├── providers/
│   │   │   ├── directory_provider.dart
│   │   │   └── equipment_directory_provider.dart
│   │   └── screens/
│   │       ├── directory_screen.dart
│   │       └── widgets/
│   │           ├── bulk_equipment_edit_dialog.dart
│   │           ├── bulk_user_edit_dialog.dart
│   │           ├── equipment_data_table.dart
│   │           ├── equipment_form_dialog.dart
│   │           ├── equipment_tab.dart
│   │           ├── user_form_dialog.dart
│   │           ├── users_data_table.dart
│   │           └── users_tab.dart
│   ├── history/
│   │   ├── providers/
│   │   │   └── history_provider.dart
│   │   └── screens/
│   │       └── history_screen.dart
│   ├── settings/
│   │   ├── screens/
│   │   │   └── settings_screen.dart
│   │   └── widgets/
│   │       └── remote_args_editor.dart
│   └── tasks/
│       ├── models/
│       │   ├── task.dart
│       │   ├── task_filter.dart
│       │   └── task_snooze_config.dart
│       ├── providers/
│       │   ├── task_service_provider.dart
│       │   ├── task_snooze_config_provider.dart
│       │   └── tasks_provider.dart
│       ├── screens/
│       │   ├── task_card.dart
│       │   ├── task_close_dialog.dart
│       │   ├── task_filter_bar.dart
│       │   ├── task_form_dialog.dart
│       │   ├── task_snooze_settings_dialog.dart
│       │   └── tasks_screen.dart
│       └── services/
│           └── task_service.dart
```

*(Ο φάκελος `tool/` βρίσκεται στη ρίζα του repo, όχι κάτω από `lib/`.)*

---

## 2) DATABASE SCHEMA (SQLite)

Πηγή: `lib/core/database/database_helper.dart` — `_onCreate` (έκδοση βάσης **13**), `_onUpgrade`, one-time `migrateDepartmentsIfNeeded()`, και runtime `_ensureTasksSearchIndexColumnAndBackfill()` (προσθήκη `search_index` σε υπάρχουσες βάσεις χωρίς αύξηση `user_version`).

### Πίνακες από `_onCreate` (νέα εγκατάσταση)

- **calls**  
`id` INTEGER PK AI, `date` TEXT, `time` TEXT, `caller_id` INTEGER, `equipment_id` INTEGER, `caller_text` TEXT, `phone_text` TEXT, `department_text` TEXT, `equipment_text` TEXT, `issue` TEXT, `solution` TEXT, `category_text` TEXT, `category_id` INTEGER, `status` TEXT, `duration` INTEGER, `is_priority` INTEGER DEFAULT 0
- **users**  
`id` INTEGER PK AI, `last_name` TEXT NOT NULL, `first_name` TEXT NOT NULL, `phone` TEXT, `department_id` INTEGER, `location` TEXT, `notes` TEXT
- **equipment**  
`id` INTEGER PK AI, `code_equipment` TEXT, `type` TEXT, `user_id` INTEGER, `notes` TEXT, `custom_ip` TEXT, `anydesk_id` TEXT, `default_remote_tool` TEXT
- **categories**  
`id` INTEGER PK AI, `name` TEXT
- **tasks**  
`id` INTEGER PK AI, `title` TEXT, `description` TEXT, `due_date` TEXT, `snooze_history_json` TEXT, `status` TEXT, `call_id` INTEGER, `priority` INTEGER, `solution_notes` TEXT, `snooze_until` TEXT, `caller_id` INTEGER, `equipment_id` INTEGER, `department_id` INTEGER, `phone_id` INTEGER, `phone_text` TEXT, `user_text` TEXT, `equipment_text` TEXT, `department_text` TEXT, `created_at` TEXT, `updated_at` TEXT, `**search_index` TEXT** (κανονικοποιημένο κείμενο αναζήτησης)
- **knowledge_base**  
`id` INTEGER PK AI, `topic` TEXT, `content` TEXT, `tags` TEXT
- **audit_log**  
`id` INTEGER PK AI, `action` TEXT, `timestamp` TEXT, `user_performing` TEXT, `details` TEXT
- **app_settings**  
`key` TEXT PK, `value` TEXT
- **remote_tool_args**  
`id` INTEGER PK AI, `tool_name` TEXT, `arg_flag` TEXT, `description` TEXT, `is_active` INTEGER DEFAULT 0

### Πίνακας `departments` (`migrateDepartmentsIfNeeded`)

`id` INTEGER PK AI, `name` TEXT UNIQUE NOT NULL, `building` TEXT, `color` TEXT DEFAULT '#1976D2', `notes` TEXT, `map_floor` TEXT, `map_x` REAL DEFAULT 0.0, `map_y` REAL DEFAULT 0.0, `map_width` REAL DEFAULT 0.0, `map_height` REAL DEFAULT 0.0

### Σημειώσεις σχήματος

- Σε **παλιότερες** βάσεις μπορεί να υπάρχουν επιπλέον στήλες από `ALTER` (π.χ. **equipment**: `code` TEXT, `description` TEXT) — όχι στο καθαρό `_onCreate`.
- **users**: πολύ παλιά σχήματα με `name` / `department` μετασχηματίζονται σε `first_name` / `last_name` και `department_id` μέσω migrations.
- **tasks.caller_id**: σε migrations αντικαθιστά παλιό `user_id` όπου υπήρχε.

---

## 3) MODELS (πεδία)

### Calls — `lib/features/calls/models/`

- **CallModel**: `id`, `date`, `time`, `callerId`, `equipmentId`, `callerText`, `phoneText`, `departmentText`, `equipmentText`, `issue`, `solution`, `category`, `status`, `duration`, `isPriority`.
- **UserModel**: `id`, `firstName`, `lastName`, `phone`, `departmentId`, `notes`· getters: `name`, `departmentName`, `fullNameWithDepartment`.
- **EquipmentModel**: `id`, `code` (↔ `code_equipment`), `type`, `notes`, `userId`, `customIp`, `anydeskId`, `defaultRemoteTool`· getters: `displayLabel`, `vncTarget`, `anydeskTarget`.

### Directory — `lib/features/directory/models/`

- **DepartmentModel**: `id`, `name`, `building`, `color`, `notes`, `mapFloor`, `mapX`, `mapY`, `mapWidth`, `mapHeight`.
- **EquipmentColumn**: `key`, `label`, `displayValue(EquipmentRow)`, `sortValue(EquipmentRow)?` — ορισμός στηλών πίνακα UI.
- **EquipmentRow** (typedef): `(EquipmentModel, UserModel?)`.

### Tasks — `lib/features/tasks/models/`

- **Task**: `id`, `callId`, `callerId`, `equipmentId`, `departmentId`, `phoneId`, `phoneText`, `userText`, `equipmentText`, `departmentText`, `title`, `description`, `dueDate`, `snoozeUntil`, `snoozeHistoryJson`, `status`, `priority`, `solutionNotes`, `createdAt`, `updatedAt`· getters/helpers: `combinedSearchText`, `snoozeEntries`, `snoozeHistory`, `isOverdue`, `isSnoozed`, `dueDateTime`, κ.λπ.
- **TaskStatus** (enum): `open`, `snoozed`, `closed`.
- **TaskSnoozeEntry**: `snoozedAt`, `dueAt`.
- **TaskFilter**: `searchQuery`, `statuses`, `startDate`, `endDate`, `**sortBy` (TaskSortOption)**, `**sortAscending*`*· getters: `allFiltersOff`.
- **TaskSortOption** (enum): `createdAt`, `dueAt`, `priority`, `department`, `user`, `equipment`.
- **TaskSnoozeConfig**: `dayEndTime`, `nextBusinessHour`, `skipWeekends`, `defaultSnoozeOption`, `maxSnoozeDays` (JSON σε `app_settings`).

### Core — `lib/core/models/`

- **RemoteToolArg**: `id`, `toolName`, `argFlag`, `description`, `isActive`.

---

## 4) STATE MANAGEMENT — Βασικοί Providers (Riverpod)

- `**appInitProvider`**: αποτέλεσμα εκκίνησης (σύνδεση βάσης, έλεγχοι).
- `**showActiveTimerProvider**`, `**showAnyDeskRemoteProvider**`, `**showTasksBadgeProvider**`: διακόπτες από `SharedPreferences` / ρυθμίσεις (χρονόμετρο φόρμας κλήσης, AnyDesk, badge εκκρεμοτήτων στο μενού).
- `**lookupServiceProvider**`: φόρτωση `LookupService` (cache χρηστών, τμημάτων, εξοπλισμού).
- `**callSmartEntityProvider**`: «έξυπνη» φόρμα κλήσης (καλών, εξοπλισμός, τμήμα, τηλέφωνο, κείμενα, συσχετίσεις).
- `**taskSmartEntityProvider**`: αντίστοιχη κατάσταση για εκκρεμότητες.
- `**callHeaderProvider**`: alias του `callSmartEntityProvider`.
- `**callEntryProvider**`: σημειώσεις, κατηγορία, pending checkbox, χρονόμετρο, υποβολή κλήσης/εκκρεμότητας.
- `**notesFieldHintTickProvider**`: σήμα για οπτική υπόδειξη πεδίου σημειώσεων (ανενεργό checkbox εκκρεμότητας).
- `**recentCallsProvider**`: πρόσφατες κλήσεις ανά `callerId` (`FutureProvider.family`).
- `**importLogProvider**`: γραμμές κονσόλας import.
- `**remoteArgsServiceProvider**`, `**validRemotePathsProvider**`, `**remoteLauncherStatusProvider**`, `**remoteConnectionServiceProvider**`, `**remoteLauncherServiceProvider**`: διαδρομές VNC/AnyDesk και εκκίνηση απομακρυσμένης σύνδεσης.
- `**directoryProvider**`: κατάλογος χρηστών (λίστα, αναζήτηση, ταξινόμηση, επιλογή, CRUD).
- `**equipmentDirectoryProvider**`: κατάλογος εξοπλισμού (ίδια ιδέα).
- `**catalogContinuousScrollProvider**`: συνεχής κύλιση πίνακα καταλόγου (`app_settings`).
- `**historyFilterProvider**`, `**historyCallsProvider**`, `**historyCategoriesProvider**`: ιστορικό κλήσεων.
- `**historyTableZoomProvider**`: επίπεδο ζουμ πίνακα στην οθόνη ιστορικού (`autoDispose`).
- `**taskServiceProvider**`: `TaskService`.
- `**taskFilterProvider**`: φίλτρα λίστας εκκρεμοτήτων (κείμενο, statuses, ημερομηνίες, ταξινόμηση).
- `**tasksProvider**`: λίστα tasks ανά φίλτρο (`AsyncNotifier`).
- `**taskStatusCountsProvider**`: πλήθη ανά status για chips (ίδια φίλτρα αναζήτησης/ημερομηνίας, χωρίς status filter).
- `**globalPendingTasksCountProvider**`: συνολικό πλήθος open+snoozed για badge μενού (εξαρτάται από `tasksProvider`).
- `**orphanCallsProvider**`: κλήσεις pending χωρίς task.
- `**taskSnoozeConfigProvider**`: ρυθμίσεις αναβολών (`TaskSnoozeConfig`).

---

## 5) DEPENDENCIES (`pubspec.yaml`)

**Environment:** `sdk: ^3.10.7`

**Dependencies:** `flutter` (sdk), `flutter_localizations` (sdk), `cupertino_icons: ^1.0.8`, `flutter_riverpod: ^3.2.1`, `sqflite_common_ffi: ^2.3.3`, `sqlite3_flutter_libs: ^0.6.0`, `path_provider: ^2.1.2`, `path: ^1.9.0`, `google_fonts: ^8.0.2`, `intl: ^0.20.2`, `window_manager: ^0.5.1`, `screen_retriever: ^0.2.0`, `shared_preferences: ^2.3.3`, `url_launcher: ^6.3.0`, `excel: ^4.0.6`, `file_picker: ^8.0.0`

**Dev:** `flutter_test` (sdk), `flutter_lints: ^6.0.0`