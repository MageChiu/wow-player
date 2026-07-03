use std::path::{Path, PathBuf};

use crate::domain::{AppError, AppErrorCode, AppResult};
use crate::platform::adapter::PlatformAdapter;

pub struct WindowsPlatformAdapter;

impl WindowsPlatformAdapter {
    pub fn new() -> Self {
        Self
    }
}

impl Default for WindowsPlatformAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl PlatformAdapter for WindowsPlatformAdapter {
    fn platform_name(&self) -> &'static str {
        "windows"
    }

    fn default_scan_paths(&self) -> Vec<PathBuf> {
        // 设计规划 §10.2。
        [
            r"C:\Program Files (x86)\World of Warcraft",
            r"C:\Program Files\World of Warcraft",
            r"D:\Games\World of Warcraft",
            r"D:\World of Warcraft",
        ]
        .iter()
        .map(PathBuf::from)
        .collect()
    }

    fn app_data_dir(&self) -> AppResult<PathBuf> {
        let base = std::env::var_os("APPDATA")
            .map(PathBuf::from)
            .or_else(|| dirs_home().map(|h| h.join("AppData").join("Roaming")))
            .ok_or_else(|| {
                AppError::new(AppErrorCode::UnsupportedPlatform, "无法定位 APPDATA 目录")
            })?;
        Ok(base.join("wow-addon-manager"))
    }

    fn cache_dir(&self) -> AppResult<PathBuf> {
        let base = std::env::var_os("LOCALAPPDATA")
            .map(PathBuf::from)
            .or_else(|| dirs_home().map(|h| h.join("AppData").join("Local")))
            .ok_or_else(|| {
                AppError::new(AppErrorCode::UnsupportedPlatform, "无法定位 LOCALAPPDATA 目录")
            })?;
        Ok(base.join("wow-addon-manager").join("cache"))
    }

    fn temp_dir(&self) -> AppResult<PathBuf> {
        Ok(std::env::temp_dir().join("wow-addon-manager"))
    }

    fn reveal_in_file_manager(&self, path: &Path) -> AppResult<()> {
        std::process::Command::new("explorer")
            .arg(path)
            .spawn()
            .map(|_| ())
            .map_err(|e| {
                AppError::new(AppErrorCode::Unknown, "无法打开文件管理器")
                    .with_detail(e.to_string())
            })
    }
}

fn dirs_home() -> Option<PathBuf> {
    std::env::var_os("USERPROFILE").map(PathBuf::from)
}
