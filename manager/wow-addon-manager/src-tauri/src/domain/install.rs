use serde::{Deserialize, Serialize};

use super::addon::{AddonProviderKind, LocalAddon};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum InstallSource {
    LocalZip {
        file_path: String,
    },
    Provider {
        provider: AddonProviderKind,
        remote_id: String,
        file_id: Option<String>,
    },
    ManualUrl {
        url: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DetectedAddonFolder {
    pub folder_name: String,
    pub source_path: String,
    pub toc_present: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum InstallAction {
    BackupExistingFolder,
    RemoveExistingFolder,
    CopyNewFolder,
    UpdateDatabase,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstallPlan {
    pub id: String,
    pub installation_id: String,
    pub source: InstallSource,
    pub temp_extract_path: String,
    pub detected_addon_folders: Vec<DetectedAddonFolder>,
    pub target_addon_path: String,
    pub backup_path: Option<String>,
    pub actions: Vec<InstallAction>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstallResult {
    pub success: bool,
    pub installed_addons: Vec<LocalAddon>,
    pub backup_path: Option<String>,
    pub rollback_available: bool,
    pub message: Option<String>,
}
