use std::path::{Path, PathBuf};

use log::debug;

use crate::domain::{AppError, AppErrorCode, AppResult, GameFlavor, PermissionCheckResult, WowInstallation};

/// WoW flavor 子目录与枚举的映射（设计规划 §10.4）。
/// 顺序不影响匹配（精确匹配），但影响主安装的挑选（Retail 优先）。
const FLAVOR_DIRS: &[(&str, GameFlavor)] = &[
    ("_retail_", GameFlavor::Retail),
    ("_ptr_", GameFlavor::Ptr),
    ("_classic_era_", GameFlavor::ClassicEra),
    ("_classic_", GameFlavor::Classic),
];

/// 平台适配层接口（设计规划 §10.1）。
///
/// 大部分逻辑（flavor 识别、目录校验、权限检测）与平台无关，
/// 通过 trait 的默认实现复用；每个平台只需提供：默认扫描路径、
/// 应用数据/缓存/临时目录、文件管理器打开方式。
pub trait PlatformAdapter: Send + Sync {
    fn platform_name(&self) -> &'static str;

    /// 该平台的 WoW 默认安装扫描路径。
    fn default_scan_paths(&self) -> Vec<PathBuf>;

    fn app_data_dir(&self) -> AppResult<PathBuf>;
    fn cache_dir(&self) -> AppResult<PathBuf>;
    fn temp_dir(&self) -> AppResult<PathBuf>;

    fn reveal_in_file_manager(&self, path: &Path) -> AppResult<()>;

    /// 扫描默认路径，返回所有识别到的安装（按 flavor 展开、去重）。
    fn detect_wow_installations(&self) -> AppResult<Vec<WowInstallation>> {
        let mut out: Vec<WowInstallation> = Vec::new();
        for base in self.default_scan_paths() {
            match resolve_installations_from_root(&base) {
                Ok(mut found) => out.append(&mut found),
                Err(e) => debug!("scan path {} skipped: {}", base.display(), e),
            }
        }
        out.sort_by(|a, b| a.id.cmp(&b.id));
        out.dedup_by(|a, b| a.id == b.id);
        Ok(out)
    }

    /// 从一个 WoW 根目录（或直接的 flavor 目录）解析出全部安装。
    fn resolve_installations(&self, root: &Path) -> AppResult<Vec<WowInstallation>> {
        resolve_installations_from_root(root)
    }

    /// 校验用户传入目录，返回主安装（Retail 优先）。
    /// 无法识别时返回 `InvalidInstallationPath`。
    fn validate_installation_path(&self, root: &Path) -> AppResult<WowInstallation> {
        let resolved = resolve_installations_from_root(root)?;
        resolved
            .into_iter()
            .next()
            .ok_or_else(|| invalid_path_error(root))
    }

    fn check_permission(&self, path: &Path) -> AppResult<PermissionCheckResult> {
        Ok(check_permission(path))
    }
}

/// 当前 unix 时间戳（秒）。
pub fn now_ts() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn invalid_path_error(path: &Path) -> AppError {
    AppError::new(
        AppErrorCode::InvalidInstallationPath,
        "未识别到有效的魔兽世界目录",
    )
    .with_detail(path.display().to_string())
    .recoverable(true)
}

fn flavor_tag(flavor: &GameFlavor) -> &'static str {
    match flavor {
        GameFlavor::Retail => "Retail",
        GameFlavor::Classic => "Classic",
        GameFlavor::ClassicEra => "ClassicEra",
        GameFlavor::Ptr => "PTR",
        GameFlavor::Unknown => "Unknown",
    }
}

/// 基于目录路径与 flavor 生成稳定 id（同一进程内一致）。
fn make_id(flavor_dir: &Path, flavor: &GameFlavor) -> String {
    use std::hash::{Hash, Hasher};
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    flavor_dir.to_string_lossy().hash(&mut hasher);
    flavor_tag(flavor).hash(&mut hasher);
    format!("inst_{:016x}", hasher.finish())
}

