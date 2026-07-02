use rusqlite::{Connection, OptionalExtension};

use crate::domain::{AppError, AppResult, GameFlavor, WowInstallation};
use crate::infra::db::codec::{enum_from_str, enum_to_str};
use crate::platform::adapter::check_permission;

/// installations 表的数据访问。
///
/// 注意：`WowInstallation.permission` 不落库（属运行时状态），读回时依据
/// `addon_path` 用 `check_permission` 重新计算。
pub struct InstallationRepository;

impl InstallationRepository {
    pub fn upsert(conn: &Connection, inst: &WowInstallation) -> AppResult<()> {
        conn.execute(
            "INSERT INTO installations
                (id, display_name, root_path, flavor, addon_path, wtf_path, is_valid, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
             ON CONFLICT(id) DO UPDATE SET
                display_name = excluded.display_name,
                root_path    = excluded.root_path,
                flavor       = excluded.flavor,
                addon_path   = excluded.addon_path,
                wtf_path     = excluded.wtf_path,
                is_valid     = excluded.is_valid,
                updated_at   = excluded.updated_at",
            rusqlite::params![
                inst.id,
                inst.display_name,
                inst.root_path,
                enum_to_str(&inst.flavor)?,
                inst.addon_path,
                inst.wtf_path,
                inst.is_valid as i64,
                inst.created_at,
                inst.updated_at,
            ],
        )
        .map_err(|e| AppError::database(format!("写入 installation 失败: {e}")))?;
        Ok(())
    }

    pub fn get(conn: &Connection, id: &str) -> AppResult<Option<WowInstallation>> {
        conn.query_row(
            "SELECT id, display_name, root_path, flavor, addon_path, wtf_path, is_valid, created_at, updated_at
             FROM installations WHERE id = ?1",
            [id],
            row_to_installation,
        )
        .optional()
        .map_err(|e| AppError::database(format!("读取 installation 失败: {e}")))?
        .transpose()
    }

    pub fn list(conn: &Connection) -> AppResult<Vec<WowInstallation>> {
        let mut stmt = conn
            .prepare(
                "SELECT id, display_name, root_path, flavor, addon_path, wtf_path, is_valid, created_at, updated_at
                 FROM installations ORDER BY id",
            )
            .map_err(|e| AppError::database(format!("准备查询失败: {e}")))?;
        let rows = stmt
            .query_map([], row_to_installation)
            .map_err(|e| AppError::database(format!("查询 installations 失败: {e}")))?;

        let mut out = Vec::new();
        for r in rows {
            out.push(r.map_err(|e| AppError::database(format!("读取行失败: {e}")))??);
        }
        Ok(out)
    }

    pub fn delete(conn: &Connection, id: &str) -> AppResult<bool> {
        let affected = conn
            .execute("DELETE FROM installations WHERE id = ?1", [id])
            .map_err(|e| AppError::database(format!("删除 installation 失败: {e}")))?;
        Ok(affected > 0)
    }
}

/// 将一行映射为 `WowInstallation`（permission 重算）。
/// 外层 `query_row`/`query_map` 需要闭包返回 `rusqlite::Result`，因此这里
/// 返回 `Result<AppResult<_>, rusqlite::Error>` 两层，调用侧用 `??` 展开。
fn row_to_installation(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<AppResult<WowInstallation>> {
    let id: String = row.get(0)?;
    let display_name: String = row.get(1)?;
    let root_path: String = row.get(2)?;
    let flavor_str: String = row.get(3)?;
    let addon_path: String = row.get(4)?;
    let wtf_path: String = row.get(5)?;
    let is_valid: i64 = row.get(6)?;
    let created_at: i64 = row.get(7)?;
    let updated_at: i64 = row.get(8)?;

    Ok((|| {
        let flavor: GameFlavor = enum_from_str(&flavor_str)?;
        let permission = check_permission(std::path::Path::new(&addon_path));
        Ok(WowInstallation {
            id,
            display_name,
            root_path,
            flavor,
            addon_path,
            wtf_path,
            is_valid: is_valid != 0,
            permission,
            created_at,
            updated_at,
        })
    })())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::PermissionCheckResult;
    use crate::infra::Database;

    fn sample(id: &str) -> WowInstallation {
        WowInstallation {
            id: id.to_string(),
            display_name: "WoW (Retail)".into(),
            root_path: "/tmp/wow".into(),
            flavor: GameFlavor::Retail,
            addon_path: "/tmp/wow/_retail_/Interface/AddOns".into(),
            wtf_path: "/tmp/wow/_retail_/WTF".into(),
            is_valid: true,
            permission: PermissionCheckResult {
                readable: true,
                writable: true,
                reason: None,
            },
            created_at: 100,
            updated_at: 100,
        }
    }

    #[test]
    fn insert_get_list_delete() {
        let db = Database::open_in_memory().unwrap();
        db.with_connection(|c| {
            InstallationRepository::upsert(c, &sample("inst1"))?;
            InstallationRepository::upsert(c, &sample("inst2"))?;
            let got = InstallationRepository::get(c, "inst1")?.unwrap();
            assert_eq!(got.id, "inst1");
            assert_eq!(got.flavor, GameFlavor::Retail);

            let all = InstallationRepository::list(c)?;
            assert_eq!(all.len(), 2);

            assert!(InstallationRepository::delete(c, "inst1")?);
            assert!(InstallationRepository::get(c, "inst1")?.is_none());
            assert_eq!(InstallationRepository::list(c)?.len(), 1);
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn upsert_updates_existing() {
        let db = Database::open_in_memory().unwrap();
        db.with_connection(|c| {
            InstallationRepository::upsert(c, &sample("inst1"))?;
            let mut updated = sample("inst1");
            updated.display_name = "Renamed".into();
            updated.updated_at = 200;
            InstallationRepository::upsert(c, &updated)?;

            let got = InstallationRepository::get(c, "inst1")?.unwrap();
            assert_eq!(got.display_name, "Renamed");
            assert_eq!(got.updated_at, 200);
            assert_eq!(InstallationRepository::list(c)?.len(), 1);
            Ok(())
        })
        .unwrap();
    }
}
