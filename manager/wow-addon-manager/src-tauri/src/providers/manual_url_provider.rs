//! 手动 URL 源：用户直接给出 zip 下载链接。

use std::path::{Path, PathBuf};
use std::sync::Arc;

use crate::domain::{
    AddonFile, AddonProviderKind, AppError, AppErrorCode, AppResult, GameFlavor, RemoteAddon,
};
use crate::providers::http::HttpClient;
use crate::providers::provider::AddonProvider;

pub struct ManualUrlProvider {
    http: Arc<dyn HttpClient>,
}

impl ManualUrlProvider {
    pub fn new(http: Arc<dyn HttpClient>) -> Self {
        Self { http }
    }
}

impl AddonProvider for ManualUrlProvider {
    fn kind(&self) -> AddonProviderKind {
        AddonProviderKind::ManualUrl
    }

    /// URL 源不支持搜索。
    fn search(
        &self,
        _keyword: &str,
        _game_flavor: Option<GameFlavor>,
    ) -> AppResult<Vec<RemoteAddon>> {
        Ok(Vec::new())
    }

    /// `remote_id` 即下载 URL；返回单一文件条目。
    fn get_files(
        &self,
        remote_id: &str,
        game_flavor: Option<GameFlavor>,
    ) -> AppResult<Vec<AddonFile>> {
        if !is_http_url(remote_id) {
            return Err(AppError::new(AppErrorCode::ProviderError, "无效的下载链接")
                .with_detail(remote_id.to_string())
                .recoverable(true));
        }
        Ok(vec![AddonFile {
            provider: AddonProviderKind::ManualUrl,
            remote_id: remote_id.to_string(),
            file_id: remote_id.to_string(),
            file_name: file_name_from_url(remote_id),
            version: None,
            download_url: remote_id.to_string(),
            checksum: None,
            game_flavor: game_flavor.unwrap_or(GameFlavor::Unknown),
            released_at: None,
        }])
    }

    fn download(&self, file: &AddonFile, target_dir: &Path) -> AppResult<PathBuf> {
        if !is_http_url(&file.download_url) {
            return Err(AppError::new(AppErrorCode::ProviderError, "无效的下载链接")
                .with_detail(file.download_url.clone())
                .recoverable(true));
        }
        let dest = target_dir.join(&file.file_name);
        self.http.download_to(&file.download_url, &dest)?;
        Ok(dest)
    }
}

fn is_http_url(url: &str) -> bool {
    url.starts_with("http://") || url.starts_with("https://")
}

/// 从 URL 末段推断文件名，缺省 `addon.zip`。
fn file_name_from_url(url: &str) -> String {
    let trimmed = url.split(['?', '#']).next().unwrap_or(url);
    let last = trimmed.rsplit('/').next().unwrap_or("");
    if last.is_empty() {
        "addon.zip".to_string()
    } else if last.ends_with(".zip") {
        last.to_string()
    } else {
        format!("{last}.zip")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    struct MockHttp {
        downloaded: RefCell<Vec<(String, PathBuf)>>,
    }
    impl HttpClient for MockHttp {
        fn get_text(&self, _url: &str) -> AppResult<String> {
            Ok(String::new())
        }
        fn download_to(&self, url: &str, dest: &Path) -> AppResult<()> {
            std::fs::create_dir_all(dest.parent().unwrap()).unwrap();
            std::fs::write(dest, b"zip").unwrap();
            self.downloaded
                .borrow_mut()
                .push((url.to_string(), dest.to_path_buf()));
            Ok(())
        }
    }
    // MockHttp 仅在单线程测试中使用。
    unsafe impl Send for MockHttp {}
    unsafe impl Sync for MockHttp {}

    #[test]
    fn file_name_inference() {
        assert_eq!(file_name_from_url("https://x.com/a/WeakAuras.zip"), "WeakAuras.zip");
        assert_eq!(file_name_from_url("https://x.com/a/pkg?v=1"), "pkg.zip");
        assert_eq!(file_name_from_url("https://x.com/"), "addon.zip");
    }

    #[test]
    fn get_files_rejects_non_http() {
        let http = Arc::new(MockHttp {
            downloaded: RefCell::new(vec![]),
        });
        let provider = ManualUrlProvider::new(http);
        let err = provider.get_files("ftp://x/a.zip", None).unwrap_err();
        assert_eq!(err.code, AppErrorCode::ProviderError);
    }

    #[test]
    fn download_writes_file() {
        let tmp = tempfile::tempdir().unwrap();
        let http = Arc::new(MockHttp {
            downloaded: RefCell::new(vec![]),
        });
        let provider = ManualUrlProvider::new(http);
        let file = provider
            .get_files("https://x.com/WeakAuras.zip", Some(GameFlavor::Retail))
            .unwrap()
            .remove(0);
        let out = provider.download(&file, tmp.path()).unwrap();
        assert!(out.is_file());
        assert_eq!(out.file_name().unwrap(), "WeakAuras.zip");
    }
}
