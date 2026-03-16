# Call Logger — Project Anatomy

**Ημερομηνία τροποποίησης:** 16 Μαρτίου 2026  

Συμπυκνωμένη «ακτινογραφία» του project για τροφοδότηση σε εξωτερικό LLM (Καθοδηγητής). Flutter Desktop (Windows 11), Clean Architecture, Riverpod.

---

## 1. DIRTREE (Δομή φακέλων `lib/`)

Καθαρό δέντρο μόνο του `lib/`. Αγνοούνται build, android, ios, windows, test.

```
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
│   ├── utils/
│   │   ├── name_parser.dart
│   │   ├── phone_list_parser.dart
│   │   └── search_text_normalizer.dart
│   └── widgets/
│       ├── app_init_wrapper.dart
│       ├── app_shortcuts.dart
│       ├── database_error_screen.dart
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
    │   │   └── remote_paths_provider.dart
    │   └── screens/
    │       ├── calls_screen.dart
    │       └── widgets/
    │           ├── call_header_form.dart
    │           ├── call_status_bar.dart
    │           ├── import_console_widget.dart
    │           ├── recent_calls_list.dart
    │           ├── sticky_note_widget.dart
    │           └── user_info_card.dart
    ├── database/
    │   └── screens/
    │       └── database_browser_screen.dart
    ├── directory/
    │   ├── models/
    │   │   └── equipment_column.dart
    │   ├── providers/
    │   │   ├── directory_provider.dart
    │   │   └── equipment_directory_provider.dart
    │   └── screens/
    │       ├── directory_screen.dart
    │       └── widgets/
    │           ├── bulk_equipment_edit_dialog.dart
    │           ├── bulk_user_edit_dialog.dart
    │           ├── equipment_data_table.dart
    │           ├── equipment_form_dialog.dart
    │           ├── equipment_tab.dart
    │           ├── user_form_dialog.dart
    │           ├── users_data_table.dart
    │           └── users_tab.dart
    ├── settings/
    │   ├── screens/
    │   │   └── settings_screen.dart
    │   └── widgets/
    │       └── remote_args_editor.dart
    └── tasks/
        ├── models/
        │   ├── task.dart
        │   └── task_filter.dart
        ├── providers/
        │   ├── task_service_provider.dart
        │   └── tasks_provider.dart
        ├── screens/
        │   ├── task_card.dart
        │   ├── task_close_dialog.dart
        │   ├── task_filter_bar.dart
        │   ├── task_form_dialog.dart
        │   └── tasks_screen.dart
        └── services/
            └── task_service.dart
```

---

## 2. Σχήμα Βάσης Δεδομένων (DATABASE SCHEMA)

Πηγή: `lib/core/database/database_helper.dart`. Έκδοση σχήματος: **8**. Τελικές στήλες μετά από _onCreate και migrations (_onUpgrade).

| Πίνακας | Στήλες (όνομα → τύπος) |
|--------|-------------------------|
| **calls** | id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, time TEXT, caller_id INTEGER, equipment_id INTEGER, issue TEXT, solution TEXT, category TEXT, status TEXT, duration INTEGER, is_priority INTEGER DEFAULT 0, caller_text TEXT |
| **users** | id INTEGER PRIMARY KEY AUTOINCREMENT, last_name TEXT NOT NULL, first_name TEXT NOT NULL, phone TEXT, department TEXT, location TEXT, notes TEXT |
| **equipment** | id INTEGER PRIMARY KEY AUTOINCREMENT, code_equipment TEXT, type TEXT, user_id INTEGER, notes TEXT, custom_ip TEXT, anydesk_id TEXT, default_remote_tool TEXT, code TEXT, description TEXT |
| **categories** | id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT |
| **tasks** | id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, description TEXT, due_date TEXT, status TEXT, call_id INTEGER, priority INTEGER, solution_notes TEXT, snooze_until TEXT, user_id INTEGER, equipment_id INTEGER, created_at TEXT, updated_at TEXT |
| **knowledge_base** | id INTEGER PRIMARY KEY AUTOINCREMENT, topic TEXT, content TEXT, tags TEXT |
| **audit_log** | id INTEGER PRIMARY KEY AUTOINCREMENT, action TEXT, timestamp TEXT, user_performing TEXT, details TEXT |
| **app_settings** | key TEXT PRIMARY KEY, value TEXT |
| **remote_tool_args** | id INTEGER PRIMARY KEY AUTOINCREMENT, tool_name TEXT, arg_flag TEXT, description TEXT, is_active INTEGER DEFAULT 0 |

