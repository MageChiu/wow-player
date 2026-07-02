//! GitHub Release 源：把 GitHub 仓库作为插件来源，release 的 zip asset 作为可安装文件。
//!
//! - `remote_id` 形如 `owner/repo`。
//! - 搜索走 GitHub Search API，文件列表走 Releases API。
//! - 解析逻辑独立成纯函数，便于用本地 fixture JSON 做单测。

use std::path::{Path, PathBuf};
use std::sync::Arc;

use serde::Deserialize;

use crate::domain::{
    AddonFile, AddonProviderKind, AppError, AppErrorCode, AppResult, GameFlavor, RemoteAddon,
};
use crate::providers::http::HttpClient;
use crate::providers::provider::AddonProvider;

const API_BASE: &str = "https://api.github.com";

pub struct GitHubReleaseProvider {
    http: Arc<dyn HttpClient>,
    api_base: String,
}

impl GitHubReleaseProvider {
    pub fn new(http: Arc<dyn HttpClient>) -> Self {
        Self {
            http,
            api_base: API_BASE.to_string(),
        }
    }

    /// 测试用：覆盖 API base（指向本地 mock）。
    #[cfg(test)]
    pub fn with_base(http: Arc<dyn HttpClient>, api_base: impl Into<String>) -> Self {
        Self {
            http,
            api_base: api_base.into(),
        }
    }
}

impl AddonProvider for GitHubReleaseProvider {
    fn kind(&self) -> AddonProviderKind {
        AddonProviderKind::GithubRelease
    }

    fn search(
        &self,
        keyword: &str,
        _game_flavor: Option<GameFlavor>,
    ) -> AppResult<Vec<RemoteAddon>> {
        if keyword.trim().is_empty() {
            return Ok(Vec::new());
        }
        let url = format!(
            "{}/search/repositories?q={}",
            self.api_base,
            urlencode(keyword)
        );
        let body = self.http.get_text(&url)?;
        parse_search(&body)
    }

    fn get_files(
        &self,
        remote_id: &str,
        game_flavor: Option<GameFlavor>,
    ) -> AppResult<Vec<AddonFile>> {
        if !is_owner_repo(remote_id) {
            return Err(AppError::new(
                AppErrorCode::ProviderError,
                "无效的 GitHub 仓库标识（应为 owner/repo）",
            )
            .with_detail(remote_id.to_string())
            .recoverable(true));
        }
        let url = format!("{}/repos/{}/releases", self.api_base, remote_id);
        let body = self.http.get_text(&url)?;
        parse_releases(remote_id, &body, game_flavor.unwrap_or(GameFlavor::Unknown))
    }

    fn download(&self, file: &AddonFile, target_dir: &Path) -> AppResult<PathBuf> {
        let dest = target_dir.join(&file.file_name);
        self.http.download_to(&file.download_url, &dest)?;
        Ok(dest)
    }
}

// ---- GitHub API DTO ----

#[derive(Debug, Deserialize)]
struct SearchResponse {
    #[serde(default)]
    items: Vec<RepoItem>,
}

#[derive(Debug, Deserialize)]
struct RepoItem {
    full_name: String,
    #[serde(default)]
    description: Option<String>,
    #[serde(default)]
    owner: Option<Owner>,
    #[serde(default)]
    html_url: Option<String>,
    #[serde(default)]
    stargazers_count: Option<i64>,
}

#[derive(Debug, Deserialize)]
struct Owner {
    #[serde(default)]
    login: Option<String>,
}

#[derive(Debug, Deserialize)]
struct ReleaseItem {
    #[serde(default)]
    tag_name: Option<String>,
    #[serde(default)]
    assets: Vec<AssetItem>,
    #[serde(default)]
    published_at: Option<String>,
}

#[derive(Debug, Deserialize)]
struct AssetItem {
    id: i64,
    name: String,
    browser_download_url: String,
}

// ---- 纯解析函数（可单测）----

fn parse_search(body: &str) -> AppResult<Vec<RemoteAddon>> {
    let resp: SearchResponse = serde_json::from_str(body).map_err(map_parse("解析搜索结果失败"))?;
    Ok(resp
        .items
        .into_iter()
        .map(|item| RemoteAddon {
            provider: AddonProviderKind::GithubRelease,
            remote_id: item.full_name.clone(),
            title: item.full_name,
            summary: item.description,
            author: item.owner.and_then(|o| o.login),
            latest_version: None,
            game_flavors: Vec::new(),
            homepage_url: item.html_url.clone(),
            source_url: item.html_url,
            download_count: item.stargazers_count,
            updated_at: None,
        })
        .collect())
}

fn parse_releases(
    remote_id: &str,
    body: &str,
    game_flavor: GameFlavor,
) -> AppResult<Vec<AddonFile>> {
    let releases: Vec<ReleaseItem> =
        serde_json::from_str(body).map_err(map_parse("解析 release 列表失败"))?;

    let mut files = Vec::new();
    for rel in releases {
        let version = rel.tag_name.clone();
        let released_at = rel.published_at.as_deref().and_then(parse_iso8601);
        for asset in rel.assets {
            if !asset.name.to_lowercase().ends_with(".zip") {
                continue; // 只取 zip asset。
            }
            files.push(AddonFile {
                provider: AddonProviderKind::GithubRelease,
                remote_id: remote_id.to_string(),
                file_id: asset.id.to_string(),
                file_name: asset.name,
                version: version.clone(),
                download_url: asset.browser_download_url,
                checksum: None,
                game_flavor: game_flavor.clone(),
                released_at,
            });
        }
    }
    Ok(files)
}

