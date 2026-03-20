# Call Logger — Project Anatomy

**Ημερομηνία τροποποίησης εγγράφου:** 20 Μαρτίου 2026

Συμπυκνωμένη «ακτινογραφία» για εξωτερικό LLM (Καθοδηγητής), με βάση την τρέχουσα δομή του έργου (Flutter, Windows 11, Clean Architecture, Riverpod). Δεν περιέχει αυτούσιο κώδικα.

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
│   ├── theme/
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

*(Αγνοούνται αρχεία `.gitkeep`· ο φάκελος `tool/` βρίσκεται στη ρίζα του project, όχι κάτω από `lib/`.)*

---

## 2) DATABASE SCHEMA (SQLite)

Πηγή: `lib/core/database/database_helper.dart` — `_onCreate` (έκδοση βάσης **13**), συν migrations στο `_onUpgrade`, και one-time `migrateDepartmentsIfNeeded()` για τον πίνακα `departments`.

### Πίνακες από `_onCreate` (νέα εγκατάσταση)

- **calls**
  - `id INTEGER PRIMARY KEY AUTOINCREMENT`
  - `date TEXT`
  - `time TEXT`
  - `caller_id INTEGER`
  - `equipment_id INTEGER`
  - `caller_text TEXT`
  - `phone_text TEXT`
  - `department_text TEXT`
  - `equipment_text TEXT`
  - `issue TEXT`
  - `solution TEXT`
  - `category_text TEXT`
  - `category_id INTEGER`
  - `status TEXT`
  - `duration INTEGER`
  - `is_priority INTEGER DEFAULT 0`

- **users**
  - `id INTEGER PRIMARY KEY AUTOINCREMENT`
  - `last_name TEXT NOT NULL`
  - `first_name TEXT NOT NULL`
  - `phone TEXT`
  - `department_id INTEGER`
  - `location TEXT`
  - `notes TEXT`

- **equipment**
  - `id INTEGER PRIMARY KEY AUTOINCREMENT`
  - `code_equipment TEXT`
  - `type TEXT`
  - `user_id INTEGER`
  - `notes TEXT`
  - `custom_ip TEXT`
  - `anydesk_id TEXT`
  - `default_remote_tool TEXT`

- **categories**
  - `id INTEGER PRIMARY KEY AUTOINCREMENT`
  - `name TEXT`

- **tasks**
  - `id INTEGER PRIMARY KEY AUTOINCREMENT`
  - `title TEXT`
  - `description TEXT`
  - `due_date TEXT`
  - `snooze_history_json TEXT`
  - `status TEXT`
  - `call_id INTEGER`
  - `priority INTEGER`
  - `solution_notes TEXT`
  - `snooze_until TEXT`
  - `caller_id INTEGER` *(μετεγκατάσταση από παλιό `user_id` σε υπάρχουσες βάσεις)*
  - `equipment_id INTEGER`
  - `department_id INTEGER`
  - `phone_id INTEGER`
  - `phone_text TEXT`
  - `user_text TEXT`
  - `equipment_text TEXT`
  - `department_text TEXT`
  - `created_at TEXT`
  - `updated_at TEXT`

- **knowledge_base**
  - `id INTEGER PRIMARY KEY AUTOINCREMENT`
  - `topic TEXT`
  - `content TEXT`
  - `tags TEXT`

- **audit_log**
  - `id INTEGER PRIMARY KEY AUTOINCREMENT`
  - `action TEXT`
  - `timestamp TEXT`
  - `user_performing TEXT`
  - `details TEXT`

- **app_settings**
  - `key TEXT PRIMARY KEY`
  - `value TEXT`

- **remote_tool_args**
  - `id INTEGER PRIMARY KEY AUTOINCREMENT`
  - `tool_name TEXT`
  - `arg_flag TEXT`
  - `description TEXT`
  - `is_active INTEGER DEFAULT 0`

### Πίνακας runtime migration (`migrateDepartmentsIfNeeded`)

- **departments**
  - `id INTEGER PRIMARY KEY AUTOINCREMENT`
  - `name TEXT UNIQUE NOT NULL`
  - `building TEXT`
  - `color TEXT DEFAULT '#1976D2'`
  - `notes TEXT`
  - `map_floor TEXT`
  - `map_x REAL DEFAULT 0.0`
  - `map_y REAL DEFAULT 0.0`
  - `map_width REAL DEFAULT 0.0`
  - `map_height REAL DEFAULT 0.0`

### Σημειώσεις σχήματος (migrations)

- Σε παλιότερες βάσεις μπορεί να υπάρχουν επιπλέον στήλες που προστέθηκαν με `ALTER TABLE`, π.χ. στο **equipment**: `code TEXT`, `description TEXT` — δεν είναι στο βασικό `_onCreate` αλλά μπορεί να εμφανίζονται μετά από αναβάθμιση.
- Ο πίνακας **users** σε πολύ παλιά σχήματα είχε `name` / `department` — η αναβάθμιση τα μετασχηματίζει προς `first_name` / `last_name` και `department_id` (λογική στο `_onUpgrade`).

---

## 3) MODELS (πεδία)

### Calls — `lib/features/calls/models/`

- **CallModel**: `id`, `date`, `time`, `callerId`, `equipmentId`, `callerText`, `phoneText`, `departmentText`, `equipmentText`, `issue`, `solution`, `category`, `status`, `duration`, `isPriority`. *(Στη βάση: `category_text` / `category_id`· το μοντέλο χρησιμοποιεί πεδίο `category` για χάρτη προς/από queries ανάλογα με τη ροή.)*
- **UserModel**: `id`, `firstName`, `lastName`, `phone`, `departmentId`, `notes`· υπολογιζόμενα/βοηθητικά: `name`, `departmentName`, `fullNameWithDepartment`.
- **EquipmentModel**: `id`, `code`, `type`, `notes`, `userId`, `customIp`, `anydeskId`, `defaultRemoteTool`· υπολογιζόμενα: `displayLabel`, `vncTarget`, `anydeskTarget`.

