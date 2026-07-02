use std::path::{Path, PathBuf};

use serde::Deserialize;
use tauri::State;
use uuid::Uuid;

use crate::app::AppState;
use crate::domain::{
    AppError, AppErrorCode, AppResult, InstallPlan, InstallResult, LocalAddon,
};
use crate::infra::{InstallHistoryRecord, InstallHistoryRepository};
use crate::installer::{execute_plan, plan_from_zip, restore_backup, ExecutionOutcome};
use crate::platform::adapter::now_ts;
use crate::scanner::scan_addons as scan_addons_dir;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateInstallPlanFromZipInput {
    pub installation_id: String,
    pub zip_path: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExecuteInstallPlanInput {
    pub plan_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InstallAddonFromZipInput {
    pub installation_id: String,
    pub zip_path: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RollbackInstallInput {
    pub installation_id: String,
    pub rollback_id: String,
}

/// 从本地 zip 生成安装计划（不落盘到 AddOns，仅解压到临时目录并识别）。
#[tauri::command]
pub fn create_install_plan_from_zip(
    state: State<'_, AppState>,
    input: CreateInstallPlanFromZipInput,
) -> AppResult<InstallPlan> {
    let installation = require_installation(&state, &input.installation_id)?;
    let work_root = state.platform.temp_dir()?;

    let plan = plan_from_zip(
        &installation.id,
        Path::new(&installation.addon_path),
        Path::new(&input.zip_path),
        &work_root,
    )?;
    state.store_plan(plan.clone());
    Ok(plan)
}

/// 执行已生成的安装计划。
#[tauri::command]
pub fn execute_install_plan(
    state: State<'_, AppState>,
    input: ExecuteInstallPlanInput,
) -> AppResult<InstallResult> {
    let plan = state.take_plan(&input.plan_id).ok_or_else(|| {
        AppError::new(AppErrorCode::InstallPlanNotFound, "安装计划不存在或已过期")
            .with_detail(input.plan_id.clone())
    })?;
    let result = run_plan(&state, &plan);
    cleanup_temp(&plan.temp_extract_path);
    result
}

/// 一步安装：生成计划并立即执行。
#[tauri::command]
pub fn install_addon_from_zip(
    state: State<'_, AppState>,
    input: InstallAddonFromZipInput,
) -> AppResult<InstallResult> {
    let installation = require_installation(&state, &input.installation_id)?;
    let work_root = state.platform.temp_dir()?;
    let plan = plan_from_zip(
        &installation.id,
        Path::new(&installation.addon_path),
        Path::new(&input.zip_path),
        &work_root,
    )?;
    let result = run_plan(&state, &plan);
    cleanup_temp(&plan.temp_extract_path);
    result
}

/// 手动回滚：从备份目录恢复插件，并重扫刷新数据库。
#[tauri::command]
pub fn rollback_install(
    state: State<'_, AppState>,
    input: RollbackInstallInput,
) -> AppResult<()> {
    let installation = require_installation(&state, &input.installation_id)?;
    restore_backup(
        Path::new(&installation.addon_path),
        Path::new(&input.rollback_id),
    )?;
    // 恢复后重扫，保持数据库与磁盘一致。
    let addons = scan_addons_dir(&installation.id, Path::new(&installation.addon_path))?;
    state.set_addons(&installation.id, &addons)?;
    Ok(())
}

// ---- 内部编排 ----

fn require_installation(
    state: &State<'_, AppState>,
    installation_id: &str,
) -> AppResult<crate::domain::WowInstallation> {
    state
        .get_installation(installation_id)?
        .ok_or_else(|| {
            AppError::new(AppErrorCode::InstallationNotFound, "未找到对应的安装")
                .with_detail(installation_id.to_string())
        })
}

/// 执行文件系统安装 → 重扫 → 写库 → 记 install_history。
pub(crate) fn run_plan(state: &State<'_, AppState>, plan: &InstallPlan) -> AppResult<InstallResult> {
    let addon_path = PathBuf::from(&plan.target_addon_path);

    match execute_plan(plan) {
        Ok(outcome) => {
            // 安装成功后重扫并写库。
            let addons = scan_addons_dir(&plan.installation_id, &addon_path)?;
            state.set_addons(&plan.installation_id, &addons)?;
            record_history(state, plan, &outcome, "success", None);

            let installed = filter_installed(&addons, &outcome.installed_folders);
            Ok(InstallResult {
                success: true,
                installed_addons: installed,
                backup_path: outcome.backup_path.clone(),
                rollback_available: outcome.backup_path.is_some(),
                message: Some(format!("成功安装 {} 个插件", outcome.installed_folders.len())),
            })
        }
        Err(e) => {
            // executor 已回滚文件系统；记录失败历史。
            record_history_failed(state, plan, &e);
            Err(e)
        }
    }
}

fn filter_installed(addons: &[LocalAddon], folders: &[String]) -> Vec<LocalAddon> {
    addons
        .iter()
        .filter(|a| folders.contains(&a.folder_name))
        .cloned()
        .collect()
}

fn record_history(
    state: &State<'_, AppState>,
    plan: &InstallPlan,
    outcome: &ExecutionOutcome,
    status: &str,
    error: Option<String>,
) {
    let rec = InstallHistoryRecord {
        id: format!("hist_{}", Uuid::new_v4().simple()),
        installation_id: plan.installation_id.clone(),
        addon_folder_names: outcome.installed_folders.clone(),
        source_type: source_type(plan).to_string(),
        source_ref: source_ref(plan),
        backup_path: outcome.backup_path.clone(),
        status: status.to_string(),
        error_message: error,
        created_at: now_ts(),
    };
    let _ = state.db.with_connection(|c| InstallHistoryRepository::insert(c, &rec));
}

fn record_history_failed(state: &State<'_, AppState>, plan: &InstallPlan, err: &AppError) {
    let rec = InstallHistoryRecord {
        id: format!("hist_{}", Uuid::new_v4().simple()),
        installation_id: plan.installation_id.clone(),
        addon_folder_names: Vec::new(),
        source_type: source_type(plan).to_string(),
        source_ref: source_ref(plan),
        backup_path: plan.backup_path.clone(),
        status: "failed".to_string(),
        error_message: Some(err.message.clone()),
        created_at: now_ts(),
    };
    let _ = state.db.with_connection(|c| InstallHistoryRepository::insert(c, &rec));
}

fn source_type(plan: &InstallPlan) -> &'static str {
    match &plan.source {
        crate::domain::InstallSource::LocalZip { .. } => "local_zip",
        crate::domain::InstallSource::ManualUrl { .. } => "manual_url",
        crate::domain::InstallSource::Provider { .. } => "provider",
    }
}

fn source_ref(plan: &InstallPlan) -> Option<String> {
    match &plan.source {
        crate::domain::InstallSource::LocalZip { file_path } => Some(file_path.clone()),
        crate::domain::InstallSource::ManualUrl { url } => Some(url.clone()),
        crate::domain::InstallSource::Provider { remote_id, .. } => Some(remote_id.clone()),
    }
}

fn cleanup_temp(temp_path: &str) {
    let _ = crate::installer::fs_ops::remove_dir(Path::new(temp_path));
}
