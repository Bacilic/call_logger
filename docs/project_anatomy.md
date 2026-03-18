# Call Logger — Project Anatomy

**Ημερομηνία τροποποίησης:** 18 Μαρτίου 2026  

Συμπυκνωμένη «ακτινογραφία» για τροφοδότηση σε εξωτερικό LLM (Καθοδηγητής). Flutter Desktop (Windows 11), καθαρή αρχιτεκτονική κατά feature, Riverpod.

---

## 1. DIRTREE (`lib/`)

```
lib/
├── main.dart
├── core/
│   ├── config/app_config.dart
│   ├── database/
│   │   ├── database_helper.dart
│   │   ├── database_init_result.dart
│   │   └── database_init_runner.dart
│   ├── init/
│   │   ├── app_init_provider.dart
│   │   └── app_initializer.dart
│   ├── models/remote_tool_arg.dart
│   ├── providers/settings_provider.dart
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
└── features/
    ├── calls/
    │   ├── models/ (call_model, equipment_model, user_model)
    │   ├── provider/
    │   │   ├── call_entry_provider.dart
    │   │   ├── call_header_provider.dart
    │   │   ├── import_log_provider.dart
    │   │   ├── lookup_provider.dart
    │   │   └── remote_paths_provider.dart
    │   └── screens/
    │       ├── calls_screen.dart
    │       └── widgets/ (call_header_form, call_status_bar, equipment_info_card, notes_sticky_field, recent_calls_list, remote_connection_buttons, sticky_note_widget, user_info_card, import_console_widget)
    ├── database/screens/database_browser_screen.dart
    ├── directory/
    │   ├── models/ (department_model, equipment_column)
    │   ├── providers/ (directory_provider, equipment_directory_provider)
    │   └── screens/ (directory_screen, widgets: users_tab, equipment_tab, φόρμες, πίνακες, bulk dialogs)
    ├── history/
    │   ├── providers/history_provider.dart
    │   └── screens/history_screen.dart
    ├── settings/
    │   ├── screens/settings_screen.dart
    │   └── widgets/remote_args_editor.dart
    └── tasks/
        ├── models/ (task, task_filter)
        ├── providers/ (task_service_provider, tasks_provider)
        ├── services/task_service.dart
        └── screens/ (tasks_screen, task_card, task_filter_bar, task_form_dialog, task_close_dialog)
```

---

## 2. DATABASE SCHEMA (SQLite)

Πηγή: `database_helper.dart` (`_onCreate`, `_onUpgrade`, `migrateDepartmentsIfNeeded`). Τύποι όπως στο DDL.

| Πίνακας | Στήλες (όνομα → τύπος) |
|---------|------------------------|
| **calls** | id INTEGER PK AUTOINCREMENT, date TEXT, time TEXT, caller_id INTEGER, equipment_id INTEGER, issue TEXT, solution TEXT, category TEXT, status TEXT, duration INTEGER, is_priority INTEGER DEFAULT 0 · **+** caller_text TEXT (migration v4) |
| **users** | id INTEGER PK AUTOINCREMENT, last_name TEXT NOT NULL, first_name TEXT NOT NULL, phone TEXT, department TEXT, location TEXT, notes TEXT (μετά migration v5 από name→first/last) · **Σημ.:** ο κώδικας εισαγωγής/ενημέρωσης χρησιμοποιεί και **department_id INTEGER** όπου υπάρχει στη βάση |
| **equipment** | id INTEGER PK AUTOINCREMENT, code_equipment TEXT, type TEXT, user_id INTEGER, notes TEXT, custom_ip TEXT, anydesk_id TEXT, default_remote_tool TEXT · **+** code TEXT, description TEXT (migrations v2–3) |
| **categories** | id INTEGER PK, name TEXT |
| **tasks** | id INTEGER PK, title TEXT, description TEXT, due_date TEXT, status TEXT, call_id INTEGER · **+** priority, solution_notes, snooze_until, user_id, equipment_id, created_at, updated_at (migration v7) |
| **knowledge_base** | id INTEGER PK, topic TEXT, content TEXT, tags TEXT |
| **audit_log** | id INTEGER PK, action TEXT, timestamp TEXT, user_performing TEXT, details TEXT |
| **app_settings** | key TEXT PK, value TEXT |
| **remote_tool_args** | id INTEGER PK, tool_name TEXT, arg_flag TEXT, description TEXT, is_active INTEGER DEFAULT 0 |
| **departments** | id INTEGER PK, name TEXT UNIQUE NOT NULL, building TEXT, color TEXT DEFAULT '#1976D2', notes TEXT, map_floor TEXT, map_x REAL DEFAULT 0, map_y REAL DEFAULT 0, map_width REAL DEFAULT 0, map_height REAL DEFAULT 0 (δημιουργία runtime αν λείπει migration flag) |

