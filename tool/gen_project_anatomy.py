# -*- coding: utf-8 -*-
"""One-off generator for docs/project_anatomy.md — run from repo root: python tool/gen_project_anatomy.py"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _lib_dirtree() -> str:
    lines = ["lib/", "  main.dart"]

    def walk(p: Path, indent: str) -> None:
        try:
            names = sorted(p.iterdir(), key=lambda x: x.name.lower())
        except OSError:
            return
        dirs = [x for x in names if x.is_dir() and x.name != ".dart_tool"]
        files = [x for x in names if x.is_file()]
        for d in dirs:
            lines.append(f"{indent}{d.name}/")
            walk(d, indent + "  ")
        for f in files:
            lines.append(f"{indent}  {f.name}")

    walk(ROOT / "lib", "  ")
    return "\n".join(lines)

md = f"""# Call Logger — Project Anatomy

**Ημερομηνία τροποποίησης εγγράφου:** 14 Μαΐου 2026

Συμπυκνωμένη «ακτινογραφία» για εξωτερικό LLM (Καθοδηγητής): Flutter για Windows 11, δομή ανά features/, Riverpod, SQLite μέσω sqflite_common_ffi.

---

## 1) DIRTREE (lib/)

```
{_lib_dirtree()}
```

---

## 2) DATABASE SCHEMA (SQLite)

**Τρέχουσα έκδοση σχήματος (squashed v1):** `databaseSchemaVersionV1` = **27** (`lib/core/database/database_v1_schema.dart`, σταθερά `_kDatabaseSchemaVersion` στο `database_helper.dart`).

**Σημείωση runtime:** η `DatabaseHelper.ensureDepartmentsMapHiddenColumn` προσθέτει idempotent τη στήλη **`departments.map_hidden`** (INTEGER NOT NULL DEFAULT 0) χωρίς αύξηση του αριθμού έκδοσης σχήματος.

### Πίνακες (στήλη → τύπος SQLite)

