use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use crate::domain::{AppError, AppErrorCode, AppResult};

/// zip 解压/校验服务。
pub struct ZipService;

impl ZipService {
    /// 校验文件是可读的合法 zip。
    pub fn validate(zip_path: &Path) -> AppResult<()> {
        let file = fs::File::open(zip_path).map_err(|e| {
            AppError::new(AppErrorCode::InvalidZipFile, "无法打开压缩包")
                .with_detail(format!("{}: {e}", zip_path.display()))
                .recoverable(true)
        })?;
        zip::ZipArchive::new(file).map_err(|e| {
            AppError::new(AppErrorCode::InvalidZipFile, "压缩包无效")
                .with_detail(e.to_string())
                .recoverable(true)
        })?;
        Ok(())
    }

    /// 解压到目标目录，防止 zip-slip（条目路径逃逸目标目录）。
    pub fn extract(zip_path: &Path, dest_dir: &Path) -> AppResult<()> {
        let file = fs::File::open(zip_path).map_err(|e| {
            AppError::new(AppErrorCode::InvalidZipFile, "无法打开压缩包")
                .with_detail(format!("{}: {e}", zip_path.display()))
                .recoverable(true)
        })?;
        let mut archive = zip::ZipArchive::new(file).map_err(|e| {
            AppError::new(AppErrorCode::InvalidZipFile, "压缩包无效")
                .with_detail(e.to_string())
                .recoverable(true)
        })?;

        fs::create_dir_all(dest_dir).map_err(|e| {
            AppError::new(AppErrorCode::InstallFailed, "无法创建解压目录")
                .with_detail(e.to_string())
        })?;

        for i in 0..archive.len() {
            let mut entry = archive.by_index(i).map_err(|e| {
                AppError::new(AppErrorCode::InvalidZipFile, "读取压缩包条目失败")
                    .with_detail(e.to_string())
            })?;

            let Some(rel) = entry.enclosed_name() else {
                return Err(AppError::new(
                    AppErrorCode::InvalidZipFile,
                    "压缩包包含非法路径",
                )
                .with_detail(entry.name().to_string()));
            };
            let out_path = safe_join(dest_dir, &rel)?;

            if entry.is_dir() {
                fs::create_dir_all(&out_path).map_err(map_io("创建目录失败"))?;
            } else {
                if let Some(parent) = out_path.parent() {
                    fs::create_dir_all(parent).map_err(map_io("创建父目录失败"))?;
                }
                let mut out = fs::File::create(&out_path).map_err(map_io("写入文件失败"))?;
                io::copy(&mut entry, &mut out).map_err(map_io("解压文件失败"))?;
            }
        }
        Ok(())
    }

    /// 将整个目录压缩为 zip，返回写入的字节数。
    /// zip 内路径相对于 `src_dir`（不含 src_dir 自身名称）。
    pub fn compress_dir(src_dir: &Path, zip_path: &Path) -> AppResult<u64> {
        if !src_dir.is_dir() {
            return Err(AppError::new(AppErrorCode::SnapshotCreateFailed, "源目录不存在")
                .with_detail(src_dir.display().to_string()));
        }
        if let Some(parent) = zip_path.parent() {
            fs::create_dir_all(parent).map_err(map_snapshot("创建快照目录失败"))?;
        }
        let file = fs::File::create(zip_path).map_err(map_snapshot("创建快照文件失败"))?;
        let mut writer = zip::ZipWriter::new(file);
        let opts: zip::write::FileOptions<'_, ()> =
            zip::write::FileOptions::default().compression_method(zip::CompressionMethod::Deflated);

        add_dir_to_zip(&mut writer, src_dir, src_dir, &opts)?;
        writer
            .finish()
            .map_err(|e| AppError::new(AppErrorCode::SnapshotCreateFailed, "完成快照压缩失败").with_detail(e.to_string()))?;

        let size = fs::metadata(zip_path).map(|m| m.len()).unwrap_or(0);
        Ok(size)
    }
}

