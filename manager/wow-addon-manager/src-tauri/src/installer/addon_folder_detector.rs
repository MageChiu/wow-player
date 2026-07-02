use std::path::{Path, PathBuf};

use crate::domain::{AppError, AppErrorCode, AppResult, DetectedAddonFolder};

/// 在解压后的目录树中识别插件目录（设计规划 §12.3）。
///
/// 策略：递归查找包含 `.toc` 的目录，作为候选插件目录。若候选目录嵌套在
/// `Interface/AddOns` 下，则以 `AddOns` 的直接子目录为准。支持：
/// 1. 平铺多目录：`WeakAuras/`, `WeakAurasOptions/` ...
/// 2. 带版本前缀：`addon-1.0/WeakAuras/` ...
/// 3. `Interface/AddOns` 嵌套。
pub fn detect_addon_folders(root: &Path) -> AppResult<Vec<DetectedAddonFolder>> {
    let mut candidates: Vec<PathBuf> = Vec::new();
    collect_toc_dirs(root, &mut candidates, 0);

    // 若存在 Interface/AddOns 结构，优先只取其直接子目录（裁剪嵌套）。
    if let Some(addons_dir) = find_addons_dir(root) {
        let scoped: Vec<PathBuf> = candidates
            .iter()
            .filter(|p| is_direct_child(&addons_dir, p))
            .cloned()
            .collect();
        if !scoped.is_empty() {
            return Ok(to_detected(dedup(scoped)));
        }
    }

    let deduped = dedup(candidates);
    if deduped.is_empty() {
        return Err(AppError::new(
            AppErrorCode::NoAddonFolderDetected,
            "未在压缩包中识别到插件目录",
        )
        .with_detail(root.display().to_string())
        .recoverable(true));
    }
    Ok(to_detected(deduped))
}

/// 递归查找含 `.toc` 的目录。找到含 `.toc` 的目录后不再深入其子目录。
fn collect_toc_dirs(dir: &Path, out: &mut Vec<PathBuf>, depth: usize) {
    if depth > 8 {
        return;
    }
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    let mut subdirs: Vec<PathBuf> = Vec::new();
    let mut has_toc = false;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            subdirs.push(path);
        } else if path
            .extension()
            .and_then(|e| e.to_str())
            .map(|e| e.eq_ignore_ascii_case("toc"))
            .unwrap_or(false)
        {
            has_toc = true;
        }
    }
    if has_toc {
        out.push(dir.to_path_buf());
        return; // 该目录即为插件目录，不再深入。
    }
    for sub in subdirs {
        collect_toc_dirs(&sub, out, depth + 1);
    }
}

/// 查找解压树中的 `Interface/AddOns` 目录（大小写不敏感）。
fn find_addons_dir(root: &Path) -> Option<PathBuf> {
    fn walk(dir: &Path, depth: usize) -> Option<PathBuf> {
        if depth > 6 {
            return None;
        }
        let entries = std::fs::read_dir(dir).ok()?;
        let mut subdirs = Vec::new();
        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }
            let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
            if name.eq_ignore_ascii_case("AddOns") {
                if let Some(parent) = path.parent() {
                    if parent
                        .file_name()
                        .and_then(|n| n.to_str())
                        .map(|n| n.eq_ignore_ascii_case("Interface"))
                        .unwrap_or(false)
                    {
                        return Some(path);
                    }
                }
            }
            subdirs.push(path);
        }
        for sub in subdirs {
            if let Some(found) = walk(&sub, depth + 1) {
                return Some(found);
            }
        }
        None
    }
    walk(root, 0)
}

fn is_direct_child(parent: &Path, child: &Path) -> bool {
    child.parent().map(|p| p == parent).unwrap_or(false)
}

fn dedup(mut v: Vec<PathBuf>) -> Vec<PathBuf> {
    v.sort();
    v.dedup();
    v
}

fn to_detected(dirs: Vec<PathBuf>) -> Vec<DetectedAddonFolder> {
    dirs.into_iter()
        .map(|p| DetectedAddonFolder {
            folder_name: p
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_default(),
            source_path: p.to_string_lossy().to_string(),
            toc_present: true,
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn touch(path: &Path) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, b"x").unwrap();
    }

    #[test]
    fn detects_flat_multi_folder() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        touch(&root.join("WeakAuras/WeakAuras.toc"));
        touch(&root.join("WeakAurasOptions/WeakAurasOptions.toc"));

        let found = detect_addon_folders(root).unwrap();
        let names: Vec<&str> = found.iter().map(|f| f.folder_name.as_str()).collect();
        assert!(names.contains(&"WeakAuras"));
        assert!(names.contains(&"WeakAurasOptions"));
        assert_eq!(found.len(), 2);
    }

    #[test]
    fn detects_version_prefixed() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        touch(&root.join("addon-1.2.3/WeakAuras/WeakAuras.toc"));

        let found = detect_addon_folders(root).unwrap();
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].folder_name, "WeakAuras");
    }

    #[test]
    fn detects_interface_addons_nested() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        touch(&root.join("pkg/Interface/AddOns/WeakAuras/WeakAuras.toc"));
        touch(&root.join("pkg/Interface/AddOns/Details/Details.toc"));

        let found = detect_addon_folders(root).unwrap();
        let names: Vec<&str> = found.iter().map(|f| f.folder_name.as_str()).collect();
        assert_eq!(found.len(), 2);
        assert!(names.contains(&"WeakAuras"));
        assert!(names.contains(&"Details"));
    }

    #[test]
    fn errors_when_no_toc() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        touch(&root.join("random/readme.txt"));
        let err = detect_addon_folders(root).unwrap_err();
        assert_eq!(err.code, AppErrorCode::NoAddonFolderDetected);
    }
}
