use std::path::{Path, PathBuf};

use crate::domain::{AppError, AppErrorCode, AppResult, TocMetadata};

/// 解析 `.toc` 文本内容（设计规划 §11.4）。
///
/// 规则：
/// 1. 只解析以 `##` 开头的元数据行。
/// 2. key 忽略大小写。
/// 3. value 去除首尾空格。
/// 4. 逗号分隔字段拆成数组（去空、去重前后空格）。
pub fn parse_toc_content(content: &str) -> TocMetadata {
    let mut meta = TocMetadata::default();

    for raw_line in content.lines() {
        let line = raw_line.trim_start_matches('\u{feff}').trim();
        let Some(rest) = line.strip_prefix("##") else {
            continue;
        };
        let Some((key, value)) = rest.split_once(':') else {
            continue;
        };
        let key = key.trim().to_lowercase();
        let value = value.trim();
        if value.is_empty() {
            continue;
        }

        match key.as_str() {
            "interface" => meta.interface_version = Some(value.to_string()),
            "title" => meta.title = Some(value.to_string()),
            "version" => meta.version = Some(value.to_string()),
            "author" => meta.author = Some(value.to_string()),
            "notes" => meta.notes = Some(value.to_string()),
            "dependencies" | "requireddeps" => {
                meta.dependencies = split_list(value);
            }
            "optionaldeps" => {
                meta.optional_dependencies = split_list(value);
            }
            "savedvariables" => {
                meta.saved_variables = split_list(value);
            }
            "savedvariablespercharacter" => {
                meta.saved_variables_per_character = split_list(value);
            }
            _ => {}
        }
    }

    meta
}

/// 拆分逗号分隔的列表字段，去除空白项。
fn split_list(value: &str) -> Vec<String> {
    value
        .split(',')
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .collect()
}

/// 读取并解析单个 `.toc` 文件。
pub fn parse_toc_file(path: &Path) -> AppResult<TocMetadata> {
    let content = std::fs::read_to_string(path).map_err(|e| {
        AppError::new(AppErrorCode::TocParseError, "无法读取 .toc 文件")
            .with_detail(format!("{}: {e}", path.display()))
            .recoverable(true)
    })?;
    Ok(parse_toc_content(&content))
}

/// 在插件目录中挑选主 `.toc` 文件（设计规划 §11.4 规则 5/6）。
///
/// 优先返回与目录名相同的 `.toc`（忽略大小写，容忍 `-Classic`/`-Mainline` 等
/// flavor 后缀）；否则返回第一个 `.toc`。目录名以去掉 `.disabled` 后缀为准。
pub fn find_primary_toc(addon_dir: &Path) -> AppResult<PathBuf> {
    let entries = std::fs::read_dir(addon_dir).map_err(|e| {
        AppError::new(AppErrorCode::TocParseError, "无法读取插件目录")
            .with_detail(format!("{}: {e}", addon_dir.display()))
            .recoverable(true)
    })?;

    let mut toc_files: Vec<PathBuf> = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_file()
            && path
                .extension()
                .and_then(|e| e.to_str())
                .map(|e| e.eq_ignore_ascii_case("toc"))
                .unwrap_or(false)
        {
            toc_files.push(path);
        }
    }

    if toc_files.is_empty() {
        return Err(AppError::new(AppErrorCode::TocParseError, "插件目录内无 .toc 文件")
            .with_detail(addon_dir.display().to_string())
            .recoverable(true));
    }

    let dir_name = normalized_dir_name(addon_dir);

    // 完全同名优先。
    if let Some(p) = toc_files.iter().find(|p| {
        p.file_stem()
            .and_then(|s| s.to_str())
            .map(|s| s.eq_ignore_ascii_case(&dir_name))
            .unwrap_or(false)
    }) {
        return Ok(p.clone());
    }

    // 其次：去掉 flavor 后缀（`Name-Classic.toc` 等）后同名。
    if let Some(p) = toc_files.iter().find(|p| {
        p.file_stem()
            .and_then(|s| s.to_str())
            .map(|s| strip_flavor_suffix(s).eq_ignore_ascii_case(&dir_name))
            .unwrap_or(false)
    }) {
        return Ok(p.clone());
    }

    // 兜底：第一个（排序后保证稳定）。
    toc_files.sort();
    Ok(toc_files.into_iter().next().unwrap())
}

