pub mod addon_commands;
pub mod config_commands;
pub mod installation_commands;
pub mod installer_commands;
pub mod profile_commands;
pub mod provider_commands;
pub mod system_commands;

pub use addon_commands::{list_addons, scan_addons};
pub use config_commands::{
    create_config_snapshot, delete_config_snapshot, list_config_snapshots,
    restore_config_snapshot,
};
pub use profile_commands::{
    apply_profile, create_profile, delete_profile, list_profiles, update_profile,
};
pub use provider_commands::{
    check_addon_updates, get_remote_addon_files, install_addon_from_provider, search_remote_addons,
};
pub use installation_commands::{
    add_installation, detect_installations, list_installations, remove_installation,
    validate_installation_path,
};
pub use installer_commands::{
    create_install_plan_from_zip, execute_install_plan, install_addon_from_zip, rollback_install,
};
pub use system_commands::health_check;
