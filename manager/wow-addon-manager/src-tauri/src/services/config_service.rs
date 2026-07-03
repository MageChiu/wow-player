use std::path::{Path, PathBuf};

use log::{info, warn};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::domain::{
    AppError, AppErrorCode, AppResult, ConfigSnapshot, RestoreResult, SnapshotScope,
};
use crate::installer::fs_ops::{move_dir, remove_dir};
use crate::installer::ZipService;
use crate::platform::adapter::now_ts;
use std::collections::HashMap;

/// 快照目录内的元数据文件名。
const METADATA_FILE: &str = "metadata.json";
/// 快照压缩包文件名。
const SNAPSHOT_ZIP: &str = "wtf.zip";

/// 快照 metadata.json 的结构（设计规划 §13.2）。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SnapshotMetadata {
    pub id: String,
    pub installation_id: String,
    pub name: String,
    pub scope: SnapshotScope,
    pub created_at: i64,
    pub addon_versions: HashMap<String, String>,
    #[serde(default)]
    pub description: Option<String>,
}

/// 创建快照的参数。
pub struct CreateSnapshotParams<'a> {
    pub installation_id: &'a str,
    pub name: &'a str,
    pub scope: SnapshotScope,
    pub target: Option<String>,
    pub description: Option<String>,
    /// 待备份的 WTF 目录。
    pub wtf_path: &'a Path,
    /// 快照存储根目录（通常 `<app_data>/snapshots`）。
    pub snapshots_root: &'a Path,
    /// 当前插件版本映射，写入 metadata。
    pub addon_versions: HashMap<String, String>,
}

/// WTF 配置快照服务。仅负责文件系统与 metadata；DB 记录由命令层写入。
pub struct ConfigService;

impl ConfigService {
    /// 创建 `FullWtf` 快照：压缩 WTF → 写 metadata.json → 返回 ConfigSnapshot。
    pub fn create_snapshot(params: CreateSnapshotParams<'_>) -> AppResult<ConfigSnapshot> {
        if !params.wtf_path.is_dir() {
            return Err(AppError::new(AppErrorCode::WtfPathNotFound, "WTF 目录不存在")
                .with_detail(params.wtf_path.display().to_string())
                .recoverable(true));
        }

        let snapshot_id = format!("snapshot_{}", Uuid::new_v4().simple());
        let snapshot_dir = params
            .snapshots_root
            .join(params.installation_id)
            .join(&snapshot_id);
        std::fs::create_dir_all(&snapshot_dir).map_err(|e| {
            AppError::new(AppErrorCode::SnapshotCreateFailed, "创建快照目录失败")
                .with_detail(e.to_string())
        })?;

        let zip_path = snapshot_dir.join(SNAPSHOT_ZIP);
        let size_bytes = match ZipService::compress_dir(params.wtf_path, &zip_path) {
            Ok(size) => size as i64,
            Err(e) => {
                // 压缩失败清理半成品目录。
                let _ = remove_dir(&snapshot_dir);
                return Err(e);
            }
        };

        let created_at = now_ts();
        let metadata = SnapshotMetadata {
            id: snapshot_id.clone(),
            installation_id: params.installation_id.to_string(),
            name: params.name.to_string(),
            scope: params.scope.clone(),
            created_at,
            addon_versions: params.addon_versions.clone(),
            description: params.description.clone(),
        };
        write_metadata(&snapshot_dir.join(METADATA_FILE), &metadata)?;

        info!("snapshot {} created ({} bytes)", snapshot_id, size_bytes);
        Ok(ConfigSnapshot {
            id: snapshot_id,
            installation_id: params.installation_id.to_string(),
            name: params.name.to_string(),
            scope: params.scope,
            target: params.target,
            file_path: zip_path.to_string_lossy().to_string(),
            size_bytes,
            addon_versions: params.addon_versions,
            description: params.description,
            created_at,
        })
    }

