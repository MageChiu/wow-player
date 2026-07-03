//! Platform adapter layer (A1)。
//!
//! 平台差异只允许出现在本模块内（开发规范 B6）。业务层通过
//! `PlatformAdapter` trait 使用平台能力，不做任何 `cfg!(windows)` 判断。

pub mod adapter;
pub mod macos;
pub mod windows;

use std::sync::Arc;

pub use adapter::PlatformAdapter;

/// 根据当前编译目标返回平台适配器实现。
/// 这是整个工程中唯一允许出现平台条件编译的位置。
pub fn current_adapter() -> Arc<dyn PlatformAdapter> {
    #[cfg(target_os = "windows")]
    {
        Arc::new(windows::WindowsPlatformAdapter::new())
    }
    #[cfg(not(target_os = "windows"))]
    {
        // macOS 及其它类 unix 平台暂用 mac 适配器（路径策略最接近）。
        Arc::new(macos::MacPlatformAdapter::new())
    }
}
