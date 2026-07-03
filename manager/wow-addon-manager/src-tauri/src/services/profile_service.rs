use std::path::{Path, PathBuf};

use log::{info, warn};

use crate::domain::{AppError, AppErrorCode, AppResult};

const DISABLED_SUFFIX: &str = ".disabled";

/// 应用 Profile 对插件目录启停的结果。
#[derive(Debug, Default)]
pub struct ToggleOutcome {
    /// 本次被启用（去掉 `.disabled`）的目录归一化名。
    pub enabled: Vec<String>,
    /// 本次被禁用（加上 `.disabled`）的目录归一化名。
    pub disabled: Vec<String>,
}

/// Profile 服务：负责按目标插件集合启停 `AddOns` 下的目录。
///
/// 启停通过目录重命名实现（设计规划 §A6）：
/// - 启用：`Addon.disabled` → `Addon`
/// - 禁用：`Addon` → `Addon.disabled`
///
/// 只重命名、不删除，失败时尽量保持目录完好（已成功的重命名不回退，
/// 但绝不删除任何插件数据）。
pub struct ProfileService;

impl ProfileService {
    /// 将 `AddOns` 目录调整为：`target_folders` 内插件启用、其余禁用。
    /// `target_folders` 为归一化目录名（不含 `.disabled`）。
    pub fn apply_to_addons(
        addon_path: &Path,
        target_folders: &[String],
    ) -> AppResult<ToggleOutcome> {
        if !addon_path.is_dir() {
            return Err(AppError::new(AppErrorCode::AddonPathNotFound, "插件目录不存在")
                .with_detail(addon_path.display().to_string())
                .recoverable(true));
        }

        let target: std::collections::HashSet<&str> =
            target_folders.iter().map(|s| s.as_str()).collect();

        let mut outcome = ToggleOutcome::default();
        for entry in std::fs::read_dir(addon_path).map_err(|e| {
            AppError::new(AppErrorCode::AddonPathNotFound, "无法读取插件目录")
                .with_detail(e.to_string())
        })? {
            let entry = entry.map_err(|e| {
                AppError::new(AppErrorCode::Unknown, "遍历插件目录失败").with_detail(e.to_string())
            })?;
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }
            let name = match path.file_name().and_then(|n| n.to_str()) {
                Some(n) => n.to_string(),
                None => continue,
            };
            if name.starts_with('.') && !name.ends_with(DISABLED_SUFFIX) {
                continue; // 跳过隐藏目录（但 `.disabled` 插件要处理）。
            }

            let is_disabled = name.ends_with(DISABLED_SUFFIX);
            let normalized = name
                .strip_suffix(DISABLED_SUFFIX)
                .unwrap_or(&name)
                .to_string();
            let should_enable = target.contains(normalized.as_str());

            if should_enable && is_disabled {
                let dest = addon_path.join(&normalized);
                rename(&path, &dest)?;
                outcome.enabled.push(normalized);
            } else if !should_enable && !is_disabled {
                let dest = addon_path.join(format!("{normalized}{DISABLED_SUFFIX}"));
                rename(&path, &dest)?;
                outcome.disabled.push(normalized);
            }
        }

        outcome.enabled.sort();
        outcome.disabled.sort();
        info!(
            "profile applied: {} enabled, {} disabled",
            outcome.enabled.len(),
            outcome.disabled.len()
        );
        Ok(outcome)
    }
}

fn rename(from: &Path, to: &Path) -> AppResult<()> {
    if to.exists() {
        // 目标已存在（例如同时存在启用/禁用两份），保守跳过并告警，不破坏数据。
        warn!(
            "skip rename: target already exists {} (from {})",
            to.display(),
            from.display()
        );
        return Ok(());
    }
    std::fs::rename(from, to).map_err(|e| {
        AppError::new(AppErrorCode::Unknown, "插件目录重命名失败")
            .with_detail(format!("{} -> {}: {e}", from.display(), to.display()))
            .recoverable(true)
    })
}