Σημείωση: Στον πίνακα **equipment** η κύρια στήλη κωδικού στη βάση είναι `code_equipment`· στα μοντέλα χρησιμοποιείται πεδίο `code` (αντιστοίχιση στο fromMap/toMap).

---

## 3. Μοντέλα (MODELS)

**Θέση:** `lib/features/calls/models/` (CallModel, UserModel, EquipmentModel), `lib/features/directory/models/` (EquipmentColumn, EquipmentRow), `lib/features/tasks/models/` (Task, TaskStatus, TaskFilter), `lib/core/models/` (RemoteToolArg).

- **CallModel**  
  id, date, time, callerId, equipmentId, callerText, issue, solution, category, status, duration, isPriority. fromMap/toMap με snake_case κλειδιά.

- **UserModel**  
  id, firstName, lastName, phone, department, location, notes. Υπολογιζόμενα: name (first + last), fullNameWithDepartment. fromMap υποστηρίζει και παλιό πεδίο `name`.

- **EquipmentModel**  
  id, code (αντιστοιχία με code_equipment), type, notes, userId, customIp, anydeskId, defaultRemoteTool. Υπολογιζόμενα: displayLabel, vncTarget, anydeskTarget. fromMap/toMap με code_equipment.

- **EquipmentColumn**  
  Ορισμός στήλης πίνακα εξοπλισμού: key, label, displayValue(EquipmentRow), sortValue(EquipmentRow). Στατικές σταθερές: code, type, owner, location, phone, notes, customIp, anydeskId, defaultRemote· defaults, all.

- **EquipmentRow**  
  Typedef: (EquipmentModel, UserModel?) — γραμμή πίνακα = εξοπλισμός + κάτοχος.

- **Task**  
  id, callId, userId, equipmentId, title, description, dueDate, snoozeUntil, status, priority, solutionNotes, createdAt, updatedAt. Enum TaskStatus: open, snoozed, closed.

- **TaskFilter**  
  searchQuery, statuses (List<TaskStatus>), startDate, endDate. Για φιλτράρισμα λίστας εκκρεμοτήτων.

- **RemoteToolArg**  
  id, toolName, argFlag, description, isActive. Ορίσματα γραμμής εντολών για VNC/AnyDesk· placeholders {TARGET}, {PASSWORD}.

---

## 4. Διαχείριση Κατάστασης — Πάροχοι (STATE MANAGEMENT — Providers)

