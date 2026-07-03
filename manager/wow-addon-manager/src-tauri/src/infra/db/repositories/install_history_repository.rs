use rusqlite::Connection;

use crate::domain::{AppError, AppResult};
use crate::infra::db::codec::json_encode;

/// install_history 一条记录（写入用）。
pub struct InstallHistoryRecord {
    pub id: String,
    pub installation_id: String,
    pub addon_folder_names: Vec<String>,
    pub source_type: String,
    pub source_ref: Option<String>,
    pub backup_path: Option<String>,
    pub status: String,
    pub error_message: Option<String>,
    pub created_at: i64,
}

pub struct InstallHistoryRepository;

impl InstallHistoryRepository {
    pub fn insert(conn: &Connection, rec: &InstallHistoryRecord) -> AppResult<()> {
        conn.execute(
            "INSERT INTO install_history
                (id, installation_id, addon_folder_names_json, source_type, source_ref, backup_path, status, error_message, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            rusqlite::params![
                rec.id,
                rec.installation_id,
                json_encode(&rec.addon_folder_names)?,
                rec.source_type,
                rec.source_ref,
                rec.backup_path,
                rec.status,
                rec.error_message,
                rec.created_at,
            ],
        )
        .map_err(|e| AppError::database(format!("写入 install_history 失败: {e}")))?;
        Ok(())
    }

    pub fn count_for_installation(conn: &Connection, installation_id: &str) -> AppResult<i64> {
        conn.query_row(
            "SELECT count(*) FROM install_history WHERE installation_id = ?1",
            [installation_id],
            |row| row.get(0),
        )
        .map_err(|e| AppError::database(format!("统计 install_history 失败: {e}")))
    }
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

    #[test]
    fn insert_and_count() {
        let db = Database::open_in_memory().unwrap();
        db.with_connection(|c| {
            seed_installation(c, "inst1");
            InstallHistoryRepository::insert(
                c,
                &InstallHistoryRecord {
                    id: "h1".into(),
                    installation_id: "inst1".into(),
                    addon_folder_names: vec!["WeakAuras".into()],
                    source_type: "local_zip".into(),
                    source_ref: Some("/tmp/a.zip".into()),
                    backup_path: None,
                    status: "success".into(),
                    error_message: None,
                    created_at: 1,
                },
            )?;
            assert_eq!(
                InstallHistoryRepository::count_for_installation(c, "inst1")?,
                1
            );
            Ok(())
        })
        .unwrap();
    }
}
