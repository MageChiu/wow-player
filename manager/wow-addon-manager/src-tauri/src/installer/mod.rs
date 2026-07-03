//! Install pipeline (A4)。
//!
//! 职责划分：
//! - `zip_service`：zip 校验与解压（zip-slip 防护）。
//! - `addon_folder_detector`：识别解压树中的插件目录。
//! - `install_planner`：生成 `InstallPlan`。
//! - `install_executor`：执行文件系统操作（备份/复制/回滚）。
//! - `fs_ops`：目录复制/移动/删除底层操作。
//!
//! DB 写入与 install_history 记录由命令层负责（Provider 下载不在此处）。

pub mod addon_folder_detector;
pub mod fs_ops;
pub mod install_executor;
pub mod install_planner;
pub mod zip_service;

#[cfg(test)]
pub mod test_support;

pub use addon_folder_detector::detect_addon_folders;
pub use install_executor::{execute_plan, restore_backup, ExecutionOutcome};
pub use install_planner::plan_from_zip;
pub use zip_service::ZipService;
