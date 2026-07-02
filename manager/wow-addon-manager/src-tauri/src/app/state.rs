use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use crate::domain::{AppResult, InstallPlan, LocalAddon, WowInstallation};
use crate::infra::{AddonRepository, Database, InstallationRepository};
use crate::platform::PlatformAdapter;
use crate::providers::ProviderService;

/// 全局应用状态，注入到 Tauri 的 managed state。
/// installations / addons 已持久化到 SQLite（A3）。
pub struct AppState {
    pub db: Arc<Database>,
    pub platform: Arc<dyn PlatformAdapter>,
    /// 插件源框架（A7）。
    pub providers: Arc<ProviderService>,
    /// 已生成的安装计划（内存态，供 execute/rollback 按 plan_id 查询）。
    plans: Mutex<HashMap<String, InstallPlan>>,
}

impl AppState {
    pub fn new(db: Arc<Database>, platform: Arc<dyn PlatformAdapter>) -> Self {
        Self::with_providers(db, platform, Arc::new(ProviderService::with_defaults()))
    }

    pub fn with_providers(
        db: Arc<Database>,
        platform: Arc<dyn PlatformAdapter>,
        providers: Arc<ProviderService>,
    ) -> Self {
        Self {
            db,
            platform,
            providers,
            plans: Mutex::new(HashMap::new()),
        }
    }

    // ---- installations ----

    pub fn upsert_installation(&self, inst: &WowInstallation) -> AppResult<()> {
        self.db
            .with_connection(|c| InstallationRepository::upsert(c, inst))
    }

    pub fn get_installation(&self, id: &str) -> AppResult<Option<WowInstallation>> {
        self.db.with_connection(|c| InstallationRepository::get(c, id))
    }

    pub fn list_installations(&self) -> AppResult<Vec<WowInstallation>> {
        self.db.with_connection(InstallationRepository::list)
    }

    /// 删除安装。外键约束下需先清理其插件（同一事务）。
    pub fn remove_installation(&self, id: &str) -> AppResult<bool> {
        self.db.with_transaction(|tx| {
            tx.execute("DELETE FROM addons WHERE installation_id = ?1", [id])
                .map_err(|e| crate::domain::AppError::database(format!("清理 addons 失败: {e}")))?;
            InstallationRepository::delete(tx, id)
        })
    }

    // ---- addons ----

    /// 用一次扫描结果替换某安装的全部插件（事务）。
    pub fn set_addons(&self, installation_id: &str, addons: &[LocalAddon]) -> AppResult<()> {
        self.db.with_transaction(|tx| {
            AddonRepository::replace_for_installation(tx, installation_id, addons)
        })
    }

    pub fn get_addons(&self, installation_id: &str) -> AppResult<Vec<LocalAddon>> {
        self.db
            .with_connection(|c| AddonRepository::list_by_installation(c, installation_id))
    }

    // ---- install plans (内存态) ----

    pub fn store_plan(&self, plan: InstallPlan) {
        if let Ok(mut map) = self.plans.lock() {
            map.insert(plan.id.clone(), plan);
        }
    }

    pub fn take_plan(&self, plan_id: &str) -> Option<InstallPlan> {
        self.plans.lock().ok().and_then(|mut m| m.remove(plan_id))
    }
}
