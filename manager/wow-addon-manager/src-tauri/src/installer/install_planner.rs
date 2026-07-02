use std::path::{Path, PathBuf};

use uuid::Uuid;

use crate::domain::{
    AppResult, DetectedAddonFolder, InstallAction, InstallPlan, InstallSource,
};
use crate::installer::addon_folder_detector::detect_addon_folders;
use crate::installer::zip_service::ZipService;

/// 依据一个本地 zip 生成安装计划：校验 → 解压到临时目录 → 识别插件目录。
///
/// `work_root` 为临时工作根目录（由平台适配器提供）。
pub fn plan_from_zip(
    installation_id: &str,
    target_addon_path: &Path,
    zip_path: &Path,
    work_root: &Path,
) -> AppResult<InstallPlan> {
    ZipService::validate(zip_path)?;

    let plan_id = format!("plan_{}", Uuid::new_v4().simple());
    let temp_extract = work_root.join(&plan_id);
    ZipService::extract(zip_path, &temp_extract)?;

    let detected = detect_addon_folders(&temp_extract)?;
    let actions = build_actions(target_addon_path, &detected);
    let warnings = build_warnings(target_addon_path, &detected);

    let backup_needed = actions.contains(&InstallAction::BackupExistingFolder);
    let backup_path = backup_needed.then(|| {
        work_root
            .join(format!("{plan_id}_backup"))
            .to_string_lossy()
            .to_string()
    });

    Ok(InstallPlan {
        id: plan_id,
        installation_id: installation_id.to_string(),
        source: InstallSource::LocalZip {
            file_path: zip_path.to_string_lossy().to_string(),
        },
        temp_extract_path: temp_extract.to_string_lossy().to_string(),
        detected_addon_folders: detected,
        target_addon_path: target_addon_path.to_string_lossy().to_string(),
        backup_path,
        actions,
        warnings,
    })
}

fn build_actions(
    target_addon_path: &Path,
    detected: &[DetectedAddonFolder],
) -> Vec<InstallAction> {
    let mut actions = Vec::new();
    let any_existing = detected
        .iter()
        .any(|d| existing_target(target_addon_path, d).exists());

    if any_existing {
        actions.push(InstallAction::BackupExistingFolder);
        actions.push(InstallAction::RemoveExistingFolder);
    }
    actions.push(InstallAction::CopyNewFolder);
    actions.push(InstallAction::UpdateDatabase);
    actions
}

fn build_warnings(target_addon_path: &Path, detected: &[DetectedAddonFolder]) -> Vec<String> {
    detected
        .iter()
        .filter(|d| existing_target(target_addon_path, d).exists())
        .map(|d| format!("插件 {} 已存在，将被更新（更新前会备份）", d.folder_name))
        .collect()
}

pub(crate) fn existing_target(target_addon_path: &Path, d: &DetectedAddonFolder) -> PathBuf {
    target_addon_path.join(&d.folder_name)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::installer::test_support::make_zip;
    use std::fs;

    #[test]
    fn plan_detects_and_sets_actions_no_existing() {
        let tmp = tempfile::tempdir().unwrap();
        let zip_path = tmp.path().join("wa.zip");
        make_zip(
            &zip_path,
            &[("WeakAuras/WeakAuras.toc", b"## Title: WA\n")],
        );
        let target = tmp.path().join("AddOns");
        fs::create_dir_all(&target).unwrap();
        let work = tmp.path().join("work");

        let plan = plan_from_zip("inst1", &target, &zip_path, &work).unwrap();
        assert_eq!(plan.detected_addon_folders.len(), 1);
        assert_eq!(plan.detected_addon_folders[0].folder_name, "WeakAuras");
        assert!(plan.actions.contains(&InstallAction::CopyNewFolder));
        assert!(!plan.actions.contains(&InstallAction::BackupExistingFolder));
        assert!(plan.backup_path.is_none());
        assert!(plan.warnings.is_empty());
    }

    #[test]
    fn plan_flags_backup_when_existing() {
        let tmp = tempfile::tempdir().unwrap();
        let zip_path = tmp.path().join("wa.zip");
        make_zip(&zip_path, &[("WeakAuras/WeakAuras.toc", b"## Title: WA\n")]);
        let target = tmp.path().join("AddOns");
        fs::create_dir_all(target.join("WeakAuras")).unwrap();
        let work = tmp.path().join("work");

        let plan = plan_from_zip("inst1", &target, &zip_path, &work).unwrap();
        assert!(plan.actions.contains(&InstallAction::BackupExistingFolder));
        assert!(plan.backup_path.is_some());
        assert_eq!(plan.warnings.len(), 1);
    }
}
