use rusqlite::{Connection, OptionalExtension};
use uuid::Uuid;

use crate::domain::{AppError, AppResult, Profile};

pub struct ProfileRepository;

impl ProfileRepository {
    /// 插入或更新 profile 及其关联的插件目录集合（调用方应在事务中执行）。
    pub fn upsert(conn: &Connection, profile: &Profile) -> AppResult<()> {
        conn.execute(
            "INSERT INTO profiles (id, installation_id, name, description, snapshot_id, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
             ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                description = excluded.description,
                snapshot_id = excluded.snapshot_id,
                updated_at = excluded.updated_at",
            rusqlite::params![
                profile.id,
                profile.installation_id,
                profile.name,
                profile.description,
                profile.snapshot_id,
                profile.created_at,
                profile.updated_at,
            ],
        )
        .map_err(|e| AppError::database(format!("写入 profile 失败: {e}")))?;

        // 重建关联插件集合。
        conn.execute(
            "DELETE FROM profile_addons WHERE profile_id = ?1",
            [&profile.id],
        )
        .map_err(|e| AppError::database(format!("清理 profile_addons 失败: {e}")))?;

        for folder in &profile.addon_folder_names {
            conn.execute(
                "INSERT INTO profile_addons (id, profile_id, folder_name, enabled)
                 VALUES (?1, ?2, ?3, 1)",
                rusqlite::params![Uuid::new_v4().to_string(), profile.id, folder],
            )
            .map_err(|e| AppError::database(format!("写入 profile_addons 失败: {e}")))?;
        }
        Ok(())
    }

    pub fn get(conn: &Connection, id: &str) -> AppResult<Option<Profile>> {
        let base = conn
            .query_row(
                "SELECT id, installation_id, name, description, snapshot_id, created_at, updated_at
                 FROM profiles WHERE id = ?1",
                [id],
                row_to_profile_base,
            )
            .optional()
            .map_err(|e| AppError::database(format!("读取 profile 失败: {e}")))?;

        match base {
            Some((mut profile, _)) => {
                profile.addon_folder_names = Self::folder_names(conn, id)?;
                Ok(Some(profile))
            }
            None => Ok(None),
        }
    }

    pub fn list_by_installation(
        conn: &Connection,
        installation_id: &str,
    ) -> AppResult<Vec<Profile>> {
        let mut stmt = conn
            .prepare(
                "SELECT id, installation_id, name, description, snapshot_id, created_at, updated_at
                 FROM profiles WHERE installation_id = ?1 ORDER BY created_at DESC",
            )
            .map_err(|e| AppError::database(format!("准备查询失败: {e}")))?;
        let rows = stmt
            .query_map([installation_id], row_to_profile_base)
            .map_err(|e| AppError::database(format!("查询 profiles 失败: {e}")))?;

        let mut profiles = Vec::new();
        for r in rows {
            let (profile, _) = r.map_err(|e| AppError::database(format!("读取行失败: {e}")))?;
            profiles.push(profile);
        }
        for p in profiles.iter_mut() {
            p.addon_folder_names = Self::folder_names(conn, &p.id)?;
        }
        Ok(profiles)
    }

    pub fn delete(conn: &Connection, id: &str) -> AppResult<bool> {
        conn.execute("DELETE FROM profile_addons WHERE profile_id = ?1", [id])
            .map_err(|e| AppError::database(format!("删除 profile_addons 失败: {e}")))?;
        let affected = conn
            .execute("DELETE FROM profiles WHERE id = ?1", [id])
            .map_err(|e| AppError::database(format!("删除 profile 失败: {e}")))?;
        Ok(affected > 0)
    }

    fn folder_names(conn: &Connection, profile_id: &str) -> AppResult<Vec<String>> {
        let mut stmt = conn
            .prepare(
                "SELECT folder_name FROM profile_addons WHERE profile_id = ?1 ORDER BY folder_name",
            )
            .map_err(|e| AppError::database(format!("准备查询失败: {e}")))?;
        let rows = stmt
            .query_map([profile_id], |row| row.get::<_, String>(0))
            .map_err(|e| AppError::database(format!("查询 profile_addons 失败: {e}")))?;
        let mut out = Vec::new();
        for r in rows {
            out.push(r.map_err(|e| AppError::database(format!("读取行失败: {e}")))?);
        }
        Ok(out)
    }
}

/// 返回 profile（folder_names 待填充）。
fn row_to_profile_base(row: &rusqlite::Row<'_>) -> rusqlite::Result<(Profile, ())> {
    Ok((
        Profile {
            id: row.get(0)?,
            installation_id: row.get(1)?,
            name: row.get(2)?,
            description: row.get(3)?,
            addon_folder_names: Vec::new(),
            snapshot_id: row.get(4)?,
            created_at: row.get(5)?,
            updated_at: row.get(6)?,
        },
        (),
    ))
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

    fn sample(id: &str, folders: &[&str]) -> Profile {
        Profile {
            id: id.to_string(),
            installation_id: "inst1".into(),
            name: "raid".into(),
            description: Some("raid setup".into()),
            addon_folder_names: folders.iter().map(|s| s.to_string()).collect(),
            snapshot_id: None,
            created_at: 5,
            updated_at: 5,
        }
    }

    #[test]
    fn upsert_get_with_folders() {
        let db = Database::open_in_memory().unwrap();
        db.with_connection(|c| {
            seed_installation(c, "inst1");
            ProfileRepository::upsert(c, &sample("p1", &["WeakAuras", "Details"]))?;
            let got = ProfileRepository::get(c, "p1")?.unwrap();
            assert_eq!(got.name, "raid");
            assert_eq!(got.addon_folder_names, vec!["Details", "WeakAuras"]);
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn upsert_replaces_folder_set() {
        let db = Database::open_in_memory().unwrap();
        db.with_connection(|c| {
            seed_installation(c, "inst1");
            ProfileRepository::upsert(c, &sample("p1", &["A", "B"]))?;
            ProfileRepository::upsert(c, &sample("p1", &["C"]))?;
            let got = ProfileRepository::get(c, "p1")?.unwrap();
            assert_eq!(got.addon_folder_names, vec!["C"]);
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn list_and_delete() {
        let db = Database::open_in_memory().unwrap();
        db.with_connection(|c| {
            seed_installation(c, "inst1");
            ProfileRepository::upsert(c, &sample("p1", &["A"]))?;
            ProfileRepository::upsert(c, &sample("p2", &["B"]))?;
            assert_eq!(ProfileRepository::list_by_installation(c, "inst1")?.len(), 2);

            assert!(ProfileRepository::delete(c, "p1")?);
            assert!(ProfileRepository::get(c, "p1")?.is_none());
            assert_eq!(ProfileRepository::list_by_installation(c, "inst1")?.len(), 1);
            Ok(())
        })
        .unwrap();
    }
}
