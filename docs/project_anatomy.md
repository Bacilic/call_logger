# Call Logger — Project Anatomy

**Ημερομηνία τροποποίησης εγγράφου:** 17 Ιουνίου 2026

Συμπυκνωμένη «ακτινογραφία» για εξωτερικό LLM (Καθοδηγητής): Flutter για Windows 11, δομή ανά `features/`, Riverpod, SQLite μέσω `sqflite_common_ffi`.

---

## 1) DIRTREE (lib/)

```
lib/
├── core/
│   ├── about/
│   │   ├── models/
│   │   │   └── changelog_entry.dart
│   │   ├── providers/
│   │   │   ├── app_version_provider.dart
│   │   │   └── changelog_provider.dart
│   │   ├── services/
│   │   │   └── changelog_service.dart
│   │   ├── version_display.dart
│   │   └── widgets/
│   │       ├── changelog_dialog.dart
│   │       └── version_chip.dart
│   ├── config/
│   │   ├── app_config.dart
│   │   └── audit_retention_config.dart
│   ├── database/
│   │   ├── calls_repository.dart
│   │   ├── database_access_probe.dart
│   │   ├── database_helper.dart
│   │   ├── database_init_progress_provider.dart
│   │   ├── database_init_result.dart
│   │   ├── database_init_runner.dart
│   │   ├── database_path_pick_flow.dart
│   │   ├── database_path_resolution.dart
│   │   ├── database_v1_schema.dart
│   │   ├── department_floor_migration.dart
│   │   ├── dictionary_repository.dart
│   │   ├── directory_audit_helpers.dart
│   │   ├── directory_repository.dart
│   │   ├── lock_diagnostic_service.dart
│   │   ├── old_database/
│   │   │   ├── equipment_set_master_cycle.dart
│   │   │   ├── lamp_data_issue_type_labels.dart
│   │   │   ├── lamp_database_provider.dart
│   │   │   ├── lamp_excel_parse_int.dart
│   │   │   ├── lamp_issue_resolution_service.dart
│   │   │   ├── lamp_old_db_validator.dart
│   │   │   ├── lamp_settings_store.dart
│   │   │   ├── lamp_table_browser_api.dart
│   │   │   ├── lamp_table_greek_names.dart
│   │   │   ├── old_database_schema.dart
│   │   │   ├── old_equipment_repository.dart
│   │   │   ├── old_excel_importer.dart
│   │   │   └── resolution_log_entry.dart
│   │   ├── remote_tools_repository.dart
│   │   ├── settings_repository.dart
│   │   └── user_delete_phone_policy.dart
│   ├── directory/
│   │   └── phone_department_policy.dart
│   ├── errors/
│   │   ├── app_error_result.dart
│   │   ├── call_save_exception.dart
│   │   ├── department_exists_exception.dart
│   │   ├── dictionary_export_exception.dart
│   │   └── task_save_exception.dart
│   ├── init/
│   │   ├── app_init_provider.dart
│   │   └── app_initializer.dart
│   ├── models/
│   │   ├── building_map_floor.dart
│   │   ├── calls_screen_cards_visibility.dart
│   │   ├── dictionary_import_mode.dart
│   │   ├── remote_tool.dart
│   │   ├── remote_tool_arg.dart
│   │   ├── remote_tool_role.dart
│   │   └── window_placement_mode.dart
│   ├── providers/
│   │   ├── app_profile_provider.dart
│   │   ├── application_reset_provider.dart
│   │   ├── core_lexicon_provider.dart
│   │   ├── directory_tab_intent_provider.dart
│   │   ├── equipment_focus_intent_provider.dart
│   │   ├── greek_dictionary_provider.dart
│   │   ├── history_audit_immersive_provider.dart
│   │   ├── lamp_open_settings_intent_provider.dart
│   │   ├── lamp_read_path_health_provider.dart
│   │   ├── lexicon_categories_provider.dart
│   │   ├── lexicon_full_mode_provider.dart
│   │   ├── lexicon_language_recalc_provider.dart
│   │   ├── main_nav_request_provider.dart
│   │   ├── settings_provider.dart
│   │   ├── shell_navigation_intent_provider.dart
│   │   ├── spell_check_provider.dart
│   │   ├── task_focus_intent_provider.dart
│   │   └── user_form_edit_intent_provider.dart
│   ├── services/
│   │   ├── application_prefs_snapshot.dart
│   │   ├── application_reset_service.dart
│   │   ├── audit_retention_runner.dart
│   │   ├── audit_service.dart
│   │   ├── backup_reset_metadata.dart
│   │   ├── building_map_storage.dart
│   │   ├── core_lexicon_service.dart
│   │   ├── core_lexicon_validation.dart
│   │   ├── default_remote_tool_display.dart
│   │   ├── desktop_window_service.dart
│   │   ├── dictionary_service.dart
│   │   ├── gemini_runtime_settings.dart
│   │   ├── gemini_ticket_service.dart
│   │   ├── lansweeper_agent_api_probe.dart
│   │   ├── lansweeper_helpdesk_login_probe.dart
│   │   ├── lansweeper_host_reachability.dart
│   │   ├── lansweeper_sync_service.dart
│   │   ├── lansweeper_ticket_requester_fields.dart
│   │   ├── lookup_service.dart
│   │   ├── master_dictionary_service.dart
│   │   ├── portable_lamp_storage.dart
│   │   ├── portable_tool_image_storage.dart
│   │   ├── remote_args_service.dart
│   │   ├── remote_connection_service.dart
│   │   ├── remote_launcher_service.dart
│   │   ├── remote_tools_paths_helper.dart
│   │   ├── settings_service.dart
│   │   ├── spell_check_service.dart
│   │   └── spelling_lookup_gemini_service.dart
│   ├── theme/
│   │   └── .gitkeep
│   ├── utils/
│   │   ├── autocomplete_highlight_scroll.dart
│   │   ├── bundled_dictionary_assets.dart
│   │   ├── date_parser_util.dart
│   │   ├── department_display_utils.dart
│   │   ├── department_floor_sync.dart
│   │   ├── file_picker_initial_directory.dart
│   │   ├── file_picker_session.dart
│   │   ├── history_entity_display_utils.dart
│   │   ├── lexicon_word_metrics.dart
│   │   ├── linkable_text_parser.dart
│   │   ├── name_parser.dart
│   │   ├── natural_string_compare.dart
│   │   ├── phone_list_parser.dart
│   │   ├── safe_file_base_name.dart
│   │   ├── search_debouncer.dart
│   │   ├── search_text_normalizer.dart
│   │   ├── spell_check.dart
│   │   ├── user_homonym_finder.dart
│   │   ├── user_identity_normalizer.dart
│   │   ├── windows_cli_error_dialog.dart
│   │   ├── windows_file_name_validation.dart
│   │   └── windows_save_sqlite_database_dialog.dart
│   └── widgets/
│       ├── .gitkeep
│       ├── app_init_wrapper.dart
│       ├── app_shell_with_global_fatal_error.dart
│       ├── app_shortcuts.dart
│       ├── calendar_range_picker.dart
│       ├── database_error_screen.dart
│       ├── database_persistence_error_snackbar.dart
│       ├── deleted_catalog_entity_text.dart
│       ├── ellipsis_tooltip_text.dart
│       ├── fatal_error_screen.dart
│       ├── global_fatal_error_notifier.dart
│       ├── lexicon_spell_menu_helper.dart
│       ├── lexicon_spell_text_form_field.dart
│       ├── linkable_selectable_text.dart
│       ├── main_nav_destination.dart
│       ├── main_shell.dart
│       ├── nav_rail_attention_badge.dart
│       ├── remote_tool_icon.dart
│       └── spell_check_controller.dart
├── features/
│   ├── audit/
│   │   ├── audit.dart
│   │   ├── constants/
│   │   │   └── audit_ui_mappings.dart
│   │   ├── models/
│   │   │   ├── audit_filter_model.dart
│   │   │   ├── audit_log_model.dart
│   │   │   ├── audit_page_result.dart
│   │   │   └── audit_reference_labels.dart
│   │   ├── providers/
│   │   │   └── audit_providers.dart
│   │   └── services/
│   │       ├── audit_entity_preview_resolver.dart
│   │       ├── audit_formatter_service.dart
│   │       └── audit_reference_label_resolver.dart
│   ├── calls/
│   │   ├── models/
│   │   │   ├── .gitkeep
│   │   │   ├── call_model.dart
│   │   │   ├── equipment_model.dart
│   │   │   └── user_model.dart
│   │   ├── provider/
│   │   │   ├── .gitkeep
│   │   │   ├── call_entry_provider.dart
│   │   │   ├── call_header_provider.dart
│   │   │   ├── call_mutation_refresh.dart
│   │   │   ├── calls_dashboard_providers.dart
│   │   │   ├── lookup_provider.dart
│   │   │   ├── notes_field_hint_provider.dart
│   │   │   ├── remote_paths_provider.dart
│   │   │   └── smart_entity_selector_provider.dart
│   │   ├── screens/
│   │   │   ├── .gitkeep
│   │   │   ├── calls_screen.dart
│   │   │   └── widgets/
│   │   │       ├── call_header_form.dart
│   │   │       ├── call_status_bar.dart
│   │   │       ├── category_autocomplete_field.dart
│   │   │       ├── equipment_recent_calls_panel.dart
│   │   │       ├── global_recent_calls_list.dart
│   │   │       ├── mini_map_card.dart
│   │   │       ├── notes_sticky_field.dart
│   │   │       ├── recent_calls_list.dart
│   │   │       ├── remote_connection_buttons.dart
│   │   │       ├── smart_entity_selector_caller_field.dart
│   │   │       ├── smart_entity_selector_caller_presentational.dart
│   │   │       ├── smart_entity_selector_conflict_badge.dart
│   │   │       ├── smart_entity_selector_department_field.dart
│   │   │       ├── smart_entity_selector_equipment_field.dart
│   │   │       ├── smart_entity_selector_equipment_models.dart
│   │   │       ├── smart_entity_selector_equipment_suggestion_list.dart
│   │   │       ├── smart_entity_selector_overlay_utils.dart
│   │   │       ├── smart_entity_selector_phone_field.dart
│   │   │       ├── smart_entity_selector_phone_presentational.dart
│   │   │       ├── smart_entity_selector_phone_suggestion_list.dart
│   │   │       ├── smart_entity_selector_phone_utils.dart
│   │   │       ├── smart_entity_selector_widget.dart
│   │   │       ├── sticky_note_widget.dart
│   │   │       ├── text_layout_utils.dart
│   │   │       └── user_info_card.dart
│   │   └── utils/
│   │       ├── call_remote_targets.dart
│   │       ├── equipment_remote_param_key.dart
│   │       ├── remote_target_rules.dart
│   │       └── vnc_remote_target.dart
│   ├── database/
│   │   ├── debug/
│   │   │   ├── error_scenarios_screen.dart
│   │   │   ├── integrity_debug_provider_refresh.dart
│   │   │   └── integrity_debug_seeder_service.dart
│   │   ├── models/
│   │   │   ├── database_backup_settings.dart
│   │   │   ├── database_integrity_finding.dart
│   │   │   ├── database_integrity_report.dart
│   │   │   ├── database_stats.dart
│   │   │   └── integrity_fix_models.dart
│   │   ├── providers/
│   │   │   ├── backup_scheduler_provider.dart
│   │   │   ├── database_backup_settings_provider.dart
│   │   │   ├── database_browser_stats_provider.dart
│   │   │   ├── database_integrity_provider.dart
│   │   │   └── database_maintenance_provider.dart
│   │   ├── screens/
│   │   │   └── database_browser_screen.dart
│   │   ├── services/
│   │   │   ├── database_backup_audit.dart
│   │   │   ├── database_backup_service.dart
│   │   │   ├── database_exit_backup.dart
│   │   │   ├── database_integrity_fix_service.dart
│   │   │   ├── database_integrity_service.dart
│   │   │   ├── database_maintenance_service.dart
│   │   │   ├── database_stats_service.dart
│   │   │   └── integrity_audit_details_builder.dart
│   │   ├── utils/
│   │   │   ├── backup_destination_folder_validator.dart
│   │   │   ├── backup_destination_location_warnings.dart
│   │   │   ├── backup_location_hints.dart
│   │   │   ├── backup_restore_tooltip.dart
│   │   │   ├── backup_schedule_status.dart
│   │   │   ├── backup_schedule_utils.dart
│   │   │   └── portable_backup_availability.dart
│   │   └── widgets/
│   │       ├── backup_folder_missing_dialog.dart
│   │       ├── database_integrity_panel.dart
│   │       ├── database_maintenance_panel.dart
│   │       ├── database_rename_failure_dialog.dart
│   │       ├── database_settings_panel.dart
│   │       └── integrity_fix_dialogs.dart
│   ├── dictionary/
│   │   ├── dictionary_table_layout.dart
│   │   ├── models/
│   │   │   └── lexicon_list_filters_model.dart
│   │   ├── providers/
│   │   │   ├── lexicon_list_filters_provider.dart
│   │   │   ├── lexicon_scroll_provider.dart
│   │   │   └── lexicon_spelling_panel_provider.dart
│   │   ├── screens/
│   │   │   └── dictionary_manager_screen.dart
│   │   └── widgets/
│   │       ├── core_lexicon_setup_dialog.dart
│   │       ├── dictionary_grid_row.dart
│   │       ├── dictionary_settings_dialog.dart
│   │       └── lexicon_spelling_panel.dart
│   ├── directory/
│   │   ├── building_map/
│   │   │   ├── building_map_geometry.dart
│   │   │   ├── building_map_label_layout.dart
│   │   │   ├── building_map_sheet_export_key.dart
│   │   │   ├── controllers/
│   │   │   │   └── building_map_controller.dart
│   │   │   ├── providers/
│   │   │   │   └── building_map_providers.dart
│   │   │   ├── screens/
│   │   │   │   └── building_map_dialog.dart
│   │   │   ├── services/
│   │   │   │   ├── building_map_sheet_export.dart
│   │   │   │   └── building_map_sheet_export_save_path.dart
│   │   │   └── widgets/
│   │   │       ├── building_map_commit_color_dialog.dart
│   │   │       ├── building_map_department_search_field.dart
│   │   │       ├── building_map_edit_toolbar.dart
│   │   │       ├── building_map_empty_canvas_message.dart
│   │   │       ├── building_map_fill_color_dialog.dart
│   │   │       ├── building_map_floor_departments_dialog.dart
│   │   │       ├── building_map_floor_edit_preview.dart
│   │   │       ├── building_map_floor_menu_button.dart
│   │   │       ├── building_map_floors_body.dart
│   │   │       ├── building_map_omnisearch_field.dart
│   │   │       ├── building_map_portable_image_copy_dialog.dart
│   │   │       ├── building_map_search_unresolved_banner.dart
│   │   │       ├── building_map_sheet_painter.dart
│   │   │       ├── building_map_sheet_viewport.dart
│   │   │       ├── department_selection_overlay.dart
│   │   │       ├── map_rotation_pod.dart
│   │   │       └── views/
│   │   │           ├── building_map_edit_layout.dart
│   │   │           └── building_map_view_layout.dart
│   │   ├── models/
│   │   │   ├── .gitkeep
│   │   │   ├── category_directory_column.dart
│   │   │   ├── category_model.dart
│   │   │   ├── department_directory_column.dart
│   │   │   ├── department_floor_display_extension.dart
│   │   │   ├── department_model.dart
│   │   │   ├── equipment_column.dart
│   │   │   ├── non_user_phone_entry.dart
│   │   │   ├── user_catalog_mode.dart
│   │   │   └── user_directory_column.dart
│   │   ├── providers/
│   │   │   ├── category_directory_provider.dart
│   │   │   ├── department_directory_provider.dart
│   │   │   ├── directory_cache_refresh.dart
│   │   │   ├── directory_provider.dart
│   │   │   └── equipment_directory_provider.dart
│   │   ├── screens/
│   │   │   ├── .gitkeep
│   │   │   ├── directory_screen.dart
│   │   │   └── widgets/
│   │   │       ├── bulk_department_edit_dialog.dart
│   │   │       ├── bulk_equipment_edit_dialog.dart
│   │   │       ├── bulk_user_edit_dialog.dart
│   │   │       ├── catalog_column_selector_shell.dart
│   │   │       ├── categories_data_table.dart
│   │   │       ├── categories_tab.dart
│   │   │       ├── category_form_dialog.dart
│   │   │       ├── category_undo_snackbar.dart
│   │   │       ├── department_color_palette.dart
│   │   │       ├── department_color_picker_dialog.dart
│   │   │       ├── department_form_dialog.dart
│   │   │       ├── department_palette_actions.dart
│   │   │       ├── department_palette_host.dart
│   │   │       ├── department_palette_store.dart
│   │   │       ├── department_transfer_confirm_dialog.dart
│   │   │       ├── departments_data_table.dart
│   │   │       ├── departments_tab.dart
│   │   │       ├── equipment_data_table.dart
│   │   │       ├── equipment_form_dialog.dart
│   │   │       ├── equipment_settings_dialog.dart
│   │   │       ├── equipment_tab.dart
│   │   │       ├── homonym_warning_dialog.dart
│   │   │       ├── miscellaneous_tab.dart
│   │   │       ├── non_user_phones_data_table.dart
│   │   │       ├── shared_asset_disconnect_dialog.dart
│   │   │       ├── user_form_dialog.dart
│   │   │       ├── user_form_smart_text_field.dart
│   │   │       ├── user_name_change_confirm_dialog.dart
│   │   │       ├── user_phone_department_conflict_dialog.dart
│   │   │       ├── users_data_table.dart
│   │   │       └── users_tab.dart
│   │   └── services/
│   │       └── shared_asset_disconnect_apply.dart
│   ├── floor_map/
│   │   └── services/
│   │       └── floor_color_assignment_service.dart
│   ├── history/
│   │   ├── models/
│   │   │   ├── dashboard_date_preset.dart
│   │   │   ├── dashboard_filter_model.dart
│   │   │   ├── dashboard_summary_model.dart
│   │   │   ├── lansweeper_connection_status.dart
│   │   │   └── lansweeper_sync_state.dart
│   │   ├── providers/
│   │   │   ├── dashboard_provider.dart
│   │   │   ├── history_application_audit_view_provider.dart
│   │   │   ├── history_call_actions_provider.dart
│   │   │   ├── history_provider.dart
│   │   │   ├── lansweeper_connection_probe_provider.dart
│   │   │   └── lansweeper_sync_provider.dart
│   │   ├── screens/
│   │   │   ├── dashboard_cards.dart
│   │   │   ├── dashboard_charts.dart
│   │   │   ├── dashboard_filter_pane.dart
│   │   │   ├── dashboard_palette_colors.dart
│   │   │   ├── dashboard_screen.dart
│   │   │   └── history_screen.dart
│   │   ├── services/
│   │   │   └── history_call_actions_service.dart
│   │   └── widgets/
│   │       ├── application_audit_tab.dart
│   │       ├── audit_before_after_section.dart
│   │       ├── audit_entity_previews/
│   │       │   ├── audit_entity_preview_body.dart
│   │       │   ├── audit_preview_column.dart
│   │       │   ├── backup_preview_widget.dart
│   │       │   ├── call_preview_widget.dart
│   │       │   ├── equipment_preview_widget.dart
│   │       │   ├── settings_preview_widget.dart
│   │       │   ├── task_preview_widget.dart
│   │       │   └── user_preview_widget.dart
│   │       ├── audit_entity_side_panel.dart
│   │       ├── call_delete_dialog.dart
│   │       ├── call_edit_dialog.dart
│   │       ├── history_deleted_entity_text.dart
│   │       ├── lansweeper/
│   │       │   ├── gemini_model_field.dart
│   │       │   ├── lansweeper_connection_settings_dialog.dart
│   │       │   ├── lansweeper_connection_status_indicator.dart
│   │       │   ├── lansweeper_report_call_list.dart
│   │       │   ├── lansweeper_report_call_tile.dart
│   │       │   ├── lansweeper_state_badge.dart
│   │       │   ├── lansweeper_sync_form.dart
│   │       │   ├── lansweeper_url_rules.dart
│   │       │   └── sync_history_list.dart
│   │       └── lansweeper_report_dialog.dart
│   ├── lamp/
│   │   ├── controllers/
│   │   │   ├── lamp_import_controller.dart
│   │   │   ├── lamp_integrity_controller.dart
│   │   │   ├── lamp_issue_resolution_controller.dart
│   │   │   ├── lamp_path_management.dart
│   │   │   ├── lamp_screen_host.dart
│   │   │   └── lamp_search_controller.dart
│   │   ├── screens/
│   │   │   └── lamp_screen.dart
│   │   ├── services/
│   │   │   └── lamp_migration_service.dart
│   │   └── widgets/
│   │       ├── lamp_db_tables_tab.dart
│   │       ├── lamp_issue_manual_review_dialog.dart
│   │       ├── lamp_issue_widgets.dart
│   │       ├── lamp_resolution_progress_dialog.dart
│   │       ├── lamp_result_card.dart
│   │       ├── lamp_settings_dialog.dart
│   │       ├── lamp_transfer_wizard_dialog.dart
│   │       └── lamp_unresolved_resolution_dialog.dart
│   ├── settings/
│   │   ├── screens/
│   │   │   ├── remote_tools_management_screen.dart
│   │   │   └── settings_screen.dart
│   │   └── widgets/
│   │       ├── create_new_database_dialog.dart
│   │       ├── pending_reset_database_screen.dart
│   │       ├── remote_tool_form_dialog.dart
│   │       └── start_from_beginning_flow.dart
│   └── tasks/
│       ├── models/
│       │   ├── .gitkeep
│       │   ├── task.dart
│       │   ├── task_analytics_date_preset.dart
│       │   ├── task_analytics_filter.dart
│       │   ├── task_analytics_summary.dart
│       │   ├── task_filter.dart
│       │   └── task_settings_config.dart
│       ├── providers/
│       │   ├── pending_task_delete_provider.dart
│       │   ├── task_analytics_date_provider.dart
│       │   ├── task_analytics_provider.dart
│       │   ├── task_service_provider.dart
│       │   ├── task_settings_config_provider.dart
│       │   └── tasks_provider.dart
│       ├── screens/
│       │   ├── .gitkeep
│       │   ├── task_card.dart
│       │   ├── task_close_dialog.dart
│       │   ├── task_filter_bar.dart
│       │   ├── task_form_dialog.dart
│       │   ├── task_settings_dialog.dart
│       │   └── tasks_screen.dart
│       ├── services/
│       │   └── task_service.dart
│       ├── ui/
│       │   └── task_due_option_tooltips.dart
│       └── widgets/
│           └── task_analytics_bottom_sheet.dart
└── main.dart
```

