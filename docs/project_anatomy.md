# Call Logger — Project Anatomy

Συμπυκνωμένη «ακτινογραφία» του project για τροφοδότηση σε εξωτερικό LLM (Architect). Flutter Desktop, Clean Architecture, Riverpod.

---

## 1. DIRTREE (Δομή φακέλων `lib/`)

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
│   ├── services/
│   │   ├── excel_parser.dart
│   │   ├── import_service.dart
│   │   ├── import_types.dart
│   │   ├── lookup_service.dart
│   │   └── settings_service.dart
│   ├── utils/
│   │   └── name_parser.dart
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
    │   │   └── lookup_provider.dart
    │   └── screens/
    │       ├── calls_screen.dart
    │       └── widgets/
    │           ├── call_header_form.dart
    │           ├── import_console_widget.dart
    │           ├── recent_calls_list.dart
    │           ├── sticky_note_widget.dart
    │           └── user_info_card.dart
    ├── database/
    │   └── screens/
    │       └── database_browser_screen.dart
    ├── directory/
    │   ├── providers/
    │   │   └── directory_provider.dart
    │   └── screens/
    │       ├── directory_screen.dart
    │       └── widgets/
    │           ├── bulk_user_edit_dialog.dart
    │           ├── user_form_dialog.dart
    │           ├── users_data_table.dart
    │           └── users_tab.dart
    ├── settings/
    │   └── screens/
    │       └── settings_screen.dart
    └── tasks/
        └── (screens/models placeholders)
```

---

## 2. DATABASE SCHEMA (SQLite)

Έκδοση σχήματος: **5**. Πίνακες και στήλες (με migrations):

| Πίνακας | Στήλες (όνομα → τύπος) |
|--------|-------------------------|
| **calls** | id INTEGER PK, date TEXT, time TEXT, caller_id INTEGER, equipment_id INTEGER, **caller_text TEXT** (v4), issue TEXT, solution TEXT, category TEXT, status TEXT, duration INTEGER, is_priority INTEGER DEFAULT 0 |
| **users** | id INTEGER PK, last_name TEXT NOT NULL, first_name TEXT NOT NULL, phone TEXT, department TEXT, location TEXT, notes TEXT |
| **equipment** | id INTEGER PK, code_equipment TEXT, type TEXT, user_id INTEGER, **notes TEXT** (v2), **code TEXT** (v3), **description TEXT** (v3) |
| **categories** | id INTEGER PK, name TEXT |
| **tasks** | id INTEGER PK, title TEXT, description TEXT, due_date TEXT, status TEXT, call_id INTEGER |
| **knowledge_base** | id INTEGER PK, topic TEXT, content TEXT, tags TEXT |
| **audit_log** | id INTEGER PK, action TEXT, timestamp TEXT, user_performing TEXT, details TEXT |
| **app_settings** | key TEXT PK, value TEXT |

Σημείωση: Το `equipment` στο δίσκο χρησιμοποιεί στήλη `code_equipment`· τα models/API μπορούν να χρησιμοποιούν και `code` (migration).

---

## 3. MODELS

Τα models βρίσκονται στο `lib/features/calls/models/` (και αναφέρονται από directory).

- **CallModel**  
  id, date, time, callerId, equipmentId, callerText, issue, solution, category, status, duration, isPriority. fromMap / toMap (snake_case keys).

- **UserModel**  
  id, firstName, lastName, phone, department, location, notes. Υπολογιζόμενα: name (first + last), fullNameWithDepartment. fromMap υποστηρίζει και παλιό πεδίο `name`.

- **EquipmentModel**  
  id, code (αντιστοιχία με code_equipment), type, notes, userId. Υπολογιζόμενο: displayLabel (κωδικός + τύπος). fromMap/toMap με code_equipment.

---

## 4. STATE MANAGEMENT (Riverpod Providers)

| Provider | Τύπος / Θέση | Τι διαχειρίζει |
|----------|----------------|----------------|
| **appInitProvider** | FutureProvider, core/init | Αποτέλεσμα αρχικοποίησης εφαρμογής (DB init, success/fail). Τρέχει μία φορά στην εκκίνηση. |
| **callHeaderProvider** | NotifierProvider, features/calls/provider | Κατάσταση header φόρμας κλήσης: επιλεγμένο τηλέφωνο/χρήστη/εξοπλισμό, λίστες candidates, σφάλματα, ambiguous/no-match flags, κείμενα εμφάνισης. |
| **callEntryProvider** | NotifierProvider, features/calls/provider | Κατάσταση φόρμας εισαγωγής κλήσης: internal digits, selected user/equipment, notes, category, controllers/focus (references). |
| **lookupServiceProvider** | FutureProvider, features/calls/provider | Φόρτωση LookupService μία φορά· cache για αναζήτηση χρηστών/εξοπλισμού από τη βάση. |
| **importLogProvider** | NotifierProvider, features/calls/provider | Λίστα ImportLogEntry (μηνύματα + level) για το Live Console του Import Excel· addLog / clearLogs. |
| **directoryProvider** | NotifierProvider, features/directory/providers | Κατάσταση κατάλογου χρηστών: allUsers, filteredUsers, searchQuery, sort, selectedIds, undo (lastDeleted, lastBulkUpdatedUsers), focusedRowIndex. |

---

## 5. DEPENDENCIES (pubspec.yaml)

- **flutter** (sdk)
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

**SDK:** ^3.10.7
