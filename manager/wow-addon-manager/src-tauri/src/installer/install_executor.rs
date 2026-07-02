use std::path::{Path, PathBuf};

use log::{info, warn};

use crate::domain::{AppError, AppErrorCode, AppResult, InstallPlan};
use crate::installer::fs_ops::{copy_dir_all, move_dir, remove_dir};
use crate::installer::install_planner::existing_target;

/// 执行安装计划的文件系统结果。
#[derive(Debug)]
pub struct ExecutionOutcome {
    /// 实际安装的插件目录名。
    pub installed_folders: Vec<String>,
    /// 备份目录（若发生备份）。
    pub backup_path: Option<String>,
}

/// 执行安装计划的文件系统部分：备份旧目录 → 复制新目录。
/// 任一步失败会自动回滚（恢复备份、清理半成品），并返回结构化错误。
/// DB 写入与 install_history 记录由调用方（命令层）负责。
pub fn execute_plan(plan: &InstallPlan) -> AppResult<ExecutionOutcome> {
    let target_addon_path = PathBuf::from(&plan.target_addon_path);
    let backup_root = plan.backup_path.as_ref().map(PathBuf::from);

    // 记录已完成的步骤，用于失败回滚。
    let mut backed_up: Vec<(String, PathBuf)> = Vec::new(); // (folder_name, backup_dir)
    let mut copied: Vec<PathBuf> = Vec::new(); // 目标位置已复制的新目录

    let result = (|| -> AppResult<Vec<String>> {
        let mut installed = Vec::new();
        for detected in &plan.detected_addon_folders {
            let target = existing_target(&target_addon_path, detected);
            let source = PathBuf::from(&detected.source_path);

            // 1. 若目标已存在，先备份再移除。
            if target.exists() {
                let backup_root = backup_root.as_ref().ok_or_else(|| {
                    AppError::new(AppErrorCode::InstallFailed, "需要备份但未提供备份目录")
                })?;
                let backup_dir = backup_root.join(&detected.folder_name);
                move_dir(&target, &backup_dir)?;
                backed_up.push((detected.folder_name.clone(), backup_dir));
            }

            // 2. 复制新目录到目标位置。
            copy_dir_all(&source, &target)?;
            copied.push(target.clone());
            installed.push(detected.folder_name.clone());
        }
        Ok(installed)
    })();

    match result {
        Ok(installed) => {
            info!(
                "install executed: {} folder(s) installed",
                installed.len()
            );
            Ok(ExecutionOutcome {
                installed_folders: installed,
                backup_path: plan.backup_path.clone(),
            })
        }
        Err(e) => {
            warn!("install failed, rolling back: {e}");
            rollback(&target_addon_path, &copied, &backed_up);
            Err(AppError::new(AppErrorCode::InstallFailed, "安装失败，已回滚")
                .with_detail(e.message)
                .recoverable(true))
        }
    }
}

/// 回滚：删除已复制的新目录，恢复备份目录到原位置。
fn rollback(
    target_addon_path: &Path,
    copied: &[PathBuf],
    backed_up: &[(String, PathBuf)],
) {
    for dir in copied {
        if let Err(e) = remove_dir(dir) {
            warn!("rollback: failed to remove copied dir {}: {e}", dir.display());
        }
    }
    for (folder_name, backup_dir) in backed_up {
        let original = target_addon_path.join(folder_name);
        if let Err(e) = move_dir(backup_dir, &original) {
            warn!(
                "rollback: failed to restore backup {} -> {}: {e}",
                backup_dir.display(),
                original.display()
            );
        }
    }
}

/// 显式回滚一次安装：把备份目录恢复回目标位置（供 rollback_install 命令使用）。
pub fn restore_backup(target_addon_path: &Path, backup_root: &Path) -> AppResult<()> {
    if !backup_root.exists() {
        return Err(AppError::new(AppErrorCode::RollbackFailed, "备份目录不存在")
            .with_detail(backup_root.display().to_string()));
    }
    for entry in std::fs::read_dir(backup_root)
        .map_err(|e| AppError::new(AppErrorCode::RollbackFailed, "读取备份目录失败").with_detail(e.to_string()))?
    {
        let entry = entry
            .map_err(|e| AppError::new(AppErrorCode::RollbackFailed, "遍历备份目录失败").with_detail(e.to_string()))?;
        if !entry.path().is_dir() {
            continue;
        }
        let original = target_addon_path.join(entry.file_name());
        remove_dir(&original)?;
        move_dir(&entry.path(), &original)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::installer::install_planner::plan_from_zip;
    use crate::installer::test_support::make_zip;
    use std::fs;

    fn read(p: &Path) -> String {
        fs::read_to_string(p).unwrap()
    }

    #[test]
    fn installs_new_addon() {
        let tmp = tempfile::tempdir().unwrap();
        let zip_path = tmp.path().join("wa.zip");
        make_zip(&zip_path, &[("WeakAuras/WeakAuras.toc", b"## Title: WA\n")]);
        let target = tmp.path().join("AddOns");
        fs::create_dir_all(&target).unwrap();
        let work = tmp.path().join("work");

        let plan = plan_from_zip("inst1", &target, &zip_path, &work).unwrap();
        let outcome = execute_plan(&plan).unwrap();
        assert_eq!(outcome.installed_folders, vec!["WeakAuras"]);
        assert!(target.join("WeakAuras/WeakAuras.toc").is_file());
    }

    #[test]
    fn updates_existing_with_backup() {
        let tmp = tempfile::tempdir().unwrap();
        let zip_path = tmp.path().join("wa.zip");
        make_zip(&zip_path, &[("WeakAuras/WeakAuras.toc", b"## Version: 2\n")]);
        let target = tmp.path().join("AddOns");
        fs::create_dir_all(target.join("WeakAuras")).unwrap();
        fs::write(target.join("WeakAuras/WeakAuras.toc"), "## Version: 1\n").unwrap();
        let work = tmp.path().join("work");

        let plan = plan_from_zip("inst1", &target, &zip_path, &work).unwrap();
        let outcome = execute_plan(&plan).unwrap();

        // 新版本已就位。
        assert_eq!(read(&target.join("WeakAuras/WeakAuras.toc")), "## Version: 2\n");
        // 备份保留旧版本。
        let backup = PathBuf::from(outcome.backup_path.unwrap());
        assert_eq!(read(&backup.join("WeakAuras/WeakAuras.toc")), "## Version: 1\n");
    }

    #[test]
    fn rollback_restores_on_failure() {
        // 构造：两个插件，第二个 source_path 指向不存在的目录以触发复制失败。
        let tmp = tempfile::tempdir().unwrap();
        let zip_path = tmp.path().join("multi.zip");
        make_zip(
            &zip_path,
            &[
                ("Good/Good.toc", b"## Version: 2\n"),
            ],
        );
        let target = tmp.path().join("AddOns");
        fs::create_dir_all(target.join("Good")).unwrap();
        fs::write(target.join("Good/Good.toc"), "## Version: 1\n").unwrap();
        let work = tmp.path().join("work");

        let mut plan = plan_from_zip("inst1", &target, &zip_path, &work).unwrap();
        // 破坏 source_path 使复制失败。
        plan.detected_addon_folders[0].source_path =
            tmp.path().join("does_not_exist").to_string_lossy().to_string();

        let err = execute_plan(&plan).unwrap_err();
        assert_eq!(err.code, AppErrorCode::InstallFailed);
        // 旧版本应已恢复。
        assert_eq!(read(&target.join("Good/Good.toc")), "## Version: 1\n");
    }
}
