# Call Logger — Project Anatomy

**Ημερομηνία τροποποίησης εγγράφου:** 14 Απριλίου 2026

Συμπυκνωμένη «ακτινογραφία» για εξωτερικό LLM (Καθοδηγητής): Flutter για Windows 11, δομή ανά features/, Riverpod, SQLite μέσω sqflite_common_ffi.

---

## 1) DIRTREE (lib/)

```
lib/
├── main.dart
├── core/
│   ├── config/
│   ├── database/
│   ├── debug/
│   ├── errors/
│   ├── init/
│   ├── models/
│   ├── providers/
│   ├── services/
│   ├── theme/
│   ├── utils/
│   └── widgets/
├── features/
│   ├── audit/
│   │   ├── constants/
│   │   ├── models/
│   │   ├── providers/
│   │   └── services/
│   ├── calls/
│   │   ├── models/
│   │   ├── provider/
│   │   ├── screens/
│   │   │   └── widgets/
│   │   └── utils/
│   ├── database/
│   │   ├── models/
│   │   ├── providers/
│   │   ├── screens/
│   │   ├── services/
│   │   ├── utils/
│   │   └── widgets/
│   ├── dictionary/
│   │   ├── providers/
│   │   ├── screens/
│   │   └── widgets/
│   ├── directory/
│   │   ├── models/
│   │   ├── providers/
│   │   └── screens/
│   │       └── widgets/
│   ├── history/
│   │   ├── providers/
│   │   ├── screens/
│   │   └── widgets/
│   │       └── audit_entity_previews/
│   ├── settings/
│   │   ├── screens/
│   │   └── widgets/
│   └── tasks/
│       ├── models/
│       ├── providers/
│       ├── screens/
│       ├── services/
│       └── ui/
└── tool/
```

---

## 2) DATABASE SCHEMA (SQLite)

Πηγή: `database_v1_schema.dart` (δημιουργία αρχικού σχήματος) και `database_helper.dart` (squashed `onCreate` / `onUpgrade`, user_version = σταθερά `databaseSchemaVersionV1`).

**Τρέχουσα έκδοση σχήματος (user_version):** 18 (`databaseSchemaVersionV1`).

**Πίνακες και στήλες (όνομα → τύπος SQLite):**

- **calls** — id INTEGER PK AUTOINCREMENT, date TEXT, time TEXT, caller_id INTEGER, equipment_id INTEGER, caller_text TEXT, phone_text TEXT, department_text TEXT, equipment_text TEXT, issue TEXT, solution TEXT, category_text TEXT, category_id INTEGER, status TEXT, duration INTEGER, is_priority INTEGER DEFAULT 0, search_index TEXT, is_deleted INTEGER DEFAULT 0  
- **users** — id INTEGER PK AUTOINCREMENT, last_name TEXT NOT NULL, first_name TEXT NOT NULL, department_id INTEGER, location TEXT, notes TEXT, is_deleted INTEGER DEFAULT 0  
- **phones** — id INTEGER PK AUTOINCREMENT, number TEXT UNIQUE NOT NULL, department_id INTEGER  
- **department_phones** — department_id INTEGER NOT NULL, phone_id INTEGER NOT NULL, PRIMARY KEY (department_id, phone_id)  
- **user_phones** — user_id INTEGER NOT NULL, phone_id INTEGER NOT NULL, PRIMARY KEY (user_id, phone_id)  
- **equipment** — id INTEGER PK AUTOINCREMENT, code_equipment TEXT, type TEXT, notes TEXT, custom_ip TEXT, anydesk_id TEXT, remote_params TEXT, default_remote_tool TEXT, department_id INTEGER, location TEXT, is_deleted INTEGER DEFAULT 0  
- **user_equipment** — user_id INTEGER NOT NULL, equipment_id INTEGER NOT NULL, PRIMARY KEY (user_id, equipment_id)  
- **departments** — id INTEGER PK AUTOINCREMENT, name TEXT NOT NULL, name_key TEXT UNIQUE NOT NULL, building TEXT, color TEXT DEFAULT '#1976D2', notes TEXT, map_floor TEXT, map_x REAL DEFAULT 0.0, map_y REAL DEFAULT 0.0, map_width REAL DEFAULT 0.0, map_height REAL DEFAULT 0.0, is_deleted INTEGER DEFAULT 0  
- **categories** — id INTEGER PK AUTOINCREMENT, name TEXT, is_deleted INTEGER DEFAULT 0  
- **tasks** — id INTEGER PK AUTOINCREMENT, title TEXT, description TEXT, due_date TEXT, snooze_history_json TEXT, status TEXT, call_id INTEGER, priority INTEGER, solution_notes TEXT, snooze_until TEXT, caller_id INTEGER, equipment_id INTEGER, department_id INTEGER, phone_id INTEGER, phone_text TEXT, user_text TEXT, equipment_text TEXT, department_text TEXT, created_at TEXT, updated_at TEXT, search_index TEXT, is_deleted INTEGER DEFAULT 0  
- **knowledge_base** — id INTEGER PK AUTOINCREMENT, topic TEXT, content TEXT, tags TEXT  
- **audit_log** — id INTEGER PK AUTOINCREMENT, action TEXT, timestamp TEXT, user_performing TEXT, details TEXT, entity_type TEXT, entity_id INTEGER, entity_name TEXT, old_values_json TEXT, new_values_json TEXT  
  - Ευρετήρια: idx_audit_log_timestamp, idx_audit_log_action, idx_audit_log_entity_type_entity_id  