fn match_flavor_by_name(dir: &Path) -> Option<GameFlavor> {
    let name = dir.file_name()?.to_string_lossy().to_lowercase();
    FLAVOR_DIRS
        .iter()
        .find(|(d, _)| name == *d)
        .map(|(_, f)| f.clone())
}

/// 构建单个 flavor 的 `WowInstallation`。要求 `Interface/AddOns` 存在才算有效。
fn build_installation(root: &Path, flavor_dir: &Path, flavor: GameFlavor) -> Option<WowInstallation> {
    let addon_path = flavor_dir.join("Interface").join("AddOns");
    if !addon_path.is_dir() {
        return None;
    }
    let wtf_path = flavor_dir.join("WTF");
    let permission = check_permission(&addon_path);
    let is_valid = permission.readable;
    let base_name = root
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "World of Warcraft".to_string());
    let ts = now_ts();

    Some(WowInstallation {
        id: make_id(flavor_dir, &flavor),
        display_name: format!("{} ({})", base_name, flavor_tag(&flavor)),
        root_path: root.to_string_lossy().to_string(),
        flavor,
        addon_path: addon_path.to_string_lossy().to_string(),
        wtf_path: wtf_path.to_string_lossy().to_string(),
        is_valid,
        permission,
        created_at: ts,
        updated_at: ts,
    })
}

fn sort_primary(list: &mut [WowInstallation]) {
    // Retail 优先，其余保持稳定顺序。
    list.sort_by_key(|i| match i.flavor {
        GameFlavor::Retail => 0,
        GameFlavor::Classic => 1,
        GameFlavor::ClassicEra => 2,
        GameFlavor::Ptr => 3,
        GameFlavor::Unknown => 4,
    });
}

/// 从 WoW 根目录解析所有 flavor 安装。
///
/// 支持两种输入：
/// 1. 根目录（含 `_retail_` / `_classic_` 等子目录）——展开为多个安装。
/// 2. 直接的 flavor 游戏目录（含 `Interface/AddOns`）——返回单个安装。
pub fn resolve_installations_from_root(root: &Path) -> AppResult<Vec<WowInstallation>> {
    if !root.exists() {
        return Err(AppError::new(AppErrorCode::InvalidInstallationPath, "目录不存在")
            .with_detail(root.display().to_string())
            .recoverable(true));
    }

    // Case A：root 是 WoW 根，含 flavor 子目录。
    let mut out: Vec<WowInstallation> = Vec::new();
    for (dirname, flavor) in FLAVOR_DIRS {
        let flavor_dir = root.join(dirname);
        if flavor_dir.is_dir() {
            if let Some(inst) = build_installation(root, &flavor_dir, flavor.clone()) {
                out.push(inst);
            }
        }
    }
    if !out.is_empty() {
        sort_primary(&mut out);
        return Ok(out);
    }

    // Case B：root 本身就是 flavor 游戏目录。
    if root.join("Interface").join("AddOns").is_dir() {
        let flavor = match_flavor_by_name(root).unwrap_or(GameFlavor::Unknown);
        let parent = root.parent().unwrap_or(root);
        if let Some(inst) = build_installation(parent, root, flavor) {
            out.push(inst);
        }
    }

    if out.is_empty() {
        Err(invalid_path_error(root))
    } else {
        Ok(out)
    }
}

