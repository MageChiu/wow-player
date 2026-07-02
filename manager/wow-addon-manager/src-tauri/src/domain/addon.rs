use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum GameFlavor {
    Retail,
    Classic,
    ClassicEra,
    Ptr,
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PermissionCheckResult {
    pub readable: bool,
    pub writable: bool,
    pub reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WowInstallation {
    pub id: String,
    pub display_name: String,
    pub root_path: String,
    pub flavor: GameFlavor,
    pub addon_path: String,
    pub wtf_path: String,
    pub is_valid: bool,
    pub permission: PermissionCheckResult,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AddonStatus {
    Installed,
    Disabled,
    MissingDependency,
    UpdateAvailable,
    Broken,
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "snake_case")]
pub enum AddonProviderKind {
    LocalZip,
    GithubRelease,
    Wago,
    CurseForge,
    ManualUrl,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocalAddon {
    pub id: String,
    pub installation_id: String,
    pub folder_name: String,
    pub normalized_folder_name: String,
    pub title: Option<String>,
    pub version: Option<String>,
    pub author: Option<String>,
    pub interface_version: Option<String>,
    pub notes: Option<String>,
    pub dependencies: Vec<String>,
    pub optional_dependencies: Vec<String>,
    pub saved_variables: Vec<String>,
    pub saved_variables_per_character: Vec<String>,
    pub provider: Option<AddonProviderKind>,
    pub remote_id: Option<String>,
    pub source_url: Option<String>,
    pub status: AddonStatus,
    pub installed_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemoteAddon {
    pub provider: AddonProviderKind,
    pub remote_id: String,
    pub title: String,
    pub summary: Option<String>,
    pub author: Option<String>,
    pub latest_version: Option<String>,
    pub game_flavors: Vec<GameFlavor>,
    pub homepage_url: Option<String>,
    pub source_url: Option<String>,
    pub download_count: Option<i64>,
    pub updated_at: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AddonFile {
    pub provider: AddonProviderKind,
    pub remote_id: String,
    pub file_id: String,
    pub file_name: String,
    pub version: Option<String>,
    pub download_url: String,
    pub checksum: Option<String>,
    pub game_flavor: GameFlavor,
    pub released_at: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AddonUpdateInfo {
    pub folder_name: String,
    pub current_version: Option<String>,
    pub latest_version: Option<String>,
    pub provider: Option<AddonProviderKind>,
    pub update_available: bool,
}
