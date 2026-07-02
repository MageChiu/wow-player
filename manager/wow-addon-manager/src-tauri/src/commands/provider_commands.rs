use std::path::Path;

use serde::Deserialize;
use tauri::State;

use crate::app::AppState;
use crate::commands::installer_commands::run_plan;
use crate::domain::{
    AddonFile, AddonProviderKind, AddonUpdateInfo, AppError, AppErrorCode, AppResult, GameFlavor,
    InstallResult, InstallSource, RemoteAddon,
};
use crate::installer::plan_from_zip;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchRemoteAddonsInput {
    pub provider: AddonProviderKind,
    pub keyword: String,
    #[serde(default)]
    pub game_flavor: Option<GameFlavor>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GetRemoteAddonFilesInput {
    pub provider: AddonProviderKind,
    pub remote_id: String,
    #[serde(default)]
    pub game_flavor: Option<GameFlavor>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InstallAddonFromProviderInput {
    pub installation_id: String,
    pub provider: AddonProviderKind,
    pub remote_id: String,
    #[serde(default)]
    pub file_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CheckAddonUpdatesInput {
    pub installation_id: String,
}

/// 通过指定 Provider 搜索远程插件。
#[tauri::command]
pub fn search_remote_addons(
    state: State<'_, AppState>,
    input: SearchRemoteAddonsInput,
) -> AppResult<Vec<RemoteAddon>> {
    state
        .providers
        .search(&input.provider, &input.keyword, input.game_flavor)
}

/// 获取远程插件的可下载文件列表。
#[tauri::command]
pub fn get_remote_addon_files(
    state: State<'_, AppState>,
    input: GetRemoteAddonFilesInput,
) -> AppResult<Vec<AddonFile>> {
    state
        .providers
        .get_files(&input.provider, &input.remote_id, input.game_flavor)
}

/// 从 Provider 安装：下载文件 → 复用 Installer 安装（备份/复制/回滚）→ 重扫写库。
#[tauri::command]
pub fn install_addon_from_provider(
    state: State<'_, AppState>,
    input: InstallAddonFromProviderInput,
) -> AppResult<InstallResult> {
    let installation = require_installation(&state, &input.installation_id)?;

    // 1. 选定要下载的文件（指定 file_id 则取该文件，否则取第一个）。
    let files =
        state
            .providers
            .get_files(&input.provider, &input.remote_id, Some(installation.flavor.clone()))?;
    let file = pick_file(files, input.file_id.as_deref())?;

    // 2. 下载到临时目录。
    let work_root = state.platform.temp_dir()?;
    let download_dir = work_root.join("provider_downloads");
    let downloaded = state
        .providers
        .download(&input.provider, &file, &download_dir)?;

    // 3. 从下载的 zip 生成安装计划，并标注来源为 Provider。
    let mut plan = plan_from_zip(
        &installation.id,
        Path::new(&installation.addon_path),
        &downloaded,
        &work_root,
    )?;
    plan.source = InstallSource::Provider {
        provider: input.provider,
        remote_id: input.remote_id,
        file_id: Some(file.file_id.clone()),
    };

    // 4. 执行安装（内部重扫写库 + 记 history），随后清理下载与临时解压。
    let result = run_plan(&state, &plan);
    let _ = crate::installer::fs_ops::remove_dir(&download_dir);
    let _ = crate::installer::fs_ops::remove_dir(Path::new(&plan.temp_extract_path));
    result
}

/// 检查已安装插件的可更新情况：对带有 provider + remote_id 的插件查询最新版本对比。
#[tauri::command]
pub fn check_addon_updates(
    state: State<'_, AppState>,
    input: CheckAddonUpdatesInput,
) -> AppResult<Vec<AddonUpdateInfo>> {
    let installation = require_installation(&state, &input.installation_id)?;
    let addons = state.get_addons(&installation.id)?;

    let mut updates = Vec::new();
    for addon in addons {
        let (Some(provider), Some(remote_id)) = (addon.provider.clone(), addon.remote_id.clone())
        else {
            continue; // 未记录来源的插件无法检查更新。
        };

        let latest_version = match state.providers.get_files(
            &provider,
            &remote_id,
            Some(installation.flavor.clone()),
        ) {
            Ok(files) => files.into_iter().find_map(|f| f.version),
            Err(_) => None, // 单个插件检查失败不影响整体。
        };

        let update_available = match (&addon.version, &latest_version) {
            (Some(cur), Some(latest)) => cur != latest,
            _ => false,
        };

        updates.push(AddonUpdateInfo {
            folder_name: addon.folder_name,
            current_version: addon.version,
            latest_version,
            provider: Some(provider),
            update_available,
        });
    }
    Ok(updates)
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

/// 从文件列表中选定目标文件。
fn pick_file(files: Vec<AddonFile>, file_id: Option<&str>) -> AppResult<AddonFile> {
    match file_id {
        Some(id) => files
            .into_iter()
            .find(|f| f.file_id == id)
            .ok_or_else(|| {
                AppError::new(AppErrorCode::ProviderError, "指定的文件不存在")
                    .with_detail(id.to_string())
                    .recoverable(true)
            }),
        None => files.into_iter().next().ok_or_else(|| {
            AppError::new(AppErrorCode::ProviderError, "该插件没有可下载的文件")
                .recoverable(true)
        }),
    }
}
