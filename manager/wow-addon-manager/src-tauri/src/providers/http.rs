//! HTTP 客户端抽象。Provider 只依赖此 trait，便于测试注入 mock。

use std::fs;
use std::io;
use std::path::Path;

use crate::domain::{AppError, AppErrorCode, AppResult};

/// 最小 HTTP 客户端接口：取文本（JSON）与下载到文件。
pub trait HttpClient: Send + Sync {
    /// GET 一个返回文本的资源（通常是 JSON）。
    fn get_text(&self, url: &str) -> AppResult<String>;
    /// GET 并把响应体写入 `dest` 文件。
    fn download_to(&self, url: &str, dest: &Path) -> AppResult<()>;
}

/// 基于 `ureq` 的阻塞式实现。
pub struct UreqHttpClient {
    user_agent: String,
}

impl UreqHttpClient {
    pub fn new() -> Self {
        Self {
            user_agent: "wow-addon-manager".to_string(),
        }
    }
}

impl Default for UreqHttpClient {
    fn default() -> Self {
        Self::new()
    }
}

impl HttpClient for UreqHttpClient {
    fn get_text(&self, url: &str) -> AppResult<String> {
        let resp = ureq::get(url)
            .set("User-Agent", &self.user_agent)
            .call()
            .map_err(map_ureq(url))?;
        resp.into_string().map_err(|e| {
            AppError::new(AppErrorCode::NetworkError, "读取响应内容失败")
                .with_detail(format!("{url}: {e}"))
                .recoverable(true)
        })
    }

    fn download_to(&self, url: &str, dest: &Path) -> AppResult<()> {
        let resp = ureq::get(url)
            .set("User-Agent", &self.user_agent)
            .call()
            .map_err(map_ureq(url))?;

        if let Some(parent) = dest.parent() {
            fs::create_dir_all(parent).map_err(|e| {
                AppError::new(AppErrorCode::ProviderError, "创建下载目录失败")
                    .with_detail(e.to_string())
            })?;
        }
        let mut reader = resp.into_reader();
        let mut file = fs::File::create(dest).map_err(|e| {
            AppError::new(AppErrorCode::ProviderError, "创建下载文件失败")
                .with_detail(format!("{}: {e}", dest.display()))
        })?;
        io::copy(&mut reader, &mut file).map_err(|e| {
            AppError::new(AppErrorCode::NetworkError, "写入下载内容失败")
                .with_detail(format!("{url}: {e}"))
                .recoverable(true)
        })?;
        Ok(())
    }
}

fn map_ureq(url: &str) -> impl Fn(ureq::Error) -> AppError + '_ {
    move |e| {
        let (code, msg) = match &e {
            ureq::Error::Status(status, _) => (
                AppErrorCode::ProviderError,
                format!("请求失败（HTTP {status}）"),
            ),
            ureq::Error::Transport(_) => {
                (AppErrorCode::NetworkError, "网络请求失败".to_string())
            }
        };
        AppError::new(code, msg)
            .with_detail(format!("{url}: {e}"))
            .recoverable(true)
    }
}
