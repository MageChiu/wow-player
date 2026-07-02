use serde::{Deserialize, Serialize};
use tauri::State;

use crate::app::AppState;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthStatus {
    pub ok: bool,
    pub app_version: String,
    pub platform: String,
    pub db_ready: bool,
    pub message: String,
}

/// 健康检查 command：验证后端就绪、数据库可用。
#[tauri::command]
pub fn health_check(state: State<'_, AppState>) -> HealthStatus {
    let db_ready = state.db.is_ready();
    HealthStatus {
        ok: db_ready,
        app_version: env!("CARGO_PKG_VERSION").to_string(),
        platform: std::env::consts::OS.to_string(),
        db_ready,
        message: if db_ready {
            "后端运行正常".to_string()
        } else {
            "数据库未就绪".to_string()
        },
    }
}
