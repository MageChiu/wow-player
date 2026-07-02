use std::collections::HashMap;
use std::path::Path;

use serde::Deserialize;
use tauri::State;

use crate::app::AppState;
use crate::domain::{
    AppError, AppErrorCode, AppResult, ConfigSnapshot, RestoreResult, SnapshotScope,
};
use crate::infra::SnapshotRepository;
use crate::services::{ConfigService, CreateSnapshotParams};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateConfigSnapshotInput {
    pub installation_id: String,
    pub name: String,
    pub scope: SnapshotScope,
    #[serde(default)]
    pub target: Option<String>,
    #[serde(default)]
    pub description: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ListConfigSnapshotsInput {
    pub installation_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RestoreConfigSnapshotInput {
    pub snapshot_id: String,
    #[serde(default)]
    pub create_backup_before_restore: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeleteConfigSnapshotInput {
    pub snapshot_id: String,
}

/// 创建 WTF 快照：压缩 → 写 metadata → 落库。
#[tauri::command]
pub fn create_config_snapshot(
    state: State<'_, AppState>,
    input: CreateConfigSnapshotInput,
) -> AppResult<ConfigSnapshot> {
    let installation = require_installation(&state, &input.installation_id)?;
    let snapshots_root = state.platform.app_data_dir()?.join("snapshots");
    let addon_versions = current_addon_versions(&state, &installation.id)?;

    let snapshot = ConfigService::create_snapshot(CreateSnapshotParams {
        installation_id: &installation.id,
        name: &input.name,
        scope: input.scope,
        target: input.target,
        description: input.description,
        wtf_path: Path::new(&installation.wtf_path),
        snapshots_root: &snapshots_root,
        addon_versions,
    })?;

    state
        .db
        .with_connection(|c| SnapshotRepository::insert(c, &snapshot))?;
    Ok(snapshot)
}

/// 列出某安装的快照。
#[tauri::command]
pub fn list_config_snapshots(
    state: State<'_, AppState>,
    input: ListConfigSnapshotsInput,
) -> AppResult<Vec<ConfigSnapshot>> {
    state
        .db
        .with_connection(|c| SnapshotRepository::list_by_installation(c, &input.installation_id))
}

/// 恢复快照：恢复前自动备份当前 WTF，失败自动回滚。
#[tauri::command]
pub fn restore_config_snapshot(
    state: State<'_, AppState>,
    input: RestoreConfigSnapshotInput,
) -> AppResult<RestoreResult> {
    let snapshot = state
        .db
        .with_connection(|c| SnapshotRepository::get(c, &input.snapshot_id))?
        .ok_or_else(|| {
            AppError::new(AppErrorCode::SnapshotRestoreFailed, "快照不存在")
                .with_detail(input.snapshot_id.clone())
        })?;

    let installation = require_installation(&state, &snapshot.installation_id)?;
    let backup_root = state.platform.temp_dir()?.join("wtf_backups");

    ConfigService::restore_snapshot(&snapshot, Path::new(&installation.wtf_path), &backup_root)
}

/// 删除快照：删磁盘文件 + DB 记录。
#[tauri::command]
pub fn delete_config_snapshot(
    state: State<'_, AppState>,
    input: DeleteConfigSnapshotInput,
) -> AppResult<()> {
    let snapshot = state
        .db
        .with_connection(|c| SnapshotRepository::get(c, &input.snapshot_id))?
        .ok_or_else(|| {
            AppError::new(AppErrorCode::SnapshotRestoreFailed, "快照不存在")
                .with_detail(input.snapshot_id.clone())
        })?;

    ConfigService::delete_snapshot_files(&snapshot)?;
    state
        .db
        .with_connection(|c| SnapshotRepository::delete(c, &input.snapshot_id))?;
    Ok(())
}

// ---- 内部 ----

fn require_installation(
    state: &State<'_, AppState>,
    installation_id: &str,
) -> AppResult<crate::domain::WowInstallation> {
    state.get_installation(installation_id)?.ok_or_else(|| {
        AppError::new(AppErrorCode::InstallationNotFound, "未找到对应的安装")
            .with_detail(installation_id.to_string())
    })
}

/// 从当前已扫描插件构建 folder_name -> version 映射，写入快照 metadata。
fn current_addon_versions(
    state: &State<'_, AppState>,
    installation_id: &str,
) -> AppResult<HashMap<String, String>> {
    let addons = state.get_addons(installation_id)?;
    let mut map = HashMap::new();
    for a in addons {
        if let Some(v) = a.version {
            map.insert(a.normalized_folder_name, v);
        }
    }
    Ok(map)
}