fn is_owner_repo(id: &str) -> bool {
    let mut parts = id.split('/');
    match (parts.next(), parts.next(), parts.next()) {
        (Some(a), Some(b), None) => !a.is_empty() && !b.is_empty(),
        _ => false,
    }
}

/// 最小 URL 编码：仅编码查询里常见的空格与保留字符。
fn urlencode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char)
            }
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

/// 解析形如 `2024-01-02T03:04:05Z` 的时间为 Unix 秒（无第三方依赖的粗略实现）。
fn parse_iso8601(s: &str) -> Option<i64> {
    let bytes = s.as_bytes();
    if bytes.len() < 20 || bytes[4] != b'-' || bytes[10] != b'T' {
        return None;
    }
    let year: i64 = s.get(0..4)?.parse().ok()?;
    let month: i64 = s.get(5..7)?.parse().ok()?;
    let day: i64 = s.get(8..10)?.parse().ok()?;
    let hour: i64 = s.get(11..13)?.parse().ok()?;
    let min: i64 = s.get(14..16)?.parse().ok()?;
    let sec: i64 = s.get(17..19)?.parse().ok()?;

    // days_from_civil（Howard Hinnant 算法）。
    let y = if month <= 2 { year - 1 } else { year };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let doy = (153 * (if month > 2 { month - 3 } else { month + 9 }) + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146097 + doe - 719468;
    Some(days * 86400 + hour * 3600 + min * 60 + sec)
}

fn map_parse(msg: &'static str) -> impl Fn(serde_json::Error) -> AppError {
    move |e| {
        AppError::new(AppErrorCode::ProviderError, msg)
            .with_detail(e.to_string())
            .recoverable(true)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    struct StubHttp {
        text: String,
        last_download: RefCell<Option<(String, PathBuf)>>,
    }
    impl HttpClient for StubHttp {
        fn get_text(&self, _url: &str) -> AppResult<String> {
            Ok(self.text.clone())
        }
        fn download_to(&self, url: &str, dest: &Path) -> AppResult<()> {
            std::fs::create_dir_all(dest.parent().unwrap()).unwrap();
            std::fs::write(dest, b"zip").unwrap();
            *self.last_download.borrow_mut() = Some((url.to_string(), dest.to_path_buf()));
            Ok(())
        }
    }
    unsafe impl Send for StubHttp {}
    unsafe impl Sync for StubHttp {}

    const SEARCH_JSON: &str = r#"{
      "total_count": 1,
      "items": [
        {
          "full_name": "WeakAuras/WeakAuras2",
          "description": "A powerful addon",
          "owner": { "login": "WeakAuras" },
          "html_url": "https://github.com/WeakAuras/WeakAuras2",
          "stargazers_count": 1234
        }
      ]
    }"#;

    const RELEASES_JSON: &str = r#"[
      {
        "tag_name": "v5.12.0",
        "published_at": "2024-01-02T03:04:05Z",
        "assets": [
          { "id": 1, "name": "WeakAuras-5.12.0.zip", "browser_download_url": "https://gh/dl/wa.zip" },
          { "id": 2, "name": "changelog.txt", "browser_download_url": "https://gh/dl/changelog.txt" }
        ]
      }
    ]"#;

    #[test]
    fn parse_search_maps_items() {
        let out = parse_search(SEARCH_JSON).unwrap();
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].remote_id, "WeakAuras/WeakAuras2");
        assert_eq!(out[0].author.as_deref(), Some("WeakAuras"));
        assert_eq!(out[0].download_count, Some(1234));
    }

    #[test]
    fn parse_releases_keeps_only_zip_assets() {
        let out = parse_releases("WeakAuras/WeakAuras2", RELEASES_JSON, GameFlavor::Retail).unwrap();
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].file_name, "WeakAuras-5.12.0.zip");
        assert_eq!(out[0].version.as_deref(), Some("v5.12.0"));
        assert_eq!(out[0].download_url, "https://gh/dl/wa.zip");
        assert!(out[0].released_at.is_some());
    }

    #[test]
    fn iso8601_parses_epoch() {
        // 1970-01-01T00:00:00Z == 0
        assert_eq!(parse_iso8601("1970-01-01T00:00:00Z"), Some(0));
        // 2024-01-02T03:04:05Z
        assert_eq!(parse_iso8601("2024-01-02T03:04:05Z"), Some(1704164645));
    }

    #[test]
    fn get_files_rejects_bad_remote_id() {
        let http = Arc::new(StubHttp {
            text: RELEASES_JSON.to_string(),
            last_download: RefCell::new(None),
        });
        let provider = GitHubReleaseProvider::new(http);
        let err = provider.get_files("not-a-repo", None).unwrap_err();
        assert_eq!(err.code, AppErrorCode::ProviderError);
    }

    #[test]
    fn search_and_get_files_via_stub_http() {
        let http = Arc::new(StubHttp {
            text: SEARCH_JSON.to_string(),
            last_download: RefCell::new(None),
        });
        let provider = GitHubReleaseProvider::with_base(http, "http://mock");
        let results = provider.search("weakauras", None).unwrap();
        assert_eq!(results.len(), 1);
    }

    #[test]
    fn download_delegates_to_http() {
        let tmp = tempfile::tempdir().unwrap();
        let http = Arc::new(StubHttp {
            text: RELEASES_JSON.to_string(),
            last_download: RefCell::new(None),
        });
        let provider = GitHubReleaseProvider::new(http.clone());
        let file = provider
            .get_files("WeakAuras/WeakAuras2", Some(GameFlavor::Retail))
            .unwrap()
            .remove(0);
        let out = provider.download(&file, tmp.path()).unwrap();
        assert!(out.is_file());
        assert_eq!(out.file_name().unwrap(), "WeakAuras-5.12.0.zip");
    }
}