- **app_settings** — key TEXT PK, value TEXT  
- **remote_tools** — id INTEGER PK AUTOINCREMENT, name TEXT NOT NULL, role TEXT NOT NULL, executable_path TEXT NOT NULL, launch_mode TEXT NOT NULL, config_template TEXT, sort_order INTEGER NOT NULL DEFAULT 0, is_active INTEGER NOT NULL DEFAULT 1, vnc_host_prefix TEXT, suggested_values TEXT, icon_asset_key TEXT, default_username TEXT, password TEXT, arguments_json TEXT, test_target_ip TEXT, is_exclusive INTEGER NOT NULL DEFAULT 0, deleted_at TEXT  
  - Ευρετήριο: idx_remote_tools_role  
- **remote_tool_args** — id INTEGER PK AUTOINCREMENT, remote_tool_id INTEGER, tool_name TEXT, arg_flag TEXT, description TEXT, is_active INTEGER DEFAULT 0, FK(remote_tool_id → remote_tools.id)  
- **user_dictionary** — word TEXT PK, language TEXT, letters_count INTEGER NOT NULL DEFAULT 0, diacritic_mark_count INTEGER NOT NULL DEFAULT 0  
- **full_dictionary** — id INTEGER PK AUTOINCREMENT, word TEXT NOT NULL UNIQUE, normalized_word TEXT NOT NULL, source TEXT NOT NULL, language TEXT NOT NULL, category TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now')), letters_count INTEGER NOT NULL DEFAULT 0, diacritic_mark_count INTEGER NOT NULL DEFAULT 0  
  - Ευρετήρια: idx_full_dictionary_norm, idx_full_dictionary_filters, idx_full_dictionary_letters_count, idx_full_dictionary_diacritic_mark_count  

---

## 3) MODELS

