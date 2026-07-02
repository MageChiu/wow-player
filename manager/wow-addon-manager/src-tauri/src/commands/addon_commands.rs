use std::path::Path;

use serde::Deserialize;
use tauri::State;

use crate::app::AppState;
use crate::domain::{AppError, AppErrorCode, AppResult, LocalAddon};
use crate::scanner::scan_addons as scan_addons_dir;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ScanAddonsInput {
    pub installation_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ListAddonsInput {
    pub installation_id: String,
}

/// 扫描指定安装的 `AddOns` 目录，刷新并返回插件列表。
#[tauri::command]
pub fn scan_addons(
    state: State<'_, AppState>,
    input: ScanAddonsInput,
) -> AppResult<Vec<LocalAddon>> {
    let installation = state
        .get_installation(&input.installation_id)?
        .ok_or_else(|| {
            AppError::new(AppErrorCode::InstallationNotFound, "未找到对应的安装")
                .with_detail(input.installation_id.clone())
        })?;

    let addons = scan_addons_dir(&installation.id, Path::new(&installation.addon_path))?;
    state.set_addons(&installation.id, &addons)?;
    Ok(addons)
}

/// 返回最近一次扫描到的插件列表（不重新扫描磁盘）。
#[tauri::command]
pub fn list_addons(
    state: State<'_, AppState>,
    input: ListAddonsInput,
) -> AppResult<Vec<LocalAddon>> {
    state.get_addons(&input.installation_id)
}