---

## 2) DATABASE SCHEMA (SQLite)

**Τρέχουσα έκδοση σχήματος:** `databaseSchemaVersionV1 = 31` (`lib/core/database/database_v1_schema.dart`).

| Πίνακας | Στήλες (τύπος SQLite) |
|---------|------------------------|
| **calls** | id INTEGER PK, date/time TEXT, caller_id/equipment_id INTEGER, caller_text/phone_text/department_text/equipment_text TEXT, issue TEXT, category_text TEXT, category_id INTEGER, status TEXT, duration INTEGER, is_priority INTEGER, search_index TEXT, lansweeper_state TEXT, lansweeper_main_ticket_id TEXT, lansweeper_last_sync_at TEXT, is_deleted INTEGER |
| **call_external_links** | id INTEGER PK, call_id INTEGER, external_id TEXT, provider TEXT, created_at TEXT, metadata TEXT |
| **users** | id INTEGER PK, last_name/first_name TEXT, department_id INTEGER, location/notes TEXT, is_deleted INTEGER |
| **phones** | id INTEGER PK, number TEXT UNIQUE, department_id INTEGER, is_deleted INTEGER |
| **department_phones** | department_id, phone_id (PK composite) |
| **user_phones** | user_id, phone_id (PK composite) |
| **equipment** | id INTEGER PK, code_equipment/type/notes TEXT, remote_params TEXT, default_remote_tool TEXT, department_id INTEGER, location TEXT, is_deleted INTEGER |
| **user_equipment** | user_id, equipment_id (PK composite) |
| **departments** | id INTEGER PK, name/name_key TEXT, building/color/notes TEXT, map_floor TEXT, map_x/y/width/height/rotation REAL, map_label_offset_*, map_anchor_offset_*, map_custom_name TEXT, map_label_font_scale/width/height REAL, group_name TEXT, floor_id INTEGER, map_hidden INTEGER, is_deleted INTEGER |
| **building_map_floors** | id INTEGER PK, sort_order INTEGER, label TEXT, floor_group TEXT, image_path TEXT, rotation_degrees REAL |
| **categories** | id INTEGER PK, name TEXT, is_deleted INTEGER |
| **tasks** | id INTEGER PK, title/description TEXT, due_date/snooze_until TEXT, snooze_history_json TEXT, status TEXT, call_id INTEGER, priority INTEGER, solution_notes TEXT, caller/equipment/department/phone ids & texts, created_at/updated_at TEXT, origin TEXT, search_index TEXT, is_deleted INTEGER |
| **knowledge_base** | id INTEGER PK, topic/content/tags TEXT |
| **audit_log** | id INTEGER PK, action/timestamp/user_performing/details TEXT, entity_type TEXT, entity_id INTEGER, entity_name TEXT, search_text TEXT, old_values_json/new_values_json TEXT |
| **app_settings** | key TEXT PK, value TEXT |
| **remote_tools** | id INTEGER PK, name/role/executable_path/launch_mode TEXT, sort_order/is_active/is_exclusive INTEGER, suggested_values/icon_asset_key/arguments_json/test_target_ip TEXT, deleted_at TEXT |
| **remote_tool_args** | id INTEGER PK, remote_tool_id INTEGER, tool_name/arg_flag/description TEXT, is_active INTEGER |
| **user_dictionary** | word TEXT PK, display_word TEXT, language TEXT, letters_count/diacritic_mark_count INTEGER |
| **full_dictionary** | id INTEGER PK, word/normalized_word/source/language/category TEXT, created_at TEXT, letters_count/diacritic_mark_count INTEGER |