- **calls** — id INTEGER PK AI, date TEXT, time TEXT, caller_id INTEGER, equipment_id INTEGER, caller_text TEXT, phone_text TEXT, department_text TEXT, equipment_text TEXT, issue TEXT, solution TEXT, category_text TEXT, category_id INTEGER, status TEXT, duration INTEGER, is_priority INTEGER DEFAULT 0, search_index TEXT, lansweeper_state TEXT NOT NULL DEFAULT 'unsent', lansweeper_main_ticket_id TEXT, lansweeper_last_sync_at TEXT, is_deleted INTEGER DEFAULT 0
- **call_external_links** — id INTEGER PK AI, call_id INTEGER NOT NULL, external_id TEXT NOT NULL, provider TEXT NOT NULL, created_at TEXT NOT NULL, metadata TEXT
- **users** — id INTEGER PK AI, last_name TEXT NOT NULL, first_name TEXT NOT NULL, department_id INTEGER, location TEXT, notes TEXT, is_deleted INTEGER DEFAULT 0
- **phones** — id INTEGER PK AI, number TEXT UNIQUE NOT NULL, department_id INTEGER
- **department_phones** — department_id INTEGER NOT NULL, phone_id INTEGER NOT NULL, PRIMARY KEY (department_id, phone_id)
- **user_phones** — user_id INTEGER NOT NULL, phone_id INTEGER NOT NULL, PRIMARY KEY (user_id, phone_id)
- **equipment** — id INTEGER PK AI, code_equipment TEXT, type TEXT, notes TEXT, custom_ip TEXT, anydesk_id TEXT, remote_params TEXT, default_remote_tool TEXT, department_id INTEGER, location TEXT, is_deleted INTEGER DEFAULT 0
- **user_equipment** — user_id INTEGER NOT NULL, equipment_id INTEGER NOT NULL, PRIMARY KEY (user_id, equipment_id)
- **departments** — id INTEGER PK AI, name TEXT NOT NULL, name_key TEXT UNIQUE NOT NULL, building TEXT, color TEXT DEFAULT '#1976D2', notes TEXT, map_floor TEXT, map_x REAL DEFAULT 0.0, map_y REAL DEFAULT 0.0, map_width REAL DEFAULT 0.0, map_height REAL DEFAULT 0.0, map_rotation REAL DEFAULT 0.0, map_label_offset_x REAL, map_label_offset_y REAL, map_anchor_offset_x REAL, map_anchor_offset_y REAL, map_custom_name TEXT, group_name TEXT, floor_id INTEGER, is_deleted INTEGER DEFAULT 0 (+ **map_hidden** INTEGER όπως παραπάνω)
- **building_map_floors** — id INTEGER PK AI, sort_order INTEGER NOT NULL DEFAULT 0, label TEXT NOT NULL, floor_group TEXT, image_path TEXT NOT NULL, rotation_degrees REAL NOT NULL DEFAULT 0
- **categories** — id INTEGER PK AI, name TEXT, is_deleted INTEGER DEFAULT 0
- **tasks** — id INTEGER PK AI, title TEXT, description TEXT, due_date TEXT, snooze_history_json TEXT, status TEXT, call_id INTEGER, priority INTEGER, solution_notes TEXT, snooze_until TEXT, caller_id INTEGER, equipment_id INTEGER, department_id INTEGER, phone_id INTEGER, phone_text TEXT, user_text TEXT, equipment_text TEXT, department_text TEXT, created_at TEXT, updated_at TEXT, origin TEXT DEFAULT 'legacy', search_index TEXT, is_deleted INTEGER DEFAULT 0
- **knowledge_base** — id INTEGER PK AI, topic TEXT, content TEXT, tags TEXT
- **audit_log** — id INTEGER PK AI, action TEXT, timestamp TEXT, user_performing TEXT, details TEXT, entity_type TEXT, entity_id INTEGER, entity_name TEXT, search_text TEXT, old_values_json TEXT, new_values_json TEXT
- **app_settings** — key TEXT PK, value TEXT
- **remote_tools** — id INTEGER PK AI, name TEXT NOT NULL, role TEXT NOT NULL, executable_path TEXT NOT NULL, launch_mode TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, is_active INTEGER NOT NULL DEFAULT 1, suggested_values TEXT, icon_asset_key TEXT, arguments_json TEXT, test_target_ip TEXT, is_exclusive INTEGER NOT NULL DEFAULT 0, deleted_at TEXT
- **remote_tool_args** — id INTEGER PK AI, remote_tool_id INTEGER, tool_name TEXT, arg_flag TEXT, description TEXT, is_active INTEGER DEFAULT 0, FOREIGN KEY (remote_tool_id) REFERENCES remote_tools(id)
- **user_dictionary** — word TEXT PK, language TEXT, letters_count INTEGER NOT NULL DEFAULT 0, diacritic_mark_count INTEGER NOT NULL DEFAULT 0
- **full_dictionary** — id INTEGER PK AI, word TEXT NOT NULL UNIQUE, normalized_word TEXT NOT NULL, source TEXT NOT NULL, language TEXT NOT NULL, category TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now')), letters_count INTEGER NOT NULL DEFAULT 0, diacritic_mark_count INTEGER NOT NULL DEFAULT 0

---

## 3) MODELS

### Βήμα Α — `lib/features/audit/models/`
- **AuditFilterModel** — keyword, action, entityType, dateFrom, dateTo
- **AuditLogModel** — id, action, timestamp, userPerforming, details, entityType, entityId, entityName, oldValuesJson, newValuesJson
- **AuditPageResult** — items (λίστα AuditLogModel), totalCount

### `lib/features/calls/models/`
- **CallModel** — id, date, time, callerId, equipmentId, callerText, phoneText, departmentText, equipmentText, issue, solution, category, categoryId, status, duration, isPriority, lansweeperState, lansweeperMainTicketId, lansweeperLastSyncAt, isDeleted
- **EquipmentModel** — id, code, type, notes, customIp, anydeskId, remoteParams (Map), defaultRemoteTool, departmentId, location, isDeleted
- **UserModel** — id, firstName, lastName, phones, departmentId, location, notes, isDeleted

