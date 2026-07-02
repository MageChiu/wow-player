use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Profile {
    pub id: String,
    pub installation_id: String,
    pub name: String,
    pub description: Option<String>,
    pub addon_folder_names: Vec<String>,
    pub snapshot_id: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApplyProfileResult {
    pub success: bool,
    pub snapshot_id: Option<String>,
    pub enabled: Vec<String>,
    pub disabled: Vec<String>,
    pub message: Option<String>,
}