Ευρετήρια: `calls(lansweeper_state)`, `audit_log(timestamp, action, entity_type+entity_id)`, `full_dictionary(normalized_word, filters, letters, diacritics)`, `remote_tools(role)`, `call_external_links(call_id+provider, created_at)`.

---

## 3) MODELS

### `lib/features/audit/models/`
- **AuditFilterModel** — keyword, action, entityType, dateFrom, dateTo
- **AuditLogModel** — id, action, timestamp, userPerforming, details, entityType, entityId, entityName, old/newValuesJson
- **AuditPageResult** — items, totalCount
- **AuditReferenceLabels** — departmentNames (Map)

### `lib/features/calls/models/`
- **CallModel** — id, date, time, callerId, equipmentId, *Text πεδία, issue, category, status, duration, isPriority, lansweeper*, isDeleted, linked-deleted flags
- **EquipmentModel** — id, code, type, notes, remoteParams, defaultRemoteTool, departmentId, location, isDeleted
- **UserModel** — id, firstName, lastName, phones, departmentId, location, notes, isDeleted

### `lib/features/database/models/`
- **DatabaseBackupSettings** — destination, naming, zip, includes (maps/tools/lexicon/lamp), interval, retention, last backup metadata
- **DatabaseStats** — fileSizeBytes, dbPath, lastBackupTime, rowCountsByTable
- **DatabaseIntegrityReport** — findings, checkedAt, schemaVersion
- **DatabaseIntegrityFinding** — severity, category, checkType, title, description, affectedId/Entity, context
- **IntegrityFix*** — enums/sealed classes για επιδιορθώσεις ακεραιότητας

