# Call Logger — Project Context Manifest

**Σκοπός:** Γρήγορη «ακτινογραφία δυνατοτήτων» για LLM agents. Συμπληρωματικό προς `docs/project_anatomy.md` (λεπτομέρειες δομής/αρχείων).

**Τελευταία επαλήθευση κώδικα:** Μάιος 2026 · **Έκδοση εφαρμογής:** `0.19.0+4` · **Schema SQLite:** `27` (`databaseSchemaVersionV1`)

---

## System Identity

**Call Logger** είναι **Windows 11 Desktop Operations Hub** για **IT Support / Helpdesk**: καταγραφή κλήσεων, διαχείριση καταλόγου οντότητων, εκκρεμότητες, ιστορικό, audit, συντήρηση βάσης — σε **μία** τοπική εφαρμογή.

| Άξονας | Περιγραφή |
|--------|-----------|
| **Πλατφόρμα** | **Flutter** desktop (μόνο **Windows 11**), `window_manager`, ελληνικό UI (`flutter_localizations`) |
| **Κατάσταση (state)** | **Riverpod** (`flutter_riverpod`) — reactive providers ανά feature |
| **Αποθήκευση** | **SQLite** μέσω `sqflite_common_ffi` · αρχείο `.db` (συνήθως δίκτυο **UNC** ή portable `..\Data Base\`) |
| **Δομή κώδικα** | `lib/core/` (infra) + `lib/features/` (οθόνες ανά domain) |
| **Κελύφος** | `MainShell` + **NavigationRail**: Κλήσεις → Εκκρεμότητες → Κατάλογος → Ιστορικό → Βάση → Λεξικό → **LAMP** |

**Ρόλος χρήστη:** Λειτουργικό προσωπικό helpdesk που καταγράφει κλήσεις σε πραγματικό χρόνο, συνδέει οντότητες (χρήστης / τηλέφωνο / τμήμα / εξοπλισμός), ανοίγει απομακρυσμένη πρόσβαση, κλείνει εργασίες και ελέγχει ιστορικό/audit.

---

## Global Capabilities Ecosystem

### Καταγραφή κλήσεων (Calls) — κεντρική οθόνη
- **Φόρμα κεφαλίδας** με **Smart Entity Selector**: έξυπνη επιλογή/αναζήτηση **καλούντα**, **τηλεφώνου**, **τμήματος**, **εξοπλισμού** (lookup cache, orphan quick-add).
- **Χρονόμετρο** κλήσης, **κατάσταση**, **κατηγορία** (autocomplete), **σημειώσεις** sticky, **προτεραιότητα**.
- **Πρόσφατες κλήσεις**: ανά εξοπλισμό, καθολική λίστα, πρόσφατα panel — ρυθμιζόμενη **ορατότητα καρτών**.
- **Mini Map Card** στο calls screen (σύνδεση με χάρτη κτιρίου).
- **Κουμπιά απομακρυσμένης σύνδεσης** (VNC/RDP/AnyDesk/generic) ανά εξοπλισμό και κανόνες στόχων.
- **Εισαγωγή Excel** (προαιρετικό κουμπί από ρυθμίσεις) + **live import console**.
- **Lansweeper sync**: κατάσταση αποστολής ticket (`unsent` / `sent` / `excluded` / `failed`), εξωτερικά links (`call_external_links`).

### Διαχείριση εκκρεμοτήτων (Tasks)
- **CRUD εκκρεμοτήτων** συνδεδεμένων με κλήσεις ή standalone.
- **Snooze** με ιστορικό, **κλείσιμο** με solution notes, **φίλτρα** / ταξινόμηση / μετρητές κατάστασης.
- **Ρυθμίσεις εργασιών**: ώρα λήξης ημέρας, επόμενη εργάσιμη ώρα, weekends, default snooze, auto-close quick-adds.
- **Analytics** (bottom sheet): created/closed/overdue, origin distribution, backlog sparklines.
- **Orphan calls** — κλήσεις χωρίς κλειστή εκκρεμότητα.

### Εσωτερικός κατάλογος (Directory)
- **Καρτέλες**: Χρήστες · Τμήματα · Εξοπλισμός · Κατηγορίες · Διάφορα (μη-χρήστη τηλέφωνα).
- **Data tables** με στήλες, φίλτρα, ταξινόμηση, **bulk edit** dialogs.
- **Φόρμες** χρήστη/τμήματος/εξοπλισμού/κατηγορίας — **homonym warnings**, μεταφορά τμήματος, undo snackbars.
- **Σύνδεση οντότητων**: τηλέφωνα ανά χρήστη/τμήμα, εξοπλισμός ανά χρήστη, χρώματα τμημάτων, όροφοι (`floor_id` / `map_floor`).
- **Spell-aware πεδία** (`user_form_smart_text_field`, lexicon integration).

### Building Map Canvas
- **Πολυόροφος χάρτης κτιρίου**: φύλλα (`building_map_floors`) με εικόνα πλανάριου, περιστροφή ορόφου.
- **Λειτουργίες επεξεργασίας**: τοποθέτηση/resize/rotate τμημάτων, **χρώματα**, labels, anchor offsets, **omnisearch**, overlay επιλογής.
- **Λειτουργίες προβολής** vs **edit layout** · εξαγωγή φύλλου (sheet export).
- **Συγχρονισμός** γεωμετρίας με `departments` (map_x/y/width/height/rotation, map_hidden, map_custom_name).

### Advanced spell-checking & Dictionary
- **LexiconSpellCheckService**: bundled ελληνικό core (~60k) + **`user_dictionary`** + **`full_dictionary`** (imported/master).
- **Levenshtein** προτάσεις (≤2), έλεγχος τόνων, **προσθήκη λέξης** στη βάση από UI.
- **Dictionary Manager**: πλέγμα λέξεων, κατηγορίες, import **enrich/replace**, compile εξαγωγή TXT.
- Widgets: `LexiconSpellTextFormField`, context menu ορθογραφίας.

### Remote Tools / VNC Launchers
- **Διαχείριση εργαλείων** (`remote_tools`, `remote_tool_args`): VNC, RDP, AnyDesk, generic.
- **Launch modes**, arguments JSON, test target IP, exclusive tools, εικονίδια.
- **RemoteLauncherService** + κανόνες στόχων από calls/directory.

### Audit Logging
- **Κεντρικό AuditService** → πίνακας `audit_log` (action, entity, old/new JSON, search_text).
- **Φίλτρα** / σελιδοποίηση · **entity previews** (κλήση, χρήστης, εξοπλισμός, task, backup, settings).
- **Retention runner** (ρύθμιση διατήρησης).
- Προβολή μέσα **Ιστορικό** (application audit tab, immersive mode).

### Ιστορικό & Dashboard
- **Ιστορικό κλήσεων** με φίλτρα ημερομηνίας/κατηγορίας/keyword.
- **Dashboard**: KPIs, trends, top callers, κατανομές (fl_chart), presets ημερομηνιών.
- **Lansweeper**: ρυθμίσεις API, probes, sync form, reports, sync history.

### Database Maintenance & Backups
- **Database browser**: στατιστικά πινάκων, προεπισκόπηση.
- **Backup**: `VACUUM INTO` (ατομικό, WAL/SHM), zip, χρονοπρογραμματισμός, **backup on exit**, retention.
- **Συντήρηση**: rename DB, replace, prechecks, rename failure dialogs.
- **Δημιουργία νέας βάσης** από ρυθμίσεις.

### LAMP (Legacy migration)
- **Ξεχωριστή οθόνη** για παλιά βάση LAMP: validation, Excel import, resolution issues, transfer wizard προς κύρια βάση.
- Δεν είναι καθημερινή ροή — εργαλείο **μετάβασης/καθαρισμού** legacy δεδομένων.

### Ρυθμίσεις & πλατφόρμα
- **Ρυθμίσεις**: διαδρομή βάσης, audit user, import Excel toggle, nav rail labels, spell/cards visibility, Lansweeper credentials.
- **Graceful shutdown (Windows)**: αποθήκευση μεγέθους παραθύρου → **WAL checkpoint** → exit backup → `closeConnection`.
- **Global fatal error** UI για αποτυχία βάσης · **keyboard shortcuts** (π.χ. quick capture).
- **Changelog / έκδοση** (`package_info_plus`).

---

## Data & State Infrastructure

### SQLite — πυρήνας δεδομένων
| Θέμα | Λεπτομέρεια |
|------|-------------|
| **Έκδοση σχήματος** | **`27`** — squashed v1 schema (`database_v1_schema.dart`) |
| **WAL** | `PRAGMA journal_mode = WAL` σε άνοιγμα · **checkpoint** στο κλείσιμο παραθύρου |
| **Διαδρομή** | Ρυθμιζόμενη · προεπιλογή `..\Data Base\call_logger.db` · **UNC fallback** σε τοπική dev αν το δίκτυο απουσιάζει |
| **Άνοιγμα** | Timeout + retries · **fail-fast** σε schema mismatch |
| **Multi-user / lock** | Κοινό `.db` σε δίκτυο → conflicts `database is locked` · **LockDiagnosticService** (handle.exe / PowerShell) · `forceReleaseLock` |
| **Idempotent patch** | Στήλη `departments.map_hidden` χωρίς bump έκδοσης |

**Κύριοι πίνακες (ενδεικτικά):** `calls`, `call_external_links`, `users`, `phones`, `departments`, `equipment`, `categories`, `tasks`, `building_map_floors`, `audit_log`, `app_settings`, `remote_tools`, `user_dictionary`, `full_dictionary`, `knowledge_base` (κυρίως browser/maintenance).

### Riverpod — reactive UI
- **Βήμα εκκίνησης:** `appInitProvider` (βάση + lexicon readiness) → `AppInitWrapper` → `AppShortcuts` → `MainShell`.
- **Pattern:** `*Provider` / `*Notifier` ανά οθόνη· **intent providers** για cross-tab navigation (`shellNavigationIntent`, `taskFocusIntent`, `directoryTabIntent`, κ.λπ.).
- **Lookup cache:** `lookupServiceProvider` — φόρτωση καταλόγου μία φορά, invalidation μετά mutations.
- **Building map:** `buildingMapControllerProvider` + `building_map_providers` (φύλλα, επιλογή, decoded image size).
- **Ροή κλήσης:** `callEntryProvider` + `callSmartEntityProvider` / `callHeaderProvider` (shared instance).

### Αρχιτεκτονικές συμβάσεις (για agents)
- **Features = vertical slices** (`screens/`, `providers/`, `widgets/`, `services/`).
- **Repositories** στο `core/database/` — SQL μόνο εκεί, όχι στα widgets.
- **Audit** μόνο μέσω `AuditService.log` — μην γράφεις απευθείας στον πίνακα.
- **Ορθογραφία** μέσω `LexiconSpellCheckService` / providers — όχι εξωτερικό spell-check SDK.
- **Τεκμηρίωση βάθους:** `docs/project_anatomy.md` (DIRTREE, πλήρης λίστα providers/models).

---

## Quick Reference — Navigation → Feature

| `MainNavDestination` | Οθόνη / module |
|----------------------|----------------|
| `calls` | `CallsScreen` |
| `tasks` | `TasksScreen` |
| `directory` | `DirectoryScreen` (+ Building Map dialog) |
| `history` | `HistoryScreen` (+ Dashboard, Audit, Lansweeper) |
| `database` | `DatabaseBrowserScreen` |
| `dictionary` | `DictionaryManagerScreen` |
| `lamp` | `LampScreen` |

**Settings** δεν είναι rail item — πρόσβαση από κελύφος / shortcuts.

---

## Out of Scope / Μη υποθέσεις

- **Όχι** web/mobile/macOS/Linux production target — κώδικας βελτιστοποιημένος για **Windows desktop**.
- **Όχι** cloud backend — όλα local/UNC SQLite.
- **Όχι** real-time multi-user sync — μόνο shared file + WAL· conflicts = lock diagnostics.
- **LAMP** ≠ καθημερινό module — legacy migration μόνο.

---

*Ενημέρωσε το manifest όταν αλλάζει ουσιαστικά το schema (`databaseSchemaVersionV1`) ή προστίθεται major feature στο NavigationRail.*
