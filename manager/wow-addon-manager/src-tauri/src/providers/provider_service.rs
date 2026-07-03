//! Provider 注册与分发（设计规划 §14）。

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use crate::domain::{
    AddonFile, AddonProviderKind, AppError, AppErrorCode, AppResult, GameFlavor, RemoteAddon,
};
use crate::providers::github_provider::GitHubReleaseProvider;
use crate::providers::http::{HttpClient, UreqHttpClient};
use crate::providers::local_zip_provider::LocalZipProvider;
use crate::providers::manual_url_provider::ManualUrlProvider;
use crate::providers::provider::AddonProvider;

/// 持有已注册的 Provider，按 `AddonProviderKind` 分发调用。
pub struct ProviderService {
    providers: HashMap<AddonProviderKind, Arc<dyn AddonProvider>>,
}

impl ProviderService {
    /// 用默认 HTTP 客户端注册第一批 Provider（Local/ManualUrl/GitHub）。
    pub fn with_defaults() -> Self {
        let http: Arc<dyn HttpClient> = Arc::new(UreqHttpClient::new());
        Self::with_http(http)
    }

    /// 注入自定义 HTTP 客户端（便于测试）。
    pub fn with_http(http: Arc<dyn HttpClient>) -> Self {
        let mut providers: HashMap<AddonProviderKind, Arc<dyn AddonProvider>> = HashMap::new();
        providers.insert(AddonProviderKind::LocalZip, Arc::new(LocalZipProvider::new()));
        providers.insert(
            AddonProviderKind::ManualUrl,
            Arc::new(ManualUrlProvider::new(http.clone())),
        );
        providers.insert(
            AddonProviderKind::GithubRelease,
            Arc::new(GitHubReleaseProvider::new(http)),
        );
        Self { providers }
    }

    /// 空注册表（测试用）。
    pub fn empty() -> Self {
        Self {
            providers: HashMap::new(),
        }
    }

    /// 注册（或替换）一个 Provider。
    pub fn register(&mut self, provider: Arc<dyn AddonProvider>) {
        self.providers.insert(provider.kind(), provider);
    }

    fn get(&self, kind: &AddonProviderKind) -> AppResult<&Arc<dyn AddonProvider>> {
        self.providers.get(kind).ok_or_else(|| {
            AppError::new(AppErrorCode::ProviderError, "该插件源暂不支持")
                .with_detail(format!("{kind:?}"))
                .recoverable(true)
        })
    }

    pub fn search(
        &self,
        kind: &AddonProviderKind,
        keyword: &str,
        game_flavor: Option<GameFlavor>,
    ) -> AppResult<Vec<RemoteAddon>> {
        self.get(kind)?.search(keyword, game_flavor)
    }

    pub fn get_files(
        &self,
        kind: &AddonProviderKind,
        remote_id: &str,
        game_flavor: Option<GameFlavor>,
    ) -> AppResult<Vec<AddonFile>> {
        self.get(kind)?.get_files(remote_id, game_flavor)
    }

    pub fn download(
        &self,
        kind: &AddonProviderKind,
        file: &AddonFile,
        target_dir: &Path,
    ) -> AppResult<PathBuf> {
        self.get(kind)?.download(file, target_dir)
    }
}

impl Default for ProviderService {
    fn default() -> Self {
        Self::with_defaults()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::providers::provider::AddonProvider;
    use std::path::PathBuf;

    struct FakeProvider;
    impl AddonProvider for FakeProvider {
        fn kind(&self) -> AddonProviderKind {
            AddonProviderKind::Wago
        }
        fn search(
            &self,
            keyword: &str,
            _flavor: Option<GameFlavor>,
        ) -> AppResult<Vec<RemoteAddon>> {
            Ok(vec![RemoteAddon {
                provider: AddonProviderKind::Wago,
                remote_id: "1".into(),
                title: keyword.to_string(),
                summary: None,
                author: None,
                latest_version: None,
                game_flavors: vec![],
                homepage_url: None,
                source_url: None,
                download_count: None,
                updated_at: None,
            }])
        }
        fn get_files(
            &self,
            _remote_id: &str,
            _flavor: Option<GameFlavor>,
        ) -> AppResult<Vec<AddonFile>> {
            Ok(vec![])
        }
        fn download(&self, _file: &AddonFile, _target: &Path) -> AppResult<PathBuf> {
            Ok(PathBuf::from("/tmp/x.zip"))
        }
    }

    #[test]
    fn dispatches_to_registered_provider() {
        let mut svc = ProviderService::empty();
        svc.register(Arc::new(FakeProvider));
        let results = svc
            .search(&AddonProviderKind::Wago, "hello", None)
            .unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].title, "hello");
    }

    #[test]
    fn unknown_provider_errors() {
        let svc = ProviderService::empty();
        let err = svc
            .search(&AddonProviderKind::CurseForge, "x", None)
            .unwrap_err();
        assert_eq!(err.code, AppErrorCode::ProviderError);
    }

    #[test]
    fn defaults_register_three_providers() {
        let svc = ProviderService::with_defaults();
        assert!(svc.get(&AddonProviderKind::LocalZip).is_ok());
        assert!(svc.get(&AddonProviderKind::ManualUrl).is_ok());
        assert!(svc.get(&AddonProviderKind::GithubRelease).is_ok());
        // 未实现的源不注册。
        assert!(svc.get(&AddonProviderKind::Wago).is_err());
        assert!(svc.get(&AddonProviderKind::CurseForge).is_err());
    }
}