### `lib/features/directory/models/`
- **DepartmentModel** — id, name, building, color, notes, groupName, floorId, map* γεωμετρία/ετικέτα, directPhones, isDeleted, isHiddenOnMap
- **CategoryModel** — id, name
- **NonUserPhoneEntry** — phoneId, number, departmentNamesDisplay, primaryDepartmentId
- **DepartmentDirectoryColumn / CategoryDirectoryColumn / UserDirectoryColumn / EquipmentColumn** — key, label, sortKey (+ στατικές στήλες)
- **UserCatalogMode** (enum) — personal, shared
- **EquipmentRow** (typedef) — (EquipmentModel, UserModel?)

### `lib/features/dictionary/models/`
- **LexiconListFiltersModel** — langFilter, sourceFilter, categoryFilter, columnGroups, lettersCompareOp, lettersCount, diacriticMarksFilter, page (αποθηκεύονται στη βάση· όχι αναζήτηση)

### `lib/features/history/models/`
- **DashboardFilterModel** — keyword, dateFrom, dateTo, department, userName, equipmentCode, topN
- **DashboardSummaryModel** — KPIs, trends, sparklines, byDepartment, byIssue, longestCalls, hourlyDistribution, …
- **DepartmentStat, IssueStat, DailyTrendPoint, CallerStat, LongestCallEntry, HourlyBucket, KpiBarSparklinePoint** — βοηθητικά dashboard
- **DashboardDatePreset** (enum) — today, last7, last30, all, custom
- **LansweeperConnectionStatus** (sealed) — checking, available, unavailable
- **LansweeperSyncState** — unsent, sent, excluded, failed