    /// 恢复快照到 WTF（设计规划 §13.3）。
    ///
    /// 流程：校验快照可读 → 备份当前 WTF（移动到临时备份）→ 解压恢复 →
    /// 失败则把备份移回原位。`backup_root` 为临时备份存放目录。
    pub fn restore_snapshot(
        snapshot: &ConfigSnapshot,
        wtf_path: &Path,
        backup_root: &Path,
    ) -> AppResult<RestoreResult> {
        let zip_path = PathBuf::from(&snapshot.file_path);
        // 1. 校验快照可读。
        ZipService::validate(&zip_path).map_err(|e| {
            AppError::new(AppErrorCode::SnapshotRestoreFailed, "快照文件不可读")
                .with_detail(e.message)
                .recoverable(true)
        })?;

        // 2. 备份当前 WTF（若存在），移动而非覆盖。
        let backup_dir = backup_root.join(format!(
            "wtf_backup_{}_{}",
            snapshot.installation_id,
            now_ts()
        ));
        let had_existing = wtf_path.exists();
        if had_existing {
            move_dir(wtf_path, &backup_dir).map_err(|e| {
                AppError::new(AppErrorCode::SnapshotRestoreFailed, "备份当前 WTF 失败")
                    .with_detail(e.message)
            })?;
        }

        // 3. 解压恢复。失败则回滚备份。
        match ZipService::extract(&zip_path, wtf_path) {
            Ok(()) => {
                info!("snapshot {} restored", snapshot.id);
                Ok(RestoreResult {
                    success: true,
                    backup_path: had_existing
                        .then(|| backup_dir.to_string_lossy().to_string()),
                    message: Some("配置已恢复".to_string()),
                })
            }
            Err(e) => {
                warn!("restore failed, rolling back WTF: {e}");
                // 清理可能残留的半成品，再把备份移回。
                let _ = remove_dir(wtf_path);
                if had_existing {
                    if let Err(re) = move_dir(&backup_dir, wtf_path) {
                        return Err(AppError::new(
                            AppErrorCode::SnapshotRestoreFailed,
                            "恢复失败且回滚失败，请手动检查备份目录",
                        )
                        .with_detail(format!(
                            "restore={}; rollback={}; backup={}",
                            e.message,
                            re.message,
                            backup_dir.display()
                        )));
                    }
                }
                Err(AppError::new(
                    AppErrorCode::SnapshotRestoreFailed,
                    "配置恢复失败，已回滚到原配置",
                )
                .with_detail(e.message)
                .recoverable(true))
            }
        }
    }

    /// 删除快照的磁盘文件（整个快照目录）。DB 记录由命令层删除。
    pub fn delete_snapshot_files(snapshot: &ConfigSnapshot) -> AppResult<()> {
        // file_path = <...>/<snapshot_id>/wtf.zip，删除其父目录。
        let zip_path = PathBuf::from(&snapshot.file_path);
        if let Some(dir) = zip_path.parent() {
            remove_dir(dir)?;
        }
        Ok(())
    }
}