/// 便于命令层生成禁用目录名。
pub fn disabled_name(normalized: &str) -> String {
    format!("{normalized}{DISABLED_SUFFIX}")
}

/// 返回归一化名（去掉 `.disabled`）。
pub fn normalized_name(folder_name: &str) -> String {
    folder_name
        .strip_suffix(DISABLED_SUFFIX)
        .unwrap_or(folder_name)
        .to_string()
}

/// 便于测试/命令层构造目标目录路径（未使用时避免告警）。
pub fn target_path(addon_path: &Path, normalized: &str) -> PathBuf {
    addon_path.join(normalized)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn mk_addon(addons: &Path, folder: &str) {
        let dir = addons.join(folder);
        fs::create_dir_all(&dir).unwrap();
        let toc = format!("{}.toc", normalized_name(folder));
        fs::write(dir.join(toc), "## Title: X\n").unwrap();
    }

    #[test]
    fn enables_in_profile_disables_out_of_profile() {
        let tmp = tempfile::tempdir().unwrap();
        let addons = tmp.path().join("AddOns");
        fs::create_dir_all(&addons).unwrap();
        mk_addon(&addons, "WeakAuras"); // 已启用，profile 内 → 保持
        mk_addon(&addons, "Details"); // 已启用，profile 外 → 禁用
        mk_addon(&addons, "BigWigs.disabled"); // 已禁用，profile 内 → 启用

        let out = ProfileService::apply_to_addons(
            &addons,
            &["WeakAuras".to_string(), "BigWigs".to_string()],
        )
        .unwrap();

        assert!(addons.join("WeakAuras").is_dir());
        assert!(addons.join("Details.disabled").is_dir());
        assert!(addons.join("BigWigs").is_dir());
        assert!(!addons.join("BigWigs.disabled").exists());
        assert_eq!(out.enabled, vec!["BigWigs"]);
        assert_eq!(out.disabled, vec!["Details"]);
    }

    #[test]
    fn idempotent_when_already_in_target_state() {
        let tmp = tempfile::tempdir().unwrap();
        let addons = tmp.path().join("AddOns");
        fs::create_dir_all(&addons).unwrap();
        mk_addon(&addons, "WeakAuras");

        let out =
            ProfileService::apply_to_addons(&addons, &["WeakAuras".to_string()]).unwrap();
        assert!(out.enabled.is_empty());
        assert!(out.disabled.is_empty());
        assert!(addons.join("WeakAuras").is_dir());
    }

    #[test]
    fn empty_profile_disables_all() {
        let tmp = tempfile::tempdir().unwrap();
        let addons = tmp.path().join("AddOns");
        fs::create_dir_all(&addons).unwrap();
        mk_addon(&addons, "WeakAuras");
        mk_addon(&addons, "Details");

        let out = ProfileService::apply_to_addons(&addons, &[]).unwrap();
        assert_eq!(out.disabled, vec!["Details", "WeakAuras"]);
        assert!(addons.join("WeakAuras.disabled").is_dir());
        assert!(addons.join("Details.disabled").is_dir());
    }

    #[test]
    fn errors_when_addon_path_missing() {
        let err = ProfileService::apply_to_addons(Path::new("/no/such/addons"), &[]).unwrap_err();
        assert_eq!(err.code, AppErrorCode::AddonPathNotFound);
    }

    #[test]
    fn skips_hidden_dirs() {
        let tmp = tempfile::tempdir().unwrap();
        let addons = tmp.path().join("AddOns");
        fs::create_dir_all(addons.join(".git")).unwrap();
        mk_addon(&addons, "WeakAuras");

        let out = ProfileService::apply_to_addons(&addons, &[]).unwrap();
        // .git 不应被处理。
        assert!(addons.join(".git").is_dir());
        assert_eq!(out.disabled, vec!["WeakAuras"]);
    }
}