### `lib/features/tasks/models/`
- **Task** — id, callId, entity ids/texts, title, description, dueDate, snoozeUntil, snoozeHistoryJson, status, priority, solutionNotes, origin, timestamps, isDeleted
- **TaskFilter** — searchQuery, statuses, date range, sortBy, sortAscending
- **TaskSettingsConfig** — dayEndTime, nextBusinessHour, skipWeekends, snooze defaults
- **TaskAnalyticsSummary / TaskAnalyticsFilter / TaskAnalyticsDatePreset** — αναλυτικά εκκρεμοτήτων
- **TaskStatus** (enum), **TaskSnoozeEntry**, **TaskSortOption** (enum)

### `lib/core/models/`
- **RemoteTool** — id, name, role, executablePath, launchMode, arguments, testTargetIp, isExclusive, …
- **RemoteToolArg, RemoteToolArgument, ToolRole** (enum)
- **BuildingMapFloor** — id, sortOrder, label, floorGroup, imagePath, rotationDegrees
- **DictionaryImportMode** (enum), **WindowPlacementMode** (enum)
- **CallsScreenCardsVisibility** — toggles καρτών οθόνης Κλήσεων

### `lib/core/about/models/`
- **ChangelogEntry** — version, date, added, changed, fixed

### Μοντέλα εκτός `models/`
- **HistoryFilterModel** — `history_provider.dart` (keyword, dates, category, department, …)
- **EquipmentViewModel** — `lamp_result_card.dart` (προβολή Λάμπας)