---

## 3. MODELS (πεδία)

**Calls (`lib/features/calls/models/`)**  
- **CallModel:** id, date, time, callerId, equipmentId, callerText, issue, solution, category, status, duration, isPriority  
- **UserModel:** id, firstName, lastName, phone, departmentId, notes (+ υπολογιζόμενα name, departmentName, fullNameWithDepartment)  
- **EquipmentModel:** id, code, type, notes, userId, customIp, anydeskId, defaultRemoteTool (+ displayLabel, vncTarget, anydeskTarget)

**Directory (`lib/features/directory/models/`)**  
- **DepartmentModel:** id, name, building, color, notes, mapFloor, mapX, mapY, mapWidth, mapHeight  
- **EquipmentColumn:** ορισμός στηλών πίνακα (key, label, displayValue, sortValue) — όχι ORM row  
- **EquipmentRow:** typedef (EquipmentModel, UserModel?)

**Tasks (`lib/features/tasks/models/`)**  
- **Task:** id, callId, userId, equipmentId, title, description, dueDate, snoozeUntil, status, priority, solutionNotes, createdAt, updatedAt  
- **TaskFilter:** searchQuery, statuses (open/snoozed), startDate, endDate  
- **TaskStatus** (enum): open, snoozed, closed

**Core**  
- **RemoteToolArg** (`core/models/`): αντιστοιχία σε remote_tool_args

---

## 4. STATE MANAGEMENT — Riverpod (κύριοι providers)

| Provider | Ρόλος |
|----------|--------|
| **appInitProvider** | Μία φορά στην εκκίνηση: έλεγχος/σύνδεση βάσης, αποτέλεσμα init. |
| **callHeaderProvider** | Κατάσταση φόρμας κεφαλίδας κλήσης (τηλέφωνο, καλών, τμήμα, εξοπλισμός, candidates, canSubmit, focus). |
| **callEntryProvider** | Φόρμα εισαγωγής κλήσης: σημειώσεις, κατηγορία, εκκρεμότητα, χρονόμετρο, submit / submit μόνο task. |
| **lookupServiceProvider** | Ασύγχρονο φόρτωμα LookupService (χρήστες, τμήματα, εξοπλισμός στη μνήμη). |
| **recentCallsProvider** (family) | Τελευταίες κλήσεις ανά userId. |
| **importLogProvider** | Καταγραφές μηνυμάτων import. |
| **remoteArgsServiceProvider** / **validRemotePathsProvider** / **remoteLauncherStatusProvider** / **remoteConnectionServiceProvider** / **remoteLauncherServiceProvider** | Διαδρομές & εκκίνηση VNC/AnyDesk. |
| **taskServiceProvider** | Ανάλυση TaskService (singleton ανά scope). |
| **taskFilterProvider** | Φίλτρο λίστας εκκρεμοτήτων. |
| **tasksProvider** | Λίστα tasks (async) + refresh/add/update/delete/close. |
| **orphanCallsProvider** | Κλήσεις pending χωρίς task. |
| **directoryProvider** | Κατάλογος χρηστών/εξοπλισμού (φόρτωση, επεξεργασία, διαγραφές). |
| **equipmentDirectoryProvider** | Κατάσταση καρτέλας εξοπλισμού καταλόγου. |
| **catalogContinuousScrollProvider** | Ρύθμιση συνεχούς κύλισης στον κατάλογο. |
| **historyFilterProvider** / **historyCallsProvider** / **historyCategoriesProvider** | Ιστορικό κλήσεων και φίλτρα. |
| **showActiveTimerProvider** / **showAnyDeskRemoteProvider** | Ρυθμίσεις UI από SettingsService. |

---

## 5. DEPENDENCIES (`pubspec.yaml`)

- **flutter** / **flutter_localizations** (sdk)  
- **cupertino_icons:** ^1.0.8  
- **flutter_riverpod:** ^3.2.1  
- **sqflite_common_ffi:** ^2.3.3  
- **sqlite3_flutter_libs:** ^0.6.0  
- **path_provider:** ^2.1.2  
- **path:** ^1.9.0  
- **google_fonts:** ^8.0.2  
- **intl:** ^0.20.2  
- **window_manager:** ^0.5.1  
- **screen_retriever:** ^0.2.0  
- **shared_preferences:** ^2.3.3  
- **url_launcher:** ^6.3.0  
- **excel:** ^4.0.6  
- **file_picker:** ^8.0.0  

**dev:** flutter_test (sdk), **flutter_lints:** ^6.0.0  

**environment:** sdk ^3.10.7  

---

*Τέλος εγγράφου — μόνο περιγραφές, χωρίς αυτούσιο κώδικα εφαρμογής.*