/// 目录名去掉 `.disabled` 后缀（若有），用于同名匹配。
pub fn normalized_dir_name(addon_dir: &Path) -> String {
    let name = addon_dir
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_default();
    name.strip_suffix(".disabled").unwrap_or(&name).to_string()
}

fn strip_flavor_suffix(stem: &str) -> &str {
    for suffix in [
        "-Mainline",
        "-Classic",
        "-Vanilla",
        "-BCC",
        "-Wrath",
        "-Cata",
        "_Mainline",
        "_Classic",
    ] {
        if let Some(base) = stem.strip_suffix(suffix) {
            return base;
        }
    }
    stem
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn parses_standard_toc() {
        let content = "\
## Interface: 110002
## Title: WeakAuras
## Version: 5.12.0
## Author: The WeakAuras Team
## Notes: A powerful addon
## Dependencies: Foo, Bar
## OptionalDeps: Baz
## SavedVariables: WeakAurasSaved
## SavedVariablesPerCharacter: WeakAurasPerChar
";
        let meta = parse_toc_content(content);
        assert_eq!(meta.interface_version.as_deref(), Some("110002"));
        assert_eq!(meta.title.as_deref(), Some("WeakAuras"));
        assert_eq!(meta.version.as_deref(), Some("5.12.0"));
        assert_eq!(meta.author.as_deref(), Some("The WeakAuras Team"));
        assert_eq!(meta.dependencies, vec!["Foo", "Bar"]);
        assert_eq!(meta.optional_dependencies, vec!["Baz"]);
        assert_eq!(meta.saved_variables, vec!["WeakAurasSaved"]);
        assert_eq!(meta.saved_variables_per_character, vec!["WeakAurasPerChar"]);
    }

    #[test]
    fn parses_missing_fields() {
        let content = "## Title: Minimal\n";
        let meta = parse_toc_content(content);
        assert_eq!(meta.title.as_deref(), Some("Minimal"));
        assert!(meta.version.is_none());
        assert!(meta.dependencies.is_empty());
    }

    #[test]
    fn key_case_insensitive_and_trims() {
        let content = "##   tItLe :   Spaced Title   \n##VERSION:1.0\n";
        let meta = parse_toc_content(content);
        assert_eq!(meta.title.as_deref(), Some("Spaced Title"));
        assert_eq!(meta.version.as_deref(), Some("1.0"));
    }

    #[test]
    fn handles_chinese_and_bom() {
        let content = "\u{feff}## Title: 强化光环\n## Notes: 中文说明, 第二项\n## Dependencies: 依赖A, 依赖B\n";
        let meta = parse_toc_content(content);
        assert_eq!(meta.title.as_deref(), Some("强化光环"));
        assert_eq!(meta.dependencies, vec!["依赖A", "依赖B"]);
    }

    #[test]
    fn ignores_non_metadata_lines() {
        let content = "# comment\nsome random line\n## Title: X\n";
        let meta = parse_toc_content(content);
        assert_eq!(meta.title.as_deref(), Some("X"));
    }

    #[test]
    fn empty_list_items_filtered() {
        let content = "## Dependencies: Foo, , Bar,\n";
        let meta = parse_toc_content(content);
        assert_eq!(meta.dependencies, vec!["Foo", "Bar"]);
    }

    #[test]
    fn find_primary_prefers_same_name() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path().join("WeakAuras");
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("Other.toc"), "## Title: Other\n").unwrap();
        fs::write(dir.join("WeakAuras.toc"), "## Title: WeakAuras\n").unwrap();

        let primary = find_primary_toc(&dir).unwrap();
        assert_eq!(primary.file_name().unwrap(), "WeakAuras.toc");
    }

    #[test]
    fn find_primary_strips_flavor_suffix() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path().join("Details");
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("Details-Classic.toc"), "## Title: Details\n").unwrap();

        let primary = find_primary_toc(&dir).unwrap();
        assert_eq!(primary.file_name().unwrap(), "Details-Classic.toc");
    }

    #[test]
    fn find_primary_errors_when_no_toc() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path().join("NoToc");
        fs::create_dir_all(&dir).unwrap();
        let err = find_primary_toc(&dir).unwrap_err();
        assert_eq!(err.code, AppErrorCode::TocParseError);
    }

    #[test]
    fn normalized_dir_name_strips_disabled() {
        let p = Path::new("/x/WeakAuras.disabled");
        assert_eq!(normalized_dir_name(p), "WeakAuras");
        let p2 = Path::new("/x/Details");
        assert_eq!(normalized_dir_name(p2), "Details");
    }
}
