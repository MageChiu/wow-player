use std::collections::HashMap;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SnapshotScope {
    FullWtf,
    Account,
    Character,
    Addon,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfigSnapshot {
    pub id: String,
    pub installation_id: String,
    pub name: String,
    pub scope: SnapshotScope,
    pub target: Option<String>,
    pub file_path: String,
    pub size_bytes: i64,
    pub addon_versions: HashMap<String, String>,
    pub description: Option<String>,
    pub created_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RestoreResult {
    pub success: bool,
    pub backup_path: Option<String>,
    pub message: Option<String>,
}
