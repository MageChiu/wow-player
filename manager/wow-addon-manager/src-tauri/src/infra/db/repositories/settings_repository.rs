use rusqlite::{Connection, OptionalExtension};

use crate::domain::{AppError, AppResult};
use crate::platform::adapter::now_ts;

/// key-value 设置表访问。
pub struct SettingsRepository;

impl SettingsRepository {
    pub fn set(conn: &Connection, key: &str, value: &str) -> AppResult<()> {
        conn.execute(
            "INSERT INTO settings (key, value, updated_at)
             VALUES (?1, ?2, ?3)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
            rusqlite::params![key, value, now_ts()],
        )
        .map_err(|e| AppError::database(format!("写入设置失败: {e}")))?;
        Ok(())
    }

    pub fn get(conn: &Connection, key: &str) -> AppResult<Option<String>> {
        conn.query_row(
            "SELECT value FROM settings WHERE key = ?1",
            [key],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(|e| AppError::database(format!("读取设置失败: {e}")))
    }

    pub fn delete(conn: &Connection, key: &str) -> AppResult<bool> {
        let affected = conn
            .execute("DELETE FROM settings WHERE key = ?1", [key])
            .map_err(|e| AppError::database(format!("删除设置失败: {e}")))?;
        Ok(affected > 0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::infra::Database;

    #[test]
    fn set_get_update_delete() {
        let db = Database::open_in_memory().unwrap();
        db.with_connection(|c| {
            assert!(SettingsRepository::get(c, "default_provider")?.is_none());

            SettingsRepository::set(c, "default_provider", "github_release")?;
            assert_eq!(
                SettingsRepository::get(c, "default_provider")?.as_deref(),
                Some("github_release")
            );

            SettingsRepository::set(c, "default_provider", "local_zip")?;
            assert_eq!(
                SettingsRepository::get(c, "default_provider")?.as_deref(),
                Some("local_zip")
            );

            assert!(SettingsRepository::delete(c, "default_provider")?);
            assert!(SettingsRepository::get(c, "default_provider")?.is_none());
            Ok(())
        })
        .unwrap();
    }
}
