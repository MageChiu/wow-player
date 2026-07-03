use std::fs;
use std::path::Path;

use crate::domain::{AppError, AppErrorCode, AppResult};

/// 递归复制目录 `src` 到 `dst`（dst 不应已存在）。
pub fn copy_dir_all(src: &Path, dst: &Path) -> AppResult<()> {
    fs::create_dir_all(dst).map_err(map("创建目标目录失败"))?;
    for entry in fs::read_dir(src).map_err(map("读取源目录失败"))? {
        let entry = entry.map_err(map("遍历源目录失败"))?;
        let file_type = entry.file_type().map_err(map("读取文件类型失败"))?;
        let from = entry.path();
        let to = dst.join(entry.file_name());
        if file_type.is_dir() {
            copy_dir_all(&from, &to)?;
        } else {
            fs::copy(&from, &to).map_err(map("复制文件失败"))?;
        }
    }
    Ok(())
}

/// 将 `src` 目录移动到 `dst`。先尝试 rename，跨设备失败则复制+删除。
pub fn move_dir(src: &Path, dst: &Path) -> AppResult<()> {
    if let Some(parent) = dst.parent() {
        fs::create_dir_all(parent).map_err(map("创建目标父目录失败"))?;
    }
    if fs::rename(src, dst).is_ok() {
        return Ok(());
    }
    copy_dir_all(src, dst)?;
    remove_dir(src)?;
    Ok(())
}

/// 删除目录（若存在）。
pub fn remove_dir(path: &Path) -> AppResult<()> {
    if path.exists() {
        fs::remove_dir_all(path).map_err(map("删除目录失败"))?;
    }
    Ok(())
}

fn map(msg: &'static str) -> impl Fn(std::io::Error) -> AppError {
    move |e| AppError::new(AppErrorCode::InstallFailed, msg).with_detail(e.to_string())
}
