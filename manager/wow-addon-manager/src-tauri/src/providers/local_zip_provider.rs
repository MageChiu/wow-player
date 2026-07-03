//! 本地 zip 源：把用户选中的本地 zip 作为一个"文件"提供，下载即复制到目标目录。

use std::fs;
use std::path::{Path, PathBuf};

use crate::domain::{
    AddonFile, AddonProviderKind, AppError, AppErrorCode, AppResult, GameFlavor, RemoteAddon,
};
use crate::providers::provider::AddonProvider;

pub struct LocalZipProvider;

impl LocalZipProvider {
    pub fn new() -> Self {
        Self
    }
}

impl Default for LocalZipProvider {
    fn default() -> Self {
        Self::new()
    }
}

impl AddonProvider for LocalZipProvider {
    fn kind(&self) -> AddonProviderKind {
        AddonProviderKind::LocalZip
    }

    /// 本地源不支持在线搜索。
    fn search(
        &self,
        _keyword: &str,
        _game_flavor: Option<GameFlavor>,
    ) -> AppResult<Vec<RemoteAddon>> {
        Ok(Vec::new())
    }

    /// `remote_id` 即本地 zip 的绝对路径；返回单一文件条目。
    fn get_files(
        &self,
        remote_id: &str,
        game_flavor: Option<GameFlavor>,
    ) -> AppResult<Vec<AddonFile>> {
        let path = Path::new(remote_id);
        if !path.is_file() {
            return Err(AppError::new(AppErrorCode::ProviderError, "本地文件不存在")
                .with_detail(remote_id.to_string())
                .recoverable(true));
        }
        let file_name = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("addon.zip")
            .to_string();
        Ok(vec![AddonFile {
            provider: AddonProviderKind::LocalZip,
            remote_id: remote_id.to_string(),
            file_id: remote_id.to_string(),
            file_name,
            version: None,
            download_url: remote_id.to_string(),
            checksum: None,
            game_flavor: game_flavor.unwrap_or(GameFlavor::Unknown),
            released_at: None,
        }])
    }

    /// "下载"本地文件 = 复制到目标目录。
    fn download(&self, file: &AddonFile, target_dir: &Path) -> AppResult<PathBuf> {
        let src = Path::new(&file.download_url);
        if !src.is_file() {
            return Err(AppError::new(AppErrorCode::ProviderError, "本地文件不存在")
                .with_detail(file.download_url.clone())
                .recoverable(true));
        }
        fs::create_dir_all(target_dir).map_err(|e| {
            AppError::new(AppErrorCode::ProviderError, "创建目标目录失败")
                .with_detail(e.to_string())
        })?;
        let dest = target_dir.join(&file.file_name);
        fs::copy(src, &dest).map_err(|e| {
            AppError::new(AppErrorCode::ProviderError, "复制本地文件失败")
                .with_detail(format!("{} -> {}: {e}", src.display(), dest.display()))
        })?;
        Ok(dest)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn get_files_returns_local_entry() {
        let tmp = tempfile::tempdir().unwrap();
        let zip = tmp.path().join("WeakAuras.zip");
        fs::write(&zip, b"PK\x03\x04").unwrap();

        let provider = LocalZipProvider::new();
        let files = provider
            .get_files(zip.to_str().unwrap(), Some(GameFlavor::Retail))
            .unwrap();
        assert_eq!(files.len(), 1);
        assert_eq!(files[0].file_name, "WeakAuras.zip");
        assert_eq!(files[0].game_flavor, GameFlavor::Retail);
    }

    #[test]
    fn get_files_errors_when_missing() {
        let provider = LocalZipProvider::new();
        let err = provider.get_files("/no/such/file.zip", None).unwrap_err();
        assert_eq!(err.code, AppErrorCode::ProviderError);
    }

    #[test]
    fn download_copies_to_target() {
        let tmp = tempfile::tempdir().unwrap();
        let zip = tmp.path().join("A.zip");
        fs::write(&zip, b"data").unwrap();
        let provider = LocalZipProvider::new();
        let file = provider
            .get_files(zip.to_str().unwrap(), None)
            .unwrap()
            .remove(0);

        let target = tmp.path().join("dl");
        let out = provider.download(&file, &target).unwrap();
        assert!(out.is_file());
        assert_eq!(fs::read(&out).unwrap(), b"data");
    }
}