/// 检查目录的可读/可写权限。
pub fn check_permission(path: &Path) -> PermissionCheckResult {
    if !path.exists() {
        return PermissionCheckResult {
            readable: false,
            writable: false,
            reason: Some("路径不存在".to_string()),
        };
    }

    let readable = if path.is_dir() {
        std::fs::read_dir(path).is_ok()
    } else {
        std::fs::File::open(path).is_ok()
    };

    let writable = if path.is_dir() {
        let probe = path.join(format!(".wam_write_probe_{}", now_ts()));
        match std::fs::File::create(&probe) {
            Ok(_) => {
                let _ = std::fs::remove_file(&probe);
                true
            }
            Err(_) => false,
        }
    } else {
        std::fs::metadata(path)
            .map(|m| !m.permissions().readonly())
            .unwrap_or(false)
    };

    let reason = match (readable, writable) {
        (true, true) => None,
        (true, false) => Some("目录不可写".to_string()),
        (false, _) => Some("目录不可读".to_string()),
    };

    PermissionCheckResult {
        readable,
        writable,
        reason,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn make_flavor(root: &Path, flavor_dir: &str) {
        let d = root.join(flavor_dir);
        fs::create_dir_all(d.join("Interface").join("AddOns")).unwrap();
        fs::create_dir_all(d.join("WTF")).unwrap();
    }

    #[test]
    fn resolves_retail_installation() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        make_flavor(root, "_retail_");

        let list = resolve_installations_from_root(root).unwrap();
        assert_eq!(list.len(), 1);
        let inst = &list[0];
        assert_eq!(inst.flavor, GameFlavor::Retail);
        assert!(inst.is_valid);
        assert!(inst.addon_path.ends_with("_retail_/Interface/AddOns"));
        assert!(inst.wtf_path.ends_with("_retail_/WTF"));
    }

    #[test]
    fn resolves_multiple_flavors_retail_first() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        make_flavor(root, "_classic_");
        make_flavor(root, "_retail_");

        let list = resolve_installations_from_root(root).unwrap();
        assert_eq!(list.len(), 2);
        assert_eq!(list[0].flavor, GameFlavor::Retail);
        assert_ne!(list[0].id, list[1].id);
    }

    #[test]
    fn resolves_when_root_is_flavor_dir() {
        let tmp = tempfile::tempdir().unwrap();
        let flavor_dir = tmp.path().join("_classic_era_");
        fs::create_dir_all(flavor_dir.join("Interface").join("AddOns")).unwrap();

        let list = resolve_installations_from_root(&flavor_dir).unwrap();
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].flavor, GameFlavor::ClassicEra);
    }

    #[test]
    fn nonexistent_path_is_invalid() {
        let err = resolve_installations_from_root(Path::new("/no/such/wow/dir")).unwrap_err();
        assert_eq!(err.code, AppErrorCode::InvalidInstallationPath);
    }

    #[test]
    fn empty_dir_is_invalid() {
        let tmp = tempfile::tempdir().unwrap();
        let err = resolve_installations_from_root(tmp.path()).unwrap_err();
        assert_eq!(err.code, AppErrorCode::InvalidInstallationPath);
    }

    #[test]
    fn permission_reports_readable_writable() {
        let tmp = tempfile::tempdir().unwrap();
        let res = check_permission(tmp.path());
        assert!(res.readable);
        assert!(res.writable);
        assert!(res.reason.is_none());
    }

    #[test]
    fn permission_missing_path() {
        let res = check_permission(Path::new("/no/such/path/xyz"));
        assert!(!res.readable);
        assert!(!res.writable);
        assert_eq!(res.reason.as_deref(), Some("路径不存在"));
    }

    #[cfg(unix)]
    #[test]
    fn permission_readonly_dir_not_writable() {
        use std::os::unix::fs::PermissionsExt;
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path().join("ro");
        fs::create_dir(&dir).unwrap();

        let mut perms = fs::metadata(&dir).unwrap().permissions();
        perms.set_mode(0o500); // r-x------，不可写
        fs::set_permissions(&dir, perms).unwrap();

        let res = check_permission(&dir);
        assert!(!res.writable);

        // 恢复权限以便 tempdir 清理。
        let mut restore = fs::metadata(&dir).unwrap().permissions();
        restore.set_mode(0o700);
        fs::set_permissions(&dir, restore).unwrap();
    }
}
