use std::sync::Arc;

use log::{info, warn};

use crate::app::state::AppState;
use crate::domain::AppResult;
use crate::infra::{logging, Database};
use crate::platform::{self, PlatformAdapter};

/// 应用启动初始化：日志 + 平台适配器 + 数据库连接。
/// 数据库路径由平台适配器的 `app_data_dir()` 决定（开发规范：路径不硬编码）。
pub fn bootstrap() -> AppResult<AppState> {
    logging::init_logging();

    let platform: Arc<dyn PlatformAdapter> = platform::current_adapter();
    info!("platform adapter: {}", platform.platform_name());

    let app_data_dir = match platform.app_data_dir() {
        Ok(dir) => dir,
        Err(e) => {
            warn!("app_data_dir unavailable ({e}), using temp dir");
            std::env::temp_dir().join("wow-addon-manager")
        }
    };

    let db_path = app_data_dir.join("wow-addon-manager.sqlite");
    info!("initializing database at {}", db_path.display());

    let db = match Database::open(db_path) {
        Ok(db) => db,
        Err(e) => {
            warn!("failed to open file database ({e}), falling back to in-memory");
            Database::open_in_memory()?
        }
    };

    Ok(AppState::new(Arc::new(db), platform))
}
