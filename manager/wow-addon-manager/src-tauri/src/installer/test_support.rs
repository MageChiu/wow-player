//! 测试辅助：跨 installer 子模块共享的 zip 构造函数。仅在测试编译。

use std::fs;
use std::io::Write;
use std::path::Path;

use zip::write::SimpleFileOptions;

/// 在指定路径构造 zip。entries: (zip 内路径, 内容)；以 `/` 结尾表示目录。
pub fn make_zip(path: &Path, entries: &[(&str, &[u8])]) {
    let file = fs::File::create(path).unwrap();
    let mut zw = zip::ZipWriter::new(file);
    let opts = SimpleFileOptions::default();
    for (name, content) in entries {
        if name.ends_with('/') {
            zw.add_directory(name.trim_end_matches('/'), opts).unwrap();
        } else {
            zw.start_file(*name, opts).unwrap();
            zw.write_all(content).unwrap();
        }
    }
    zw.finish().unwrap();
}
