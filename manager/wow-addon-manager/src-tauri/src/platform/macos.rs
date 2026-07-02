use std::path::{Path, PathBuf};

use crate::domain::{AppError, AppErrorCode, AppResult};
use crate::platform::adapter::PlatformAdapter;

pub struct MacPlatformAdapter;

impl MacPlatformAdapter {
    pub fn new() -> Self {
        Self
    }
}

impl Default for MacPlatformAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl PlatformAdapter for MacPlatformAdapter {
    fn platform_name(&self) -> &'static str {
        "macos"
    }

    fn default_scan_paths(&self) -> Vec<PathBuf> {
        // 设计规划 §10.3。
        let mut paths = vec![PathBuf::from("/Applications/World of Warcraft")];
        if let Some(home) = home_dir() {
            paths.push(home.join("Applications").join("World of Warcraft"));
        }
        paths
    }

    fn app_data_dir(&self) -> AppResult<PathBuf> {
        let home = home_dir().ok_or_else(missing_home)?;
        Ok(home
            .join("Library")
            .join("Application Support")
            .join("wow-addon-manager"))
    }

    fn cache_dir(&self) -> AppResult<PathBuf> {
        let home = home_dir().ok_or_else(missing_home)?;
        Ok(home
            .join("Library")
            .join("Caches")
            .join("wow-addon-manager"))
    }

    fn temp_dir(&self) -> AppResult<PathBuf> {
        Ok(std::env::temp_dir().join("wow-addon-manager"))
    }

    fn reveal_in_file_manager(&self, path: &Path) -> AppResult<()> {
        std::process::Command::new("open")
            .arg(path)
            .spawn()
            .map(|_| ())
            .map_err(|e| {
                AppError::new(AppErrorCode::Unknown, "无法打开访达")
                    .with_detail(e.to_string())
            })
    }
}

fn home_dir() -> Option<PathBuf> {
    std::env::var_os("HOME").map(PathBuf::from)
}

fn missing_home() -> AppError {
    AppError::new(AppErrorCode::UnsupportedPlatform, "无法定位用户主目录")
}