### Directory — `lib/features/directory/models/`

- **DepartmentModel**: `id`, `name`, `building`, `color`, `notes`, `mapFloor`, `mapX`, `mapY`, `mapWidth`, `mapHeight`.
- **EquipmentColumn**: ορισμός στήλης πίνακα UI (`key`, `label`, callbacks `displayValue`, `sortValue`) και στατικές προεπιλογές στηλών.
- **EquipmentRow** (typedef): `(EquipmentModel, UserModel?)` — γραμμή εξοπλισμού με προαιρετικό κάτοχο.

### Tasks — `lib/features/tasks/models/`

- **Task**: `id`, `callId`, `callerId`, `equipmentId`, `departmentId`, `phoneId`, `phoneText`, `userText`, `equipmentText`, `departmentText`, `title`, `description`, `dueDate`, `snoozeUntil`, `snoozeHistoryJson`, `status`, `priority`, `solutionNotes`, `createdAt`, `updatedAt`· υπολογιζόμενα/βοηθητικά: `snoozeEntries`, `snoozeHistory`, `isOverdue`, `isSnoozed`.
- **TaskSnoozeEntry**: `snoozedAt`, `dueAt`.
- **TaskFilter**: `searchQuery`, `statuses`, `startDate`, `endDate`.
- **TaskSnoozeConfig**: `dayEndTime`, `nextBusinessHour`, `skipWeekends`, `defaultSnoozeOption`, `maxSnoozeDays` (αποθήκευση JSON σε `app_settings`).
- **TaskStatus** (enum): `open`, `snoozed`, `closed`.

### Core — `lib/core/models/`

- **RemoteToolArg**: `id`, `toolName`, `argFlag`, `description`, `isActive`.

---

## 4) STATE MANAGEMENT — Βασικοί Providers (Riverpod)

- **`appInitProvider`**: αποτέλεσμα αρχικοποίησης εφαρμογής (σύνδεση βάσης, έλεγχοι εκκίνησης).
- **`showActiveTimerProvider`**, **`showAnyDeskRemoteProvider`**: διακόπτες UI από ρυθμίσεις (`SettingsService`).
- **`lookupServiceProvider`**: ασύγχρονη φόρτωση `LookupService` (cache χρηστών, τμημάτων, εξοπλισμού).
- **`callSmartEntityProvider`**: κατάσταση «έξυπνης» φόρμας κλήσεων (επιλογή καλούντα, εξοπλισμού, τμήματος, τηλεφώνου, συσχετίσεις, κείμενα).
- **`taskSmartEntityProvider`**: αντίστοιχη κατάσταση για οθόνη εκκρεμοτήτων.
- **`callHeaderProvider`**: ίδιο instance με `callSmartEntityProvider` (σταθερό εξωτερικό API / backward compatibility).
- **`callEntryProvider`**: κατάσταση καταχώρισης κλήσης (σημειώσεις, κατηγορία, pending, χρονόμετρο, υποβολή).
- **`recentCallsProvider`**: τελευταίες κλήσεις ανά `caller_id` (οικογένεια `family` με `int`).
- **`importLogProvider`**: κείμενα/κατάσταση κονσόλας import.
- **`remoteArgsServiceProvider`**, **`validRemotePathsProvider`**, **`remoteLauncherStatusProvider`**, **`remoteConnectionServiceProvider`**, **`remoteLauncherServiceProvider`**: διαδρομές εκτελέσιμων και υπηρεσίες απομακρυσμένης σύνδεσης (VNC / AnyDesk).
- **`directoryProvider`**: λίστα/αναζήτηση/ταξινόμηση/επιλογή χρηστών και CRUD/undo στον κατάλογο.
- **`equipmentDirectoryProvider`**: ίδια λογική για εξοπλισμό (στήλες, φίλτρα, επιλογή).
- **`catalogContinuousScrollProvider`**: ρύθμιση συνεχούς κύλισης στον κατάλογο.
- **`historyFilterProvider`**, **`historyCallsProvider`**, **`historyCategoriesProvider`**: φίλτρα και δεδομένα οθόνης ιστορικού κλήσεων.
- **`taskServiceProvider`**: πρόσβαση στο `TaskService`.
- **`taskFilterProvider`**, **`tasksProvider`**, **`orphanCallsProvider`**: φίλτρα εκκρεμοτήτων, λίστα tasks, «ορφανές» κλήσεις χωρίς task.
- **`taskSnoozeConfigProvider`**: φόρτωση/αποθήκευση `TaskSnoozeConfig`.

---

## 5) DEPENDENCIES (`pubspec.yaml`)

**Environment**

- `sdk: ^3.10.7`

**Dependencies**

- `flutter` (sdk)
- `flutter_localizations` (sdk)
- `cupertino_icons: ^1.0.8`
- `flutter_riverpod: ^3.2.1`
- `sqflite_common_ffi: ^2.3.3`
- `sqlite3_flutter_libs: ^0.6.0`
- `path_provider: ^2.1.2`
- `path: ^1.9.0`
- `google_fonts: ^8.0.2`
- `intl: ^0.20.2`
- `window_manager: ^0.5.1`
- `screen_retriever: ^0.2.0`
- `shared_preferences: ^2.3.3`
- `url_launcher: ^6.3.0`
- `excel: ^4.0.6`
- `file_picker: ^8.0.0`

**Dev dependencies**

- `flutter_test` (sdk)
- `flutter_lints: ^6.0.0`