### Σημαντικοί τύποι χωρίς επίθημα Model
| Περιοχή | Τύποι |
|---------|--------|
| Αρχικοποίηση βάσης | `DatabaseStatus`, `DatabaseInitResult`, `DatabaseInitException`, `DatabaseInitRunnerResult`, `DatabaseInitProgressState`, `ConnectionCheckResult`, `TablePreviewResult` |
| Εφαρμογή | `AppInitResult` |
| Ρυθμίσεις | `AuditRetentionConfig` |
| Υπηρεσίες | `LookupResult`, `ImportResult` (excel), `ImportLogLevel` (enum) |
| Κλήσεις | `CallEntryState`, `SmartEntitySelectorState`, `OrphanQuickAddResult`, `LookupLoadResult` |
| Κατάλογος | `DirectoryState`, `CategoryDirectoryState`, `DepartmentDirectoryState`, `EquipmentDirectoryState`, `EquipmentDeleteUndoEntry`, `BuildingMapFloorDeleteChoice` |
| Βάση | `ReplaceDatabaseResult`, `DatabaseBackupResult`, `BackupDestinationValidationResult` |
| Εργασίες | `TaskSnoozeEntry` (nested στο Task) |
| Λεξικό | `LexiconSpellingPanelState`, `LexiconSpellingTarget` — πάνελ ορθογραφίας |
| Gemini | `GeminiTextModel`, `GeminiModelProbeResult`, `GeminiModelsProbeCache` — probe μοντέλων ΤΝ |

