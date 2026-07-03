use std::collections::HashMap;

use rusqlite::{Connection, OptionalExtension};

use crate::domain::{AppError, AppResult, ConfigSnapshot, SnapshotScope};
use crate::infra::db::codec::{enum_from_str, enum_to_str, json_decode, json_encode};

pub struct SnapshotRepository;

impl SnapshotRepository {
    pub fn insert(conn: &Connection, snap: &ConfigSnapshot) -> AppResult<()> {
        conn.execute(
            "INSERT INTO config_snapshots
                (id, installation_id, name, scope, target, file_path, size_bytes, addon_versions_json, description, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
            rusqlite::params![
                snap.id,
                snap.installation_id,
                snap.name,
                enum_to_str(&snap.scope)?,
                snap.target,
                snap.file_path,
                snap.size_bytes,
                json_encode(&snap.addon_versions)?,
                snap.description,
                snap.created_at,
            ],
        )
        .map_err(|e| AppError::database(format!("写入快照失败: {e}")))?;
        Ok(())
    }

    pub fn get(conn: &Connection, id: &str) -> AppResult<Option<ConfigSnapshot>> {
        conn.query_row(
            "SELECT id, installation_id, name, scope, target, file_path, size_bytes, addon_versions_json, description, created_at
             FROM config_snapshots WHERE id = ?1",
            [id],
            row_to_snapshot,
        )
        .optional()
        .map_err(|e| AppError::database(format!("读取快照失败: {e}")))?
        .transpose()
    }

    pub fn list_by_installation(
        conn: &Connection,
        installation_id: &str,
    ) -> AppResult<Vec<ConfigSnapshot>> {
        let mut stmt = conn
            .prepare(
                "SELECT id, installation_id, name, scope, target, file_path, size_bytes, addon_versions_json, description, created_at
                 FROM config_snapshots WHERE installation_id = ?1
                 ORDER BY created_at DESC",
            )
            .map_err(|e| AppError::database(format!("准备查询失败: {e}")))?;
        let rows = stmt
            .query_map([installation_id], row_to_snapshot)
            .map_err(|e| AppError::database(format!("查询快照失败: {e}")))?;
        let mut out = Vec::new();
        for r in rows {
            out.push(r.map_err(|e| AppError::database(format!("读取行失败: {e}")))??);
        }
        Ok(out)
    }

    pub fn delete(conn: &Connection, id: &str) -> AppResult<bool> {
        let affected = conn
            .execute("DELETE FROM config_snapshots WHERE id = ?1", [id])
            .map_err(|e| AppError::database(format!("删除快照失败: {e}")))?;
        Ok(affected > 0)
    }
}

fn row_to_snapshot(row: &rusqlite::Row<'_>) -> rusqlite::Result<AppResult<ConfigSnapshot>> {
    let id: String = row.get(0)?;
    let installation_id: String = row.get(1)?;
    let name: String = row.get(2)?;
    let scope_str: String = row.get(3)?;
    let target: Option<String> = row.get(4)?;
    let file_path: String = row.get(5)?;
    let size_bytes: i64 = row.get(6)?;
    let versions_json: String = row.get(7)?;
    let description: Option<String> = row.get(8)?;
    let created_at: i64 = row.get(9)?;

    Ok((|| {
        let scope: SnapshotScope = enum_from_str(&scope_str)?;
        let addon_versions: HashMap<String, String> = json_decode(&versions_json)?;
        Ok(ConfigSnapshot {
            id,
            installation_id,
            name,
            scope,
            target,
            file_path,
            size_bytes,
            addon_versions,
            description,
            created_at,
        })
    })())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::infra::Database;

    fn seed_installation(conn: &Connection, id: &str) {
        conn.execute(
            "INSERT INTO installations
                (id, display_name, root_path, flavor, addon_path, wtf_path, is_valid, created_at, updated_at)
             VALUES (?1, 'n', '/r', 'retail', '/a', '/w', 1, 0, 0)",
            [id],
        )
        .unwrap();
    }

    fn sample(id: &str) -> ConfigSnapshot {
        let mut versions = HashMap::new();
        versions.insert("WeakAuras".to_string(), "5.12.0".to_string());
        ConfigSnapshot {
            id: id.to_string(),
            installation_id: "inst1".into(),
            name: "before update".into(),
            scope: SnapshotScope::FullWtf,
            target: None,
            file_path: "/snap/wtf.zip".into(),
            size_bytes: 1024,
            addon_versions: versions,
            description: Some("auto".into()),
            created_at: 10,
        }
    }

    #[test]
    fn insert_get_list_delete() {
        let db = Database::open_in_memory().unwrap();
        db.with_connection(|c| {
            seed_installation(c, "inst1");
            SnapshotRepository::insert(c, &sample("s1"))?;
            SnapshotRepository::insert(c, &sample("s2"))?;
            let got = SnapshotRepository::get(c, "s1")?.unwrap();
            assert_eq!(got.scope, SnapshotScope::FullWtf);
            assert_eq!(got.addon_versions.get("WeakAuras").unwrap(), "5.12.0");

            let list = SnapshotRepository::list_by_installation(c, "inst1")?;
            assert_eq!(list.len(), 2);

            assert!(SnapshotRepository::delete(c, "s1")?);
            assert!(SnapshotRepository::get(c, "s1")?.is_none());
            Ok(())
        })
        .unwrap();
    }
}