| Πάροχος | Τύπος / Θέση | Τι διαχειρίζει |
|---------|----------------|----------------|
| **appInitProvider** | FutureProvider, core/init | Αποτέλεσμα αρχικοποίησης εφαρμογής (DB, success/fail). Τρέχει μία φορά στην εκκίνηση. |
| **callHeaderProvider** | NotifierProvider, features/calls/provider | Κατάσταση header φόρμας κλήσης: επιλεγμένο τηλέφωνο/χρήστη/εξοπλισμό, λίστες candidates, σφάλματα, flags (ambiguous, no-match), κείμενα εμφάνισης. |
| **callEntryProvider** | NotifierProvider, features/calls/provider | Κατάσταση φόρμας εισαγωγής κλήσης: internal digits, selected user/equipment, notes, category, controllers/focus, χρονομέτρηση. |
| **lookupServiceProvider** | FutureProvider, features/calls/provider | Φόρτωση LookupService μία φορά· cache για αναζήτηση χρηστών/εξοπλισμού από τη βάση. |
| **remoteArgsServiceProvider** | Provider, features/calls/provider | Singleton RemoteArgsService (CRUD ορίσματα VNC/AnyDesk στη βάση). |
| **validRemotePathsProvider** | FutureProvider, features/calls/provider | Έγκυρες διαδρομές VNC και AnyDesk (για απενεργοποίηση κουμπιών / tooltip). |
| **remoteLauncherStatusProvider** | FutureProvider, features/calls/provider | Κατάσταση εκκινητών VNC/AnyDesk: διαδρομή και μήνυμα σφάλματος όταν απενεργό. |
| **remoteConnectionServiceProvider** | Provider, features/calls/provider | Singleton για RemoteConnectionService (εκκίνηση VNC/AnyDesk με target/password). |
| **remoteLauncherServiceProvider** | Provider, features/calls/provider | Singleton για RemoteLauncherService (εκκίνηση χωρίς παραμέτρους, testToolArguments). |
| **recentCallsProvider(userId)** | FutureProvider.family, features/calls/provider | Τελευταίες κλήσεις ανά caller_id για προβολή στο πεδίο καλούντος. |
| **importLogProvider** | NotifierProvider, features/calls/provider | Λίστα ImportLogEntry (μηνύματα + level) για Live Console Import Excel· addLog / clearLogs. |
| **directoryProvider** | NotifierProvider.autoDispose, features/directory/providers | Κατάσταση κατάλογου χρηστών: allUsers, filteredUsers, searchQuery, sort, selectedIds, undo (lastDeleted, lastBulkUpdatedUsers), focusedRowIndex. |
| **equipmentDirectoryProvider** | NotifierProvider.autoDispose, features/directory/providers | Κατάσταση κατάλογου εξοπλισμού: allItems, filteredItems, visibleColumns, searchQuery, sort, selectedIds, undo, focusedRowIndex. |
| **catalogContinuousScrollProvider** | FutureProvider.autoDispose, features/directory/providers | Flag «συνεχής κύλιση» πίνακα Καταλόγου (από app_settings). |
| **showActiveTimerProvider** | FutureProvider, core/providers | Ρύθμιση εμφάνισης ενεργού χρονομέτρου στη φόρμα κλήσεων (από SettingsService). |
| **taskServiceProvider** | Provider, features/tasks/providers | Singleton TaskService (CRUD tasks στη βάση). |
| **taskFilterProvider** | NotifierProvider, features/tasks/providers | Κριτήρια φιλτραρίσματος εκκρεμοτήτων: searchQuery, statuses, startDate, endDate. |
| **tasksProvider** | AsyncNotifierProvider, features/tasks/providers | Λίστα εργασιών (Task) με βάση το taskFilterProvider· refresh από TaskService. |
| **orphanCallsProvider** | FutureProvider, features/tasks/providers | Κλήσεις χωρίς αντίστοιχο task (για οθόνη εκκρεμοτήτων). |

---

## 5. Εξαρτήσεις (DEPENDENCIES)

Από `pubspec.yaml` (μόνο dependencies):

- **flutter** (sdk)
- **flutter_localizations** (sdk)
- **cupertino_icons** ^1.0.8
- **flutter_riverpod** ^3.2.1
- **sqflite_common_ffi** ^2.3.3
- **sqlite3_flutter_libs** ^0.6.0
- **path_provider** ^2.1.2
- **path** ^1.9.0
- **google_fonts** ^8.0.2
- **intl** ^0.20.2
- **window_manager** ^0.5.1
- **screen_retriever** ^0.2.0
- **shared_preferences** ^2.3.3
- **url_launcher** ^6.3.0
- **excel** ^4.0.6
- **file_picker** ^8.0.0

**dev_dependencies:** flutter_test (sdk), flutter_lints ^6.0.0  

**environment.sdk:** ^3.10.7