/// 递归把 `dir` 下的条目写入 zip，路径相对 `base`。
fn add_dir_to_zip(
    writer: &mut zip::ZipWriter<fs::File>,
    base: &Path,
    dir: &Path,
    opts: &zip::write::FileOptions<'_, ()>,
) -> AppResult<()> {
    for entry in fs::read_dir(dir).map_err(map_snapshot("读取目录失败"))? {
        let entry = entry.map_err(map_snapshot("遍历目录失败"))?;
        let path = entry.path();
        let rel = path
            .strip_prefix(base)
            .map_err(|e| AppError::new(AppErrorCode::SnapshotCreateFailed, "计算相对路径失败").with_detail(e.to_string()))?;
        let rel_str = rel.to_string_lossy().replace('\\', "/");

        if path.is_dir() {
            writer
                .add_directory(&rel_str, *opts)
                .map_err(|e| AppError::new(AppErrorCode::SnapshotCreateFailed, "写入目录条目失败").with_detail(e.to_string()))?;
            add_dir_to_zip(writer, base, &path, opts)?;
        } else {
            writer
                .start_file(&rel_str, *opts)
                .map_err(|e| AppError::new(AppErrorCode::SnapshotCreateFailed, "写入文件条目失败").with_detail(e.to_string()))?;
            let mut f = fs::File::open(&path).map_err(map_snapshot("打开文件失败"))?;
            io::copy(&mut f, writer).map_err(map_snapshot("写入文件内容失败"))?;
        }
    }
    Ok(())
}

/// 将相对路径安全拼接到 base 下，拒绝逃逸。
fn safe_join(base: &Path, rel: &Path) -> AppResult<PathBuf> {
    let joined = base.join(rel);
    // 逐段校验，不含 `..` 且规范化后仍在 base 内。
    if rel.components().any(|c| matches!(c, std::path::Component::ParentDir)) {
        return Err(AppError::new(
            AppErrorCode::InvalidZipFile,
            "压缩包路径试图逃逸目标目录",
        )
        .with_detail(rel.display().to_string()));
    }
    Ok(joined)
}

fn map_io(msg: &'static str) -> impl Fn(io::Error) -> AppError {
    move |e| AppError::new(AppErrorCode::InstallFailed, msg).with_detail(e.to_string())
}

fn map_snapshot(msg: &'static str) -> impl Fn(io::Error) -> AppError {
    move |e| AppError::new(AppErrorCode::SnapshotCreateFailed, msg).with_detail(e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::installer::test_support::make_zip;

    #[test]
    fn validate_accepts_valid_zip() {
        let tmp = tempfile::tempdir().unwrap();
        let zip_path = tmp.path().join("a.zip");
        make_zip(&zip_path, &[("WeakAuras/WeakAuras.toc", b"## Title: WA\n")]);
        assert!(ZipService::validate(&zip_path).is_ok());
    }

    #[test]
    fn validate_rejects_non_zip() {
        let tmp = tempfile::tempdir().unwrap();
        let bad = tmp.path().join("bad.zip");
        fs::write(&bad, b"not a zip").unwrap();
        let err = ZipService::validate(&bad).unwrap_err();
        assert_eq!(err.code, AppErrorCode::InvalidZipFile);
    }

    #[test]
    fn extract_writes_files() {
        let tmp = tempfile::tempdir().unwrap();
        let zip_path = tmp.path().join("a.zip");
        make_zip(
            &zip_path,
            &[
                ("WeakAuras/", b""),
                ("WeakAuras/WeakAuras.toc", b"## Title: WA\n"),
            ],
        );
        let dest = tmp.path().join("out");
        ZipService::extract(&zip_path, &dest).unwrap();
        assert!(dest.join("WeakAuras/WeakAuras.toc").is_file());
    }

    #[test]
    fn safe_join_rejects_parent_escape() {
        let base = Path::new("/tmp/base");
        let err = safe_join(base, Path::new("../evil.txt")).unwrap_err();
        assert_eq!(err.code, AppErrorCode::InvalidZipFile);
    }
}