**features/calls/models/**

- **CallModel** — id, date, time, callerId, equipmentId, callerText, phoneText, departmentText, equipmentText, issue, solution, category, categoryId, status, duration, isPriority, isDeleted  
- **UserModel** — id, firstName, lastName, phones, departmentId, location, notes, isDeleted (υπολογιζόμενα: phoneJoined, name, departmentName, fullNameWithDepartment)  
- **EquipmentModel** — id, code, type, notes, customIp, anydeskId, remoteParams, defaultRemoteTool, departmentId, location, isDeleted  

**features/directory/models/**

- **DepartmentModel** — id, name, building, color, notes, mapFloor, mapX, mapY, mapWidth, mapHeight, directPhones, isDeleted  
- **CategoryModel** — id, name  
- **NonUserPhoneEntry** — phoneId, number, departmentNamesDisplay, primaryDepartmentId  
- **UserCatalogMode** (enum) — personal, shared  
- **DepartmentDirectoryColumn / UserDirectoryColumn / CategoryDirectoryColumn** — στατικοί ορισμοί στηλών UI (key, label, sortKey)  
- **equipment_column.dart** — τύπος γραμμής EquipmentRow (tuple εξοπλισμός + κάτοχος) και βοηθητικές μορφοποιήσεις τοποθεσίας (όχι κλασικό POJO πεδίων)  

**features/tasks/models/**

- **Task** — id, callId, callerId, equipmentId, departmentId, phoneId, phoneText, userText, equipmentText, departmentText, title, description, dueDate, snoozeUntil, snoozeHistoryJson, status, priority, solutionNotes, createdAt, updatedAt, isDeleted  
- **TaskStatus** (enum) — open, snoozed, closed  
- **TaskFilter** — searchQuery, statuses, startDate, endDate, sortBy, sortAscending  
- **TaskSortOption** (enum) — createdAt, dueAt, priority, department, user, equipment  
- **TaskSettingsConfig** — dayEndTime, nextBusinessHour, skipWeekends, defaultSnoozeOption, maxSnoozeDays, autoCloseQuickAdds  

**features/database/models/**

- **DatabaseStats** — fileSizeBytes, dbPath, lastBackupTime, rowCountsByTable  
- **DatabaseBackupSettings** — destinationDirectory, namingFormat, zipOutput, backupOnExit, interval, backupDays, backupTime, lastBackupAttempt, lastBackupStatus, retentionMaxCopiesEnabled, retentionMaxCopies, retentionMaxAgeEnabled, retentionMaxAgeDays  
- **DatabaseBackupNamingFormat / DatabaseBackupInterval** (enum)  

**core/models/**

- **RemoteToolArgument** — value, description, isActive  
- **RemoteTool** — id, name, role, executablePath, launchMode, configTemplate, sortOrder, isActive, deletedAt, vncHostPrefix, suggestedValuesJson, iconAssetKey, defaultUsername, arguments, testTargetIp, password, isExclusive  
- **RemoteToolArg** — id, remoteToolId, toolName, argFlag, description, isActive (legacy αντιστοιχία πίνακα remote_tool_args)  
- **ToolRole** (enum) — vnc, rdp, anydesk, generic  
- **DictionaryImportMode** (enum) — enrich, replace  

---

## 4) STATE MANAGEMENT — PROVIDERS (Riverpod)

Σύνοψη βασικών providers (όνομα + ρόλος):

- **appInitProvider** — αρχικοποίηση εφαρμογής (βάση, ρυθμίσεις, προγραμματισμένα backups).  
- **databaseInitProgressProvider** — βήματα/μηνύματα κατά το άνοιγμα βάσης.  
- **lookupServiceProvider** — φόρτωση in-memory cache χρηστών/τμημάτων/τηλεφώνων/εξοπλισμού για γρήγορα lookups.  
- **directoryProvider / departmentDirectoryProvider / categoryDirectoryProvider / equipmentDirectoryProvider** — κατάσταση καταλόγου (CRUD λίστες, soft delete, undo).  
- **callSmartEntityProvider / taskSmartEntityProvider** — επιλογή καλούντα/εξοπλισμού στη φόρμα κλήσεων και σε εκκρεμότητες.  
- **callHeaderProvider** — alias προς callSmartEntityProvider.  
- **callEntryProvider** — κατάσταση ενεργής κλήσης (σημειώσεις, χρονόμετρο, αποστολή κλήσης).  
- **recentCallsProvider** — πρόσφατες κλήσεις για λίστα.  
- **importLogProvider** — καταγραφή μηνυμάτων εισαγωγής.  
- **tasksProvider / taskFilterProvider / taskStatusCountsProvider / globalPendingTasksCountProvider / orphanCallsProvider** — λίστα εκκρεμοτήτων, φίλτρα, μετρητές, ορφανές κλήσεις.  
- **taskSettingsConfigProvider / taskServiceProvider / pendingTaskDeleteProvider** — ρυθμίσεις snooze/ωραρίου, υπηρεσία εργασιών, εκκρεμής διαγραφής.  
- **historyFilterProvider / historyCallsProvider / historyCategoriesProvider / historyCategoryEntriesProvider** — φίλτρα και δεδομένα ιστορικού κλήσεων.  
- **historyTableZoomProvider** (στο history_screen) — επίπεδο zoom πίνακα ιστορικού.  
- **historyApplicationAuditViewProvider / historyAuditImmersiveProvider** — εναλλαγή προβολής audit στο ιστορικό.  
- **auditServiceAsyncProvider / auditFilterProvider / auditListProvider / selectedAuditEntryIdProvider / auditSidePanelOpenProvider / auditEntityPreviewProvider** — λίστα και φίλτρα audit log.  
- **databaseBackupSettingsProvider / backupSchedulerProvider / databaseMaintenanceServiceProvider / databaseBrowserStatsProvider** — backups, χρονοδιάγραμμα, συντήρηση, στατιστικά browser πινάκων.  
- **remoteToolsCatalogProvider / remoteToolsAllCatalogProvider / remoteToolFormPairsProvider / remotePathsProvider** και συναφή (valid paths, launcher status, remote services) — εργαλεία απομακρυσμένης σύνδεσης.  
- **settings_provider** (πολλαπλά AsyncNotifier) — εμφάνιση χρονομέτρου, badge εκκρεμοτήτων, ορθογραφικός έλεγχος, ορατότητα καρτελών Βάση/Λεξικό.  
- **shellNavigationIntentProvider / mainNavRequestProvider / directoryTabIntentProvider / taskFocusIntentProvider / equipmentFocusIntentProvider** — πλοήγηση και εστίαση από shortcuts ή intents.  
- **greekDictionaryServiceProvider / spellCheckServiceProvider / lexiconCategoriesProvider / lexiconFullModeProvider / lexiconLanguageRecalcProvider / lexiconMasterDataRevisionProvider** — λεξικό και ορθογραφία.  
- **lexiconContinuousScrollProvider / lexiconPageSizeProvider / catalogContinuousScrollProvider** — συμπεριφορά κύλισης/σελίδας σε λίστες λεξικού και καταλόγου.  
- **databaseBrowserZoomByTableProvider** (οθόνη browser) — zoom ανά πίνακα.  
- **notesFieldHintTickProvider** — tick για υποδείξεις πεδίου σημειώσεων.  

---

## 5) DEPENDENCIES (pubspec.yaml)

**dependencies**

- flutter (sdk)  
- flutter_localizations (sdk)  
- cupertino_icons: ^1.0.8  
- flutter_riverpod: ^3.2.1  
- sqflite_common: ^2.5.6  
- sqflite_common_ffi: ^2.3.3  
- sqlite3_flutter_libs: ^0.6.0  
- path_provider: ^2.1.2  
- path: ^1.9.0  
- google_fonts: ^8.0.2  
- intl: ^0.20.2  
- characters: ^1.4.0  
- window_manager: ^0.5.1  
- screen_retriever: ^0.2.0  
- shared_preferences: ^2.3.3  
- url_launcher: ^6.3.0  
- excel: ^4.0.6  
- file_picker: ^8.0.0  
- archive: ^3.6.1  
- win32: ^5.15.0  
- ffi: ^2.2.0  

**dev_dependencies**

- flutter_test (sdk)  
- integration_test (sdk)  
- riverpod: ^3.2.1  
- flutter_lints: ^6.0.0  

---

*Τέλος εγγράφου — ενημερώστε την ημερομηνία όταν αλλάζει ουσιαστικά το σχήμα ή η δομή.*