fn write_metadata(path: &Path, meta: &SnapshotMetadata) -> AppResult<()> {
    let json = serde_json::to_string_pretty(meta).map_err(|e| {
        AppError::new(AppErrorCode::SnapshotCreateFailed, "序列化 metadata 失败")
            .with_detail(e.to_string())
    })?;
    std::fs::write(path, json).map_err(|e| {
        AppError::new(AppErrorCode::SnapshotCreateFailed, "写入 metadata 失败")
            .with_detail(e.to_string())
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn make_wtf(root: &Path) -> PathBuf {
        let wtf = root.join("WTF");
        fs::create_dir_all(wtf.join("Account/PLAYER")).unwrap();
        fs::write(wtf.join("Config.wtf"), "SET foo 1\n").unwrap();
        fs::write(wtf.join("Account/PLAYER/SavedVariables.lua"), "x=1").unwrap();
        wtf
    }

    fn params<'a>(
        wtf: &'a Path,
        snapshots_root: &'a Path,
    ) -> CreateSnapshotParams<'a> {
        let mut versions = HashMap::new();
        versions.insert("WeakAuras".to_string(), "5.12.0".to_string());
        CreateSnapshotParams {
            installation_id: "inst1",
            name: "before update",
            scope: SnapshotScope::FullWtf,
            target: None,
            description: Some("auto".to_string()),
            wtf_path: wtf,
            snapshots_root,
            addon_versions: versions,
        }
    }

    #[test]
    fn create_snapshot_writes_zip_and_metadata() {
        let tmp = tempfile::tempdir().unwrap();
        let wtf = make_wtf(tmp.path());
        let snaps = tmp.path().join("snapshots");

        let snap = ConfigService::create_snapshot(params(&wtf, &snaps)).unwrap();
        assert_eq!(snap.scope, SnapshotScope::FullWtf);
        assert!(snap.size_bytes > 0);
        assert!(Path::new(&snap.file_path).is_file());

        let meta_path = Path::new(&snap.file_path).parent().unwrap().join(METADATA_FILE);
        assert!(meta_path.is_file());
        let meta: SnapshotMetadata =
            serde_json::from_str(&fs::read_to_string(meta_path).unwrap()).unwrap();
        assert_eq!(meta.addon_versions.get("WeakAuras").unwrap(), "5.12.0");
    }

    #[test]
    fn create_snapshot_errors_when_no_wtf() {
        let tmp = tempfile::tempdir().unwrap();
        let missing = tmp.path().join("nope");
        let snaps = tmp.path().join("snapshots");
        let err = ConfigService::create_snapshot(params(&missing, &snaps)).unwrap_err();
        assert_eq!(err.code, AppErrorCode::WtfPathNotFound);
    }

    #[test]
    fn restore_snapshot_replaces_current_wtf() {
        let tmp = tempfile::tempdir().unwrap();
        let wtf = make_wtf(tmp.path());
        let snaps = tmp.path().join("snapshots");
        let backups = tmp.path().join("backups");

        let snap = ConfigService::create_snapshot(params(&wtf, &snaps)).unwrap();

        // 修改当前 WTF，再恢复应回到快照内容。
        fs::write(wtf.join("Config.wtf"), "SET foo 999\n").unwrap();

        let result = ConfigService::restore_snapshot(&snap, &wtf, &backups).unwrap();
        assert!(result.success);
        assert!(result.backup_path.is_some());
        assert_eq!(fs::read_to_string(wtf.join("Config.wtf")).unwrap(), "SET foo 1\n");
    }

    #[test]
    fn restore_rolls_back_on_failure() {
        let tmp = tempfile::tempdir().unwrap();
        let wtf = make_wtf(tmp.path());
        let snaps = tmp.path().join("snapshots");
        let backups = tmp.path().join("backups");

        let mut snap = ConfigService::create_snapshot(params(&wtf, &snaps)).unwrap();
        // 破坏快照文件路径以触发校验失败（恢复应保持当前 WTF 不变）。
        snap.file_path = tmp.path().join("missing.zip").to_string_lossy().to_string();

        fs::write(wtf.join("Config.wtf"), "SET foo 2\n").unwrap();
        let err = ConfigService::restore_snapshot(&snap, &wtf, &backups).unwrap_err();
        assert_eq!(err.code, AppErrorCode::SnapshotRestoreFailed);
        // 当前 WTF 未被破坏。
        assert_eq!(fs::read_to_string(wtf.join("Config.wtf")).unwrap(), "SET foo 2\n");
    }

    #[test]
    fn delete_removes_snapshot_dir() {
        let tmp = tempfile::tempdir().unwrap();
        let wtf = make_wtf(tmp.path());
        let snaps = tmp.path().join("snapshots");

        let snap = ConfigService::create_snapshot(params(&wtf, &snaps)).unwrap();
        let dir = Path::new(&snap.file_path).parent().unwrap().to_path_buf();
        assert!(dir.exists());

        ConfigService::delete_snapshot_files(&snap).unwrap();
        assert!(!dir.exists());
    }
}