### `lib/features/database/models/`
- **DatabaseStats** — fileSizeBytes, dbPath, lastBackupTime, rowCountsByTable
- **DatabaseBackupSettings** — destinationDirectory, namingFormat (enum), zipOutput, backupOnExit, interval (enum), backupDays, backupTime, lastBackupAttempt, lastBackupStatus, retention flags/αριθμοί

### `lib/features/directory/models/`
- **CategoryModel** — id, name
- **CategoryDirectoryColumn** — key, label, sortKey (σταθερές στηλών καταλόγου)
- **DepartmentDirectoryColumn** — key, label, sortKey
- **DepartmentModel** — id, name, building, color, notes, groupName, floorId, mapFloor, mapX/Y/Width/Height, mapRotation, mapLabelOffsetX/Y, mapAnchorOffsetX/Y, mapCustomName, directPhones, isDeleted, isHiddenOnMap
- **EquipmentColumn** — key, label, displayValue (callback), sortValue (callback)· typedef **EquipmentRow** = (EquipmentModel, UserModel?)
- **NonUserPhoneEntry** — phoneId, number, departmentNamesDisplay, primaryDepartmentId
- **UserCatalogMode** — enum: personal, shared
- **UserDirectoryColumn** — key, label, sortKey
- **department_floor_display_extension** — extension επί DepartmentModel (όχι νέα κλάση)

### `lib/features/history/models/`
- **DashboardFilterModel** — keyword, dateFrom, dateTo, department, userName, equipmentCode, topN
- **DepartmentStat** / **IssueStat** / **DailyTrendPoint** / **CallerStat** / **LongestCallEntry** / **HourlyBucket** — βοηθητικά στατιστικών
- **DashboardSummaryModel** — totalCalls, totalDurationSeconds, avgDurationSeconds, KPIs προηγούμενης περιόδου, λίστες dailyTrend, sparklineLast7Days, topCallers, longestCalls, hourlyDistribution, byDepartment, byIssue
- **LansweeperSyncState** — abstract constants: unsent, sent, excluded, failed

### `lib/features/tasks/models/`
- **TaskStatus** — enum: open, snoozed, closed
- **Task** — id, callId, callerId, equipmentId, departmentId, phoneId, phoneText, userText, equipmentText, departmentText, title, description, dueDate, snoozeUntil, snoozeHistoryJson, status, priority, solutionNotes, createdAt, updatedAt, origin, isDeleted
- **TaskSnoozeEntry** — snoozedAt, dueAt
- **TaskSortOption** — enum (createdAt, dueAt, priority, department, user, equipment)
- **TaskFilter** — searchQuery, statuses, startDate, endDate, sortBy, sortAscending
- **TaskAnalyticsFilter** — startDate, endDate
- **TaskAnalyticsOriginSlice** / **TaskAnalyticsBacklogPoint** — βοηθητικά analytics
- **TaskAnalyticsSummary** — εύρος ημερομηνιών, μετρήσεις active/created/closed/cancelled/overdue, rates, μέσοι χρόνοι, originDistribution, backlogGrowth, sparkline arrays
- **TaskSettingsConfig** — dayEndTime, nextBusinessHour, skipWeekends, defaultSnoozeOption, maxSnoozeDays, autoCloseQuickAdds

### `lib/core/models/`
- **BuildingMapFloor** — id, sortOrder, label, floorGroup, imagePath, rotationDegrees
- **CallsScreenCardsVisibility** — showUserCard, showEquipmentCard, showEmployeeRecentCard, showEquipmentRecentPanel, showGlobalRecentCard
- **DictionaryImportMode** — enum: enrich, replace
- **RemoteToolArgument** — value, description, isActive
- **RemoteTool** — id, name, role, executablePath, launchMode, sortOrder, isActive, deletedAt, suggestedValuesJson, iconAssetKey, arguments, testTargetIp, isExclusive
- **ToolRole** — enum: vnc, rdp, anydesk, generic

