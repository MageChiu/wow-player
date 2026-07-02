use std::path::Path;

use serde::Deserialize;
use tauri::State;

use crate::app::AppState;
use crate::domain::{AppError, AppErrorCode, AppResult, WowInstallation};
use crate::platform::adapter::now_ts;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ValidateInstallationPathInput {
    pub root_path: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AddInstallationInput {
    pub root_path: String,
    #[serde(default)]
    pub display_name: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoveInstallationInput {
    pub installation_id: String,
}

/// 扫描默认路径，返回识别到的安装（不落库）。
#[tauri::command]
pub fn detect_installations(state: State<'_, AppState>) -> AppResult<Vec<WowInstallation>> {
    state.platform.detect_wow_installations()
}

/// 校验用户传入目录，返回主安装（Retail 优先）。
#[tauri::command]
pub fn validate_installation_path(
    state: State<'_, AppState>,
    input: ValidateInstallationPathInput,
) -> AppResult<WowInstallation> {
    state
        .platform
        .validate_installation_path(Path::new(&input.root_path))
}

/// 校验并添加目录下的全部安装，返回新增/更新后的安装列表。
#[tauri::command]
pub fn add_installation(
    state: State<'_, AppState>,
    input: AddInstallationInput,
) -> AppResult<Vec<WowInstallation>> {
    let mut resolved = state
        .platform
        .resolve_installations(Path::new(&input.root_path))?;

    if resolved.is_empty() {
        return Err(AppError::new(
            AppErrorCode::InvalidInstallationPath,
            "未识别到有效的魔兽世界目录",
        )
        .with_detail(input.root_path.clone())
        .recoverable(true));
    }

    // 单一安装时允许用户自定义显示名。
    if let (Some(name), 1) = (input.display_name.as_ref(), resolved.len()) {
        if !name.trim().is_empty() {
            resolved[0].display_name = name.trim().to_string();
        }
    }

    let ts = now_ts();
    let mut added = Vec::with_capacity(resolved.len());
    for mut inst in resolved {
        inst.updated_at = ts;
        state.upsert_installation(&inst)?;
        added.push(inst);
    }
    Ok(added)
}

/// 列出已添加的安装。
#[tauri::command]
pub fn list_installations(state: State<'_, AppState>) -> AppResult<Vec<WowInstallation>> {
    state.list_installations()
}

/// 移除已添加的安装。
#[tauri::command]
pub fn remove_installation(
    state: State<'_, AppState>,
    input: RemoveInstallationInput,
) -> AppResult<()> {
    if state.remove_installation(&input.installation_id)? {
        Ok(())
    } else {
        Err(AppError::new(
            AppErrorCode::InstallationNotFound,
            "未找到对应的安装",
        )
        .with_detail(input.installation_id))
    }
}
