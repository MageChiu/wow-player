use std::collections::HashMap;
use std::path::Path;

use serde::Deserialize;
use tauri::State;
use uuid::Uuid;

use crate::app::AppState;
use crate::domain::{
    AppError, AppErrorCode, AppResult, ApplyProfileResult, ConfigSnapshot, Profile, SnapshotScope,
};
use crate::infra::{ProfileRepository, SnapshotRepository};
use crate::platform::adapter::now_ts;
use crate::scanner::scan_addons as scan_addons_dir;
use crate::services::{ConfigService, CreateSnapshotParams, ProfileService};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateProfileInput {
    pub installation_id: String,
    pub name: String,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub addon_folder_names: Vec<String>,
    #[serde(default)]
    pub snapshot_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ListProfilesInput {
    pub installation_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateProfileInput {
    pub profile_id: String,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub addon_folder_names: Option<Vec<String>>,
    #[serde(default)]
    pub snapshot_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ApplyProfileInput {
    pub profile_id: String,
    #[serde(default)]
    pub create_snapshot_before_apply: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeleteProfileInput {
    pub profile_id: String,
}

/// 创建 Profile：记录目标插件集合，落库（含 profile_addons）。
#[tauri::command]
pub fn create_profile(
    state: State<'_, AppState>,
    input: CreateProfileInput,
) -> AppResult<Profile> {
    require_installation(&state, &input.installation_id)?;

    let now = now_ts();
    let profile = Profile {
        id: format!("profile_{}", Uuid::new_v4().simple()),
        installation_id: input.installation_id,
        name: input.name,
        description: input.description,
        addon_folder_names: input.addon_folder_names,
        snapshot_id: input.snapshot_id,
        created_at: now,
        updated_at: now,
    };

    state
        .db
        .with_transaction(|tx| ProfileRepository::upsert(tx, &profile))?;
    Ok(profile)
}

/// 列出某安装的所有 Profile。
#[tauri::command]
pub fn list_profiles(
    state: State<'_, AppState>,
    input: ListProfilesInput,
) -> AppResult<Vec<Profile>> {
    state
        .db
        .with_connection(|c| ProfileRepository::list_by_installation(c, &input.installation_id))
}

/// 更新 Profile 的名称/描述/插件集合/绑定快照（仅传入的字段生效）。
#[tauri::command]
pub fn update_profile(
    state: State<'_, AppState>,
    input: UpdateProfileInput,
) -> AppResult<Profile> {
    let mut profile = require_profile(&state, &input.profile_id)?;

    if let Some(name) = input.name {
        profile.name = name;
    }
    if input.description.is_some() {
        profile.description = input.description;
    }
    if let Some(folders) = input.addon_folder_names {
        profile.addon_folder_names = folders;
    }
    if input.snapshot_id.is_some() {
        profile.snapshot_id = input.snapshot_id;
    }
    profile.updated_at = now_ts();

    state
        .db
        .with_transaction(|tx| ProfileRepository::upsert(tx, &profile))?;
    Ok(profile)
}

/// 应用 Profile：可选先建当前快照 → 启用 Profile 内插件、禁用 Profile 外插件 → 重扫写库。
#[tauri::command]
pub fn apply_profile(
    state: State<'_, AppState>,
    input: ApplyProfileInput,
) -> AppResult<ApplyProfileResult> {
    let profile = require_profile(&state, &input.profile_id)?;
    let installation = require_installation(&state, &profile.installation_id)?;

    // 1. 可选：应用前创建当前 WTF 快照，便于回退到应用前状态。
    let snapshot_id = if input.create_snapshot_before_apply {
        let snapshot = create_pre_apply_snapshot(&state, &installation, &profile)?;
        Some(snapshot.id)
    } else {
        None
    };

    // 2. 目录重命名启停。
    let addon_path = Path::new(&installation.addon_path);
    let outcome = ProfileService::apply_to_addons(addon_path, &profile.addon_folder_names)?;

    // 3. 重扫刷新数据库，保持与磁盘一致。
    let addons = scan_addons_dir(&installation.id, addon_path)?;
    state.set_addons(&installation.id, &addons)?;

    let message = Some(format!(
        "已应用 Profile「{}」：启用 {} 个、禁用 {} 个插件",
        profile.name,
        outcome.enabled.len(),
        outcome.disabled.len()
    ));
    Ok(ApplyProfileResult {
        success: true,
        snapshot_id,
        enabled: outcome.enabled,
        disabled: outcome.disabled,
        message,
    })
}

/// 删除 Profile 及其关联插件集合。
#[tauri::command]
pub fn delete_profile(state: State<'_, AppState>, input: DeleteProfileInput) -> AppResult<()> {
    state
        .db
        .with_transaction(|tx| ProfileRepository::delete(tx, &input.profile_id))?;
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

fn require_profile(state: &State<'_, AppState>, profile_id: &str) -> AppResult<Profile> {
    state
        .db
        .with_connection(|c| ProfileRepository::get(c, profile_id))?
        .ok_or_else(|| {
            AppError::new(AppErrorCode::Unknown, "未找到对应的 Profile")
                .with_detail(profile_id.to_string())
                .recoverable(true)
        })
}

/// 应用前创建 FullWtf 快照并落库，返回快照记录。
fn create_pre_apply_snapshot(
    state: &State<'_, AppState>,
    installation: &crate::domain::WowInstallation,
    profile: &Profile,
) -> AppResult<ConfigSnapshot> {
    let snapshots_root = state.platform.app_data_dir()?.join("snapshots");
    let addon_versions = current_addon_versions(state, &installation.id)?;

    let snapshot = ConfigService::create_snapshot(CreateSnapshotParams {
        installation_id: &installation.id,
        name: &format!("应用 Profile 前：{}", profile.name),
        scope: SnapshotScope::FullWtf,
        target: None,
        description: Some(format!("apply profile {}", profile.id)),
        wtf_path: Path::new(&installation.wtf_path),
        snapshots_root: &snapshots_root,
        addon_versions,
    })?;

    state
        .db
        .with_connection(|c| SnapshotRepository::insert(c, &snapshot))?;
    Ok(snapshot)
}

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