### `lib/core/about/models/`
- **ChangelogEntry** — version, date, added, changed, fixed

### Βήμα Β — *Model εκτός φακέλων models/
- **HistoryFilterModel** (`history_provider.dart`) — keyword, dateFrom, dateTo, category
- **EquipmentViewModel** (`lamp_result_card.dart`) — προβολή γραμμής παλιού LAMP (όχι domain entity της κύριας βάσης)

### Βήμα Γ — σημαντικοί τύποι χωρίς επίθημα Model
| Περιοχή | Αρχείο | Τύποι |
|----------|--------|--------|
| Αρχικοποίηση βάσης | database_init_result.dart | DatabaseStatus, DatabaseInitResult, DatabaseInitException |
| | database_init_runner.dart | DatabaseInitRunnerResult |
| | database_init_progress_provider.dart | DatabaseInitProgressState |
| | database_helper.dart | ConnectionCheckResult, TablePreviewResult |
| Εφαρμογή | app_initializer.dart | AppInitResult |
| Ρυθμίσεις | audit_retention_config.dart | AuditRetentionConfig |
| Υπηρεσίες | excel_parser.dart | ImportResult |
| | lookup_service.dart | LookupResult, PhoneUsageCheck, EquipmentUsageCheck |
| | import_types.dart | ImportLogLevel (enum) |
| Κλήσεις | call_entry_provider.dart | CallEntryState |
| | import_log_provider.dart | ImportLogEntry |
| | lookup_provider.dart | LookupLoadResult |
| | smart_entity_selector_provider.dart | SmartEntitySelectorState, OrphanQuickAddResult |
| Κατάλογος | directory_provider.dart | DirectoryState |
| | category_directory_provider.dart | CategoryDirectoryState |
| | department_directory_provider.dart | DepartmentDirectoryState |
| | equipment_directory_provider.dart | EquipmentDirectoryState, EquipmentDeleteUndoEntry |
| Χάρτης κτιρίου | building_map_controller.dart | BuildingMapFloorDeleteChoice |
| Βάση | database_maintenance_service.dart | MaintenanceBackupPrecheck (enum), ReplaceDatabaseResult |
| | database_backup_service.dart | DatabaseBackupResult |
| | backup_destination_folder_validator.dart | BackupDestinationValidationKind (enum), BackupDestinationValidationResult |

---

## 4) STATE MANAGEMENT — PROVIDERS (Riverpod)

