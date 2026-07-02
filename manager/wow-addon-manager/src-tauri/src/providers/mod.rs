//! Addon providers (A7)。
//!
//! Provider 只负责搜索/取文件/下载，不负责安装（安装属 Installer + 命令层编排）。
//! - `provider`：`AddonProvider` trait。
//! - `provider_service`：注册与分发。
//! - `http`：HTTP 客户端抽象（便于测试注入）。
//! - `local_zip_provider` / `manual_url_provider` / `github_provider`：第一批实现。
//! - Wago / CurseForge 仅保留枚举，不实现。

pub mod github_provider;
pub mod http;
pub mod local_zip_provider;
pub mod manual_url_provider;
pub mod provider;
pub mod provider_service;

pub use github_provider::GitHubReleaseProvider;
pub use http::{HttpClient, UreqHttpClient};
pub use local_zip_provider::LocalZipProvider;
pub use manual_url_provider::ManualUrlProvider;
pub use provider::AddonProvider;
pub use provider_service::ProviderService;
