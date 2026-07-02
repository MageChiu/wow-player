use rusqlite::Connection;

use crate::domain::{AppError, AppResult};

/// 当前 schema 版本。新增迁移时递增，并在 `MIGRATIONS` 追加对应 SQL。
const SCHEMA_VERSION: i64 = 1;

/// 每个版本对应的建表/变更 SQL（面向终态设计，设计规划 §9）。
/// 索引与迁移编号一一对应：`MIGRATIONS[0]` 将 user_version 从 0 升到 1。
const MIGRATIONS: &[&str] = &[
    // v1：初始终态 schema。
    r#"
    CREATE TABLE IF NOT EXISTS installations (
      id TEXT PRIMARY KEY,
      display_name TEXT NOT NULL,
      root_path TEXT NOT NULL,
      flavor TEXT NOT NULL,
      addon_path TEXT NOT NULL,
      wtf_path TEXT NOT NULL,
      is_valid INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS addons (
      id TEXT PRIMARY KEY,
      installation_id TEXT NOT NULL,
      folder_name TEXT NOT NULL,
      normalized_folder_name TEXT NOT NULL,
      title TEXT,
      version TEXT,
      author TEXT,
      interface_version TEXT,
      notes TEXT,
      dependencies_json TEXT NOT NULL DEFAULT '[]',
      optional_dependencies_json TEXT NOT NULL DEFAULT '[]',
      saved_variables_json TEXT NOT NULL DEFAULT '[]',
      saved_variables_per_character_json TEXT NOT NULL DEFAULT '[]',
      provider TEXT,
      remote_id TEXT,
      source_url TEXT,
      status TEXT NOT NULL,
      installed_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      UNIQUE(installation_id, normalized_folder_name),
      FOREIGN KEY(installation_id) REFERENCES installations(id)
    );

    CREATE TABLE IF NOT EXISTS addon_sources (
      id TEXT PRIMARY KEY,
      addon_id TEXT NOT NULL,
      provider TEXT NOT NULL,
      remote_id TEXT,
      source_url TEXT,
      last_checked_at INTEGER,
      latest_version TEXT,
      metadata_json TEXT NOT NULL DEFAULT '{}',
      FOREIGN KEY(addon_id) REFERENCES addons(id)
    );

    CREATE TABLE IF NOT EXISTS config_snapshots (
      id TEXT PRIMARY KEY,
      installation_id TEXT NOT NULL,
      name TEXT NOT NULL,
      scope TEXT NOT NULL,
      target TEXT,
      file_path TEXT NOT NULL,
      size_bytes INTEGER NOT NULL DEFAULT 0,
      addon_versions_json TEXT NOT NULL DEFAULT '{}',
      description TEXT,
      created_at INTEGER NOT NULL,
      FOREIGN KEY(installation_id) REFERENCES installations(id)
    );

    CREATE TABLE IF NOT EXISTS profiles (
      id TEXT PRIMARY KEY,
      installation_id TEXT NOT NULL,
      name TEXT NOT NULL,
      description TEXT,
      snapshot_id TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY(installation_id) REFERENCES installations(id),
      FOREIGN KEY(snapshot_id) REFERENCES config_snapshots(id)
    );

    CREATE TABLE IF NOT EXISTS profile_addons (
      id TEXT PRIMARY KEY,
      profile_id TEXT NOT NULL,
      folder_name TEXT NOT NULL,
      enabled INTEGER NOT NULL DEFAULT 1,
      UNIQUE(profile_id, folder_name),
      FOREIGN KEY(profile_id) REFERENCES profiles(id)
    );

    CREATE TABLE IF NOT EXISTS install_history (
      id TEXT PRIMARY KEY,
      installation_id TEXT NOT NULL,
      addon_folder_names_json TEXT NOT NULL DEFAULT '[]',
      source_type TEXT NOT NULL,
      source_ref TEXT,
      backup_path TEXT,
      status TEXT NOT NULL,
      error_message TEXT,
      created_at INTEGER NOT NULL,
      FOREIGN KEY(installation_id) REFERENCES installations(id)
    );

    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_addons_installation
      ON addons(installation_id);
    CREATE INDEX IF NOT EXISTS idx_snapshots_installation
      ON config_snapshots(installation_id);
    CREATE INDEX IF NOT EXISTS idx_profiles_installation
      ON profiles(installation_id);
    CREATE INDEX IF NOT EXISTS idx_profile_addons_profile
      ON profile_addons(profile_id);
    CREATE INDEX IF NOT EXISTS idx_install_history_installation
      ON install_history(installation_id);
    "#,
];

/// 幂等地将数据库迁移到最新 schema 版本。
/// 依赖 `PRAGMA user_version` 记录当前版本，重复调用安全。
pub fn run_migrations(conn: &Connection) -> AppResult<()> {
    conn.execute_batch("PRAGMA foreign_keys = ON;")
        .map_err(|e| AppError::database(format!("启用外键失败: {e}")))?;

    let current: i64 = conn
        .query_row("PRAGMA user_version", [], |row| row.get(0))
        .map_err(|e| AppError::database(format!("读取 user_version 失败: {e}")))?;

    if current >= SCHEMA_VERSION {
        return Ok(());
    }

    for (idx, migration) in MIGRATIONS.iter().enumerate() {
        let version = idx as i64 + 1;
        if version <= current {
            continue;
        }
        conn.execute_batch(migration)
            .map_err(|e| AppError::database(format!("执行迁移 v{version} 失败: {e}")))?;
        // user_version 不支持参数绑定，这里 version 由代码控制，安全。
        conn.execute_batch(&format!("PRAGMA user_version = {version};"))
            .map_err(|e| AppError::database(format!("更新 user_version 失败: {e}")))?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn migration_sets_version_and_is_idempotent() {
        let conn = Connection::open_in_memory().unwrap();
        run_migrations(&conn).unwrap();

        let v: i64 = conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .unwrap();
        assert_eq!(v, SCHEMA_VERSION);

        // 再次运行不应报错、不应改变版本。
        run_migrations(&conn).unwrap();
        let v2: i64 = conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .unwrap();
        assert_eq!(v2, SCHEMA_VERSION);
    }

    #[test]
    fn all_tables_exist() {
        let conn = Connection::open_in_memory().unwrap();
        run_migrations(&conn).unwrap();

        let tables = [
            "installations",
            "addons",
            "addon_sources",
            "config_snapshots",
            "profiles",
            "profile_addons",
            "install_history",
            "settings",
        ];
        for t in tables {
            let count: i64 = conn
                .query_row(
                    "SELECT count(*) FROM sqlite_master WHERE type='table' AND name=?1",
                    [t],
                    |r| r.get(0),
                )
                .unwrap();
            assert_eq!(count, 1, "table {t} should exist");
        }
    }
}