---

## 4) STATE MANAGEMENT — PROVIDERS (Riverpod)

### Αρχικοποίηση & πυρήνας
- **appInitProvider** — μονοσήμαντη εκκίνηση εφαρμογής
- **databaseInitProgressProvider** — πρόοδος init βάσης
- **lookupServiceProvider** — in-memory κατάλογος χρηστών/εξοπλισμού
- **activeProfileProvider** — CLI προφίλ (`--profile`)
- **applicationResetPendingProvider** — ροή «Ξεκίνα από την αρχή»

### Κλήσεις
- **callEntryProvider** — φόρμα καταχώρησης κλήσης
- **callSmartEntityProvider / taskSmartEntityProvider / historyEditSmartEntityProvider** — έξυπνος επιλογέας οντοτήτων
- **recentCallsProvider, globalRecentCallsProvider** — πρόσφατες κλήσεις
- **remoteToolsCatalogProvider** — κατάλογος απομακρυσμένων εργαλείων

### Ιστορικό & dashboard
- **historyFilterProvider, historyCallsProvider** — φίλτρα και λίστα ιστορικού
- **dashboardFilterProvider, dashboardStatsProvider** — στατιστικά KPI
- **lansweeperSyncProvider, lansweeperConnectionProbeProvider** — Lansweeper integration
- **lansweeperApiUrlProvider … geminiModelsProbeCacheProvider** — ρυθμίσεις API/Gemini

