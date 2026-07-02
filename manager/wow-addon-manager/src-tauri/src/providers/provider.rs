//! Provider 抽象（设计规划 §14.1）。
//!
//! Provider 只负责：搜索、获取文件列表、下载文件。
//! 不负责：解压、判断插件目录、安装、更新数据库、备份、回滚（属 Installer/Service）。

use std::path::{Path, PathBuf};

use crate::domain::{AddonFile, AddonProviderKind, AppResult, GameFlavor, RemoteAddon};

/// 插件源接口。实现方以阻塞方式完成 IO（与全局同步架构一致）。
pub trait AddonProvider: Send + Sync {
    fn kind(&self) -> AddonProviderKind;

    /// 按关键字搜索远程插件。
    fn search(
        &self,
        keyword: &str,
        game_flavor: Option<GameFlavor>,
    ) -> AppResult<Vec<RemoteAddon>>;

    /// 获取某插件的可下载文件列表。
    fn get_files(
        &self,
        remote_id: &str,
        game_flavor: Option<GameFlavor>,
    ) -> AppResult<Vec<AddonFile>>;

    /// 下载指定文件到 `target_dir`，返回下载得到的本地文件路径。
    fn download(&self, file: &AddonFile, target_dir: &Path) -> AppResult<PathBuf>;
}
