pub mod app;
pub mod commands;
pub mod domain;
pub mod infra;
pub mod installer;
pub mod platform;
pub mod providers;
pub mod scanner;
pub mod services;

use tauri::Manager;

use crate::app::bootstrap;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            // 平台适配器负责 app data 目录等平台差异（A1）。
            let state = bootstrap().expect("failed to bootstrap application state");
            app.manage(state);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::system_commands::health_check,
            commands::installation_commands::detect_installations,
            commands::installation_commands::validate_installation_path,
            commands::installation_commands::add_installation,
            commands::installation_commands::list_installations,
            commands::installation_commands::remove_installation,
            commands::addon_commands::scan_addons,
            commands::addon_commands::list_addons,
            commands::installer_commands::create_install_plan_from_zip,
            commands::installer_commands::execute_install_plan,
            commands::installer_commands::install_addon_from_zip,
            commands::installer_commands::rollback_install,
            commands::config_commands::create_config_snapshot,
            commands::config_commands::list_config_snapshots,
            commands::config_commands::restore_config_snapshot,
            commands::config_commands::delete_config_snapshot,
            commands::profile_commands::create_profile,
            commands::profile_commands::list_profiles,
            commands::profile_commands::update_profile,
            commands::profile_commands::apply_profile,
            commands::profile_commands::delete_profile,
            commands::provider_commands::search_remote_addons,
            commands::provider_commands::get_remote_addon_files,
            commands::provider_commands::install_addon_from_provider,
            commands::provider_commands::check_addon_updates,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