### Εκκρεμότητες
- **taskFilterProvider, tasksProvider, globalPendingTasksCountProvider**
- **taskSettingsConfigProvider, taskAnalyticsProvider**

### Κατάλογος
- **directoryProvider, departmentDirectoryProvider, equipmentDirectoryProvider, categoryDirectoryProvider**
- **buildingMapControllerProvider** + undo/jump providers — χάρτης κτιρίου
- **directoryTabIntentProvider, equipmentFocusIntentProvider, userFormEditIntentProvider**

### Audit
- **auditFilterProvider, auditListProvider, selectedAuditEntryIdProvider, auditEntityPreviewProvider**

### Βάση & backup
- **databaseIntegrityProvider, databaseBackupSettingsProvider, backupSchedulerProvider**
- **databaseBrowserStatsProvider, databaseMaintenanceServiceProvider**

### Λεξικό & ορθογραφία
- **coreLexiconProvider, greekDictionaryServiceProvider, spellCheckServiceProvider**
- **lexiconFullModeProvider, lexiconCategoriesProvider, lexiconLanguageRecalcProvider**
- **lexiconListFiltersProvider** — απομνημόνευση φίλτρων λίστας (όχι αναζήτηση)
- **lexiconContinuousScrollProvider, lexiconPageSizeProvider**
- **lexiconSpellingPanelProvider** — πάνελ ορθογραφίας (ΤΝ / διαδίκτυο κατόπιν αιτήματος)

### Λάμπα, πλοήγηση, ρυθμίσεις
- **lampReadPathHealthProvider, lampOpenSettingsRequestProvider**
- **mainNavRequestProvider, shellNavigationIntentProvider**
- **settings_provider** — timer, badges, ορατότητα καρτών, nav items
- **appVersionProvider, changelogProvider**

---

## 5) DEPENDENCIES (pubspec.yaml)

**SDK:** `^3.10.7` · **Έκδοση εφαρμογής:** `0.14.0+19`

### dependencies
| Πακέτο | Έκδοση |
|--------|--------|
| flutter / flutter_localizations | sdk |
| cupertino_icons | ^1.0.9 |
| flutter_riverpod | ^3.3.1 |
| sqflite_common | 2.5.8 |
| sqflite_common_ffi | 2.4.0+3 |
| sqlite3_flutter_libs | ^0.6.0+eol |
| path_provider | ^2.1.2 |
| path | ^1.9.0 |
| google_fonts | ^8.1.0 |
| intl | ^0.20.2 |
| characters | ^1.4.0 |
| window_manager | ^0.5.1 |
| screen_retriever | ^0.2.0 |
| shared_preferences | ^2.5.5 |
| url_launcher | ^6.3.2 |
| http | ^1.2.0 |
| justkawal_excel_updated | ^5.0.0 |
| file_picker | ^12.0.0-beta.4 |
| fl_chart | ^1.2.0 |
| archive | ^4.0.9 |
| win32 | ^6.3.0 |
| ffi | ^2.2.0 |
| custom_mouse_cursor | ^1.1.3 |
| package_info_plus | ^10.1.0 |
| image | ^4.9.0 |

### dev_dependencies
- flutter_test, integration_test (sdk)
- riverpod ^3.2.1
- flutter_lints ^6.0.0

### dependency_overrides (κύρια)
`_fe_analyzer_shared`, `analyzer`, `archive`, `image`, `meta`, `test`/`test_api`/`test_core`, `vector_math`, `xml`, `objective_c`, …

---

*Τέλος εγγράφου — ενημερώστε την ημερομηνία όταν αλλάζει ουσιαστικά το σχήμα ή η δομή.*