- **appInitProvider** — αποτέλεσμα εκκίνησης (βάση + spell check readiness).
- **databaseInitProgressProvider** — βήματα/μηνύματα κατά το άνοιγμα βάσης.
- **lookupServiceProvider** — `LookupLoadResult` + singleton `LookupService` (cache καταλόγου).
- **callHeaderProvider** — ίδιο instance με **callSmartEntityProvider** (κεφαλίδα κλήσης / έξυπνος επιλογέας).
- **callSmartEntityProvider** / **taskSmartEntityProvider** — κατάσταση επιλογής τηλεφώνου, καλούντα, τμήματος, εξοπλισμού.
- **callEntryProvider** — φόρμα κλήσης, χρονόμετρο, σημειώσεις, κατηγορία, εκκρεμότητα.
- **importLogProvider** — γραμμές live console εισαγωγής.
- **recentCallsProvider** / **recentCallsByEquipmentProvider** / **globalRecentCallsProvider** / **showGlobalCallsToggleProvider** — πρόσφατες κλήσεις και toggle καθολικής λίστας.
- **directoryProvider** / **categoryDirectoryProvider** / **departmentDirectoryProvider** / **equipmentDirectoryProvider** — κατάσταση πινάκων καταλόγου, φίλτρα, στήλες, undo.
- **buildingMapControllerProvider** — λογική χάρτη κτιρίου (φύλλα, εικόνες, CRUD τμημάτων στο χάρτη).
- **building_map_providers** — δεδομένα φύλλων/επιλογής (`building_map_providers.dart`).
- **tasksProvider** / **taskFilterProvider** / **taskStatusCountsProvider** / **orphanCallsProvider** — λίστα εκκρεμοτήτων και φίλτρα.
- **taskServiceProvider** — υπηρεσία CRUD/snooze εκκρεμοτήτων.
- **taskSettingsConfigProvider** — ρυθμίσεις snooze/ωραρίου.
- **taskAnalyticsProvider** / **taskAnalyticsFilterProvider** — σύνοψη analytics εκκρεμοτήτων.
- **pendingTaskDeleteProvider** — ροή διαγραφής εκκρεμότητας από κλήση.
- **historyFilterProvider** / **historyCallsProvider** / **historyCategoriesProvider** / **historyCategoryEntriesProvider** — ιστορικό κλήσεων.
- **dashboardFilterProvider** / **dashboardStatsProvider** / **dashboardCallsForReportProvider** / **dashboardDepartmentsProvider** — πίνακας ελέγχου· σειρά providers ρυθμίσεων Lansweeper (API URL, κλειδιά, auto-login, κ.λπ.).
- **lansweeperSyncProvider** / **callExternalLinksProvider** — συγχρονισμός κλήσεων με Lansweeper και εξωτερικά tickets.
- **historyApplicationAuditViewProvider** — εναλλαγή προβολής audit εφαρμογής στο ιστορικό.
- **auditFilterProvider** / **auditListProvider** / **auditServiceAsyncProvider** / **auditEntityPreviewProvider** — ιστορικό εφαρμογής (audit).
- **databaseBackupSettingsProvider** / **backupSchedulerProvider** / **databaseMaintenanceServiceProvider** / **databaseBrowserStatsProvider** — backup, συντήρηση, στατιστικά αρχείου βάσης.
- **settingsProvider** (και σχετικά) — εμφάνιση χρονομέτρου, badge εργασιών, ορθογραφία, ορατότητα καρτών κλήσεων, κ.λπ.
- **greekDictionaryProvider** / **spellCheckServiceProvider** / **lexiconCategoriesProvider** / **lexiconFullModeProvider** / **lexiconLanguageRecalcProvider** — λεξικά και ορθογραφία.
- **mainNavRequestProvider** / **shellNavigationIntentProvider** / **directoryTabIntentProvider** — πλοήγηση κελύφους και καρτελών.
- **changelogProvider** / **appVersionProvider** — έκδοση εφαρμογής και changelog.
- **notesFieldHintTickProvider** — ένδειξη υποχρεωτικών σημειώσεων για εκκρεμότητα.

---

## 5) DEPENDENCIES (pubspec.yaml)

**dependencies:** flutter (sdk), flutter_localizations (sdk), cupertino_icons ^1.0.9, flutter_riverpod ^3.3.1, sqflite_common ^2.5.6, sqflite_common_ffi ^2.4.0+2, sqlite3_flutter_libs ^0.6.0+eol, path_provider ^2.1.2, path ^1.9.0, google_fonts ^8.0.2, intl ^0.20.2, characters ^1.4.0, window_manager ^0.5.1, screen_retriever ^0.2.0, shared_preferences ^2.5.5, url_launcher ^6.3.0, excel ^4.0.6, file_picker 11.0.2, fl_chart ^1.2.0, archive ^3.6.1, win32 ^5.15.0, ffi ^2.2.0, custom_mouse_cursor ^1.1.3, package_info_plus ^8.3.0, image 4.3.0

**dev_dependencies:** flutter_test (sdk), integration_test (sdk), riverpod ^3.2.1, flutter_lints ^6.0.0

---

*Τέλος εγγράφου — ενημερώστε την ημερομηνία όταν αλλάζει ουσιαστικά το σχήμα ή η δομή.*
"""

(ROOT / "docs/project_anatomy.md").write_text(md, encoding="utf-8")
print("OK", len(md))
