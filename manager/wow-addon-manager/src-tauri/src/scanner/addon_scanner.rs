use std::path::Path;

use log::warn;

use crate::domain::{AddonStatus, AppError, AppErrorCode, AppResult, LocalAddon, TocMetadata};
use crate::platform::adapter::now_ts;
use crate::scanner::toc_parser::{find_primary_toc, normalized_dir_name, parse_toc_file};

/// 扫描一个 `Interface/AddOns` 目录，返回全部插件。
///
/// - 目录名以 `.disabled` 结尾 → 状态 `Disabled`。
/// - 目录内无 `.toc` 或解析失败 → 状态 `Broken`，不中断整体扫描。
/// - 单个插件失败不影响其它插件（设计规划 §11.4 规则 7）。
pub fn scan_addons(installation_id: &str, addon_path: &Path) -> AppResult<Vec<LocalAddon>> {
    if !addon_path.is_dir() {
        return Err(AppError::new(
            AppErrorCode::AddonPathNotFound,
            "插件目录不存在",
        )
        .with_detail(addon_path.display().to_string())
        .recoverable(true));
    }

    let entries = std::fs::read_dir(addon_path).map_err(|e| {
        AppError::new(AppErrorCode::AddonPathNotFound, "无法读取插件目录")
            .with_detail(format!("{}: {e}", addon_path.display()))
    })?;

    let mut addons: Vec<LocalAddon> = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let folder_name = match path.file_name().and_then(|n| n.to_str()) {
            Some(n) => n.to_string(),
            None => continue,
        };
        // 跳过隐藏目录（如 .git、.DS_Store 目录等）。
        if folder_name.starts_with('.') {
            continue;
        }

        addons.push(build_addon(installation_id, &path, &folder_name));
    }

    addons.sort_by(|a, b| a.normalized_folder_name.cmp(&b.normalized_folder_name));
    Ok(addons)
}

fn build_addon(installation_id: &str, dir: &Path, folder_name: &str) -> LocalAddon {
    let disabled = folder_name.ends_with(".disabled");
    let normalized = normalized_dir_name(dir);
    let ts = now_ts();

    let (meta, status) = match load_metadata(dir) {
        Ok(meta) => {
            let status = if disabled {
                AddonStatus::Disabled
            } else {
                AddonStatus::Installed
            };
            (meta, status)
        }
        Err(e) => {
            warn!("addon '{folder_name}' marked broken: {e}");
            (TocMetadata::default(), AddonStatus::Broken)
        }
    };

    LocalAddon {
        id: format!("addon_{installation_id}_{}", normalize_id(&normalized)),
        installation_id: installation_id.to_string(),
        folder_name: folder_name.to_string(),
        normalized_folder_name: normalized,
        title: meta.title,
        version: meta.version,
        author: meta.author,
        interface_version: meta.interface_version,
        notes: meta.notes,
        dependencies: meta.dependencies,
        optional_dependencies: meta.optional_dependencies,
        saved_variables: meta.saved_variables,
        saved_variables_per_character: meta.saved_variables_per_character,
        provider: None,
        remote_id: None,
        source_url: None,
        status,
        installed_at: ts,
        updated_at: ts,
    }
}

fn load_metadata(dir: &Path) -> AppResult<TocMetadata> {
    let toc = find_primary_toc(dir)?;
    parse_toc_file(&toc)
}

/// 归一化用于 id 的名称（小写）。
fn normalize_id(name: &str) -> String {
    name.to_lowercase()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn write_addon(addons: &Path, folder: &str, toc_name: &str, body: &str) {
        let dir = addons.join(folder);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join(toc_name), body).unwrap();
    }

    #[test]
    fn scans_standard_addon() {
        let tmp = tempfile::tempdir().unwrap();
        let addons = tmp.path().join("AddOns");
        fs::create_dir_all(&addons).unwrap();
        write_addon(
            &addons,
            "WeakAuras",
            "WeakAuras.toc",
            "## Title: WeakAuras\n## Version: 5.12.0\n",
        );

        let result = scan_addons("inst1", &addons).unwrap();
        assert_eq!(result.len(), 1);
        let a = &result[0];
        assert_eq!(a.folder_name, "WeakAuras");
        assert_eq!(a.normalized_folder_name, "WeakAuras");
        assert_eq!(a.title.as_deref(), Some("WeakAuras"));
        assert_eq!(a.status, AddonStatus::Installed);
        assert_eq!(a.installation_id, "inst1");
    }

    #[test]
    fn marks_disabled_addon() {
        let tmp = tempfile::tempdir().unwrap();
        let addons = tmp.path().join("AddOns");
        fs::create_dir_all(&addons).unwrap();
        write_addon(
            &addons,
            "Details.disabled",
            "Details.toc",
            "## Title: Details\n",
        );

        let result = scan_addons("inst1", &addons).unwrap();
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].status, AddonStatus::Disabled);
        assert_eq!(result[0].normalized_folder_name, "Details");
        assert_eq!(result[0].folder_name, "Details.disabled");
    }

    #[test]
    fn marks_broken_when_no_toc() {
        let tmp = tempfile::tempdir().unwrap();
        let addons = tmp.path().join("AddOns");
        fs::create_dir_all(addons.join("NoToc")).unwrap();

        let result = scan_addons("inst1", &addons).unwrap();
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].status, AddonStatus::Broken);
    }

    #[test]
    fn broken_addon_does_not_stop_scan() {
        let tmp = tempfile::tempdir().unwrap();
        let addons = tmp.path().join("AddOns");
        fs::create_dir_all(&addons).unwrap();
        fs::create_dir_all(addons.join("BrokenOne")).unwrap();
        write_addon(&addons, "GoodOne", "GoodOne.toc", "## Title: Good\n");

        let result = scan_addons("inst1", &addons).unwrap();
        assert_eq!(result.len(), 2);
        let good = result.iter().find(|a| a.folder_name == "GoodOne").unwrap();
        let broken = result.iter().find(|a| a.folder_name == "BrokenOne").unwrap();
        assert_eq!(good.status, AddonStatus::Installed);
        assert_eq!(broken.status, AddonStatus::Broken);
    }

    #[test]
    fn handles_chinese_folder_and_spaces() {
        let tmp = tempfile::tempdir().unwrap();
        let addons = tmp.path().join("AddOns");
        fs::create_dir_all(&addons).unwrap();
        write_addon(&addons, "大脚插件", "大脚插件.toc", "## Title: 大脚\n");

        let result = scan_addons("inst1", &addons).unwrap();
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].title.as_deref(), Some("大脚"));
    }

    #[test]
    fn errors_when_addon_path_missing() {
        let err = scan_addons("inst1", Path::new("/no/such/addons")).unwrap_err();
        assert_eq!(err.code, AppErrorCode::AddonPathNotFound);
    }

    #[test]
    fn skips_files_and_hidden_dirs() {
        let tmp = tempfile::tempdir().unwrap();
        let addons = tmp.path().join("AddOns");
        fs::create_dir_all(&addons).unwrap();
        fs::write(addons.join("loose_file.txt"), "x").unwrap();
        fs::create_dir_all(addons.join(".hidden")).unwrap();
        write_addon(&addons, "Real", "Real.toc", "## Title: Real\n");

        let result = scan_addons("inst1", &addons).unwrap();
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].folder_name, "Real");
    }
}
