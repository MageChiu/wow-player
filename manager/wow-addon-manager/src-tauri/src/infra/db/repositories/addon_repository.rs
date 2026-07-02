use rusqlite::{Connection, OptionalExtension};

use crate::domain::{AddonProviderKind, AddonStatus, AppError, AppResult, LocalAddon};
use crate::infra::db::codec::{
    enum_from_str, enum_to_str, json_decode, json_encode, opt_enum_from_str, opt_enum_to_str,
};

pub struct AddonRepository;

impl AddonRepository {
    pub fn upsert(conn: &Connection, addon: &LocalAddon) -> AppResult<()> {
        conn.execute(
            "INSERT INTO addons (
                id, installation_id, folder_name, normalized_folder_name,
                title, version, author, interface_version, notes,
                dependencies_json, optional_dependencies_json,
                saved_variables_json, saved_variables_per_character_json,
                provider, remote_id, source_url, status, installed_at, updated_at
             ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19
             )
             ON CONFLICT(installation_id, normalized_folder_name) DO UPDATE SET
                folder_name = excluded.folder_name,
                title = excluded.title,
                version = excluded.version,
                author = excluded.author,
                interface_version = excluded.interface_version,
                notes = excluded.notes,
                dependencies_json = excluded.dependencies_json,
                optional_dependencies_json = excluded.optional_dependencies_json,
                saved_variables_json = excluded.saved_variables_json,
                saved_variables_per_character_json = excluded.saved_variables_per_character_json,
                provider = excluded.provider,
                remote_id = excluded.remote_id,
                source_url = excluded.source_url,
                status = excluded.status,
                updated_at = excluded.updated_at",
            rusqlite::params![
                addon.id,
                addon.installation_id,
                addon.folder_name,
                addon.normalized_folder_name,
                addon.title,
                addon.version,
                addon.author,
                addon.interface_version,
                addon.notes,
                json_encode(&addon.dependencies)?,
                json_encode(&addon.optional_dependencies)?,
                json_encode(&addon.saved_variables)?,
                json_encode(&addon.saved_variables_per_character)?,
                opt_enum_to_str(&addon.provider)?,
                addon.remote_id,
                addon.source_url,
                enum_to_str(&addon.status)?,
                addon.installed_at,
                addon.updated_at,
            ],
        )
        .map_err(|e| AppError::database(format!("写入 addon 失败: {e}")))?;
        Ok(())
    }

    /// 用一次扫描结果替换某安装的全部插件（先删后插，事务内）。
    pub fn replace_for_installation(
        conn: &Connection,
        installation_id: &str,
        addons: &[LocalAddon],
    ) -> AppResult<()> {
        conn.execute(
            "DELETE FROM addons WHERE installation_id = ?1",
            [installation_id],
        )
        .map_err(|e| AppError::database(format!("清理旧 addons 失败: {e}")))?;
        for a in addons {
            Self::upsert(conn, a)?;
        }
        Ok(())
    }

    pub fn list_by_installation(
        conn: &Connection,
        installation_id: &str,
    ) -> AppResult<Vec<LocalAddon>> {
        let mut stmt = conn
            .prepare(
                "SELECT id, installation_id, folder_name, normalized_folder_name,
                        title, version, author, interface_version, notes,
                        dependencies_json, optional_dependencies_json,
                        saved_variables_json, saved_variables_per_character_json,
                        provider, remote_id, source_url, status, installed_at, updated_at
                 FROM addons WHERE installation_id = ?1
                 ORDER BY normalized_folder_name",
            )
            .map_err(|e| AppError::database(format!("准备查询失败: {e}")))?;
        let rows = stmt
            .query_map([installation_id], row_to_addon)
            .map_err(|e| AppError::database(format!("查询 addons 失败: {e}")))?;
        let mut out = Vec::new();
        for r in rows {
            out.push(r.map_err(|e| AppError::database(format!("读取行失败: {e}")))??);
        }
        Ok(out)
    }

    pub fn get(
        conn: &Connection,
        installation_id: &str,
        normalized_folder_name: &str,
    ) -> AppResult<Option<LocalAddon>> {
        conn.query_row(
            "SELECT id, installation_id, folder_name, normalized_folder_name,
                    title, version, author, interface_version, notes,
                    dependencies_json, optional_dependencies_json,
                    saved_variables_json, saved_variables_per_character_json,
                    provider, remote_id, source_url, status, installed_at, updated_at
             FROM addons WHERE installation_id = ?1 AND normalized_folder_name = ?2",
            rusqlite::params![installation_id, normalized_folder_name],
            row_to_addon,
        )
        .optional()
        .map_err(|e| AppError::database(format!("读取 addon 失败: {e}")))?
        .transpose()
    }

    pub fn delete(
        conn: &Connection,
        installation_id: &str,
        normalized_folder_name: &str,
    ) -> AppResult<bool> {
        let affected = conn
            .execute(
                "DELETE FROM addons WHERE installation_id = ?1 AND normalized_folder_name = ?2",
                rusqlite::params![installation_id, normalized_folder_name],
            )
            .map_err(|e| AppError::database(format!("删除 addon 失败: {e}")))?;
        Ok(affected > 0)
    }
}

fn row_to_addon(row: &rusqlite::Row<'_>) -> rusqlite::Result<AppResult<LocalAddon>> {
    let id: String = row.get(0)?;
    let installation_id: String = row.get(1)?;
    let folder_name: String = row.get(2)?;
    let normalized_folder_name: String = row.get(3)?;
    let title: Option<String> = row.get(4)?;
    let version: Option<String> = row.get(5)?;
    let author: Option<String> = row.get(6)?;
    let interface_version: Option<String> = row.get(7)?;
    let notes: Option<String> = row.get(8)?;
    let deps_json: String = row.get(9)?;
    let opt_deps_json: String = row.get(10)?;
    let sv_json: String = row.get(11)?;
    let svpc_json: String = row.get(12)?;
    let provider_str: Option<String> = row.get(13)?;
    let remote_id: Option<String> = row.get(14)?;
    let source_url: Option<String> = row.get(15)?;
    let status_str: String = row.get(16)?;
    let installed_at: i64 = row.get(17)?;
    let updated_at: i64 = row.get(18)?;

    Ok((|| {
        let dependencies: Vec<String> = json_decode(&deps_json)?;
        let optional_dependencies: Vec<String> = json_decode(&opt_deps_json)?;
        let saved_variables: Vec<String> = json_decode(&sv_json)?;
        let saved_variables_per_character: Vec<String> = json_decode(&svpc_json)?;
        let provider: Option<AddonProviderKind> = opt_enum_from_str(provider_str)?;
        let status: AddonStatus = enum_from_str(&status_str)?;
        Ok(LocalAddon {
            id,
            installation_id,
            folder_name,
            normalized_folder_name,
            title,
            version,
            author,
            interface_version,
            notes,
            dependencies,
            optional_dependencies,
            saved_variables,
            saved_variables_per_character,
            provider,
            remote_id,
            source_url,
            status,
            installed_at,
            updated_at,
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

    fn sample(inst: &str, folder: &str) -> LocalAddon {
        LocalAddon {
            id: format!("addon_{inst}_{}", folder.to_lowercase()),
            installation_id: inst.to_string(),
            folder_name: folder.to_string(),
            normalized_folder_name: folder.to_string(),
            title: Some(folder.to_string()),
            version: Some("1.0".into()),
            author: Some("Author".into()),
            interface_version: Some("110002".into()),
            notes: None,
            dependencies: vec!["Dep".into()],
            optional_dependencies: vec![],
            saved_variables: vec![format!("{folder}Saved")],
            saved_variables_per_character: vec![],
            provider: Some(AddonProviderKind::GithubRelease),
            remote_id: Some("owner/repo".into()),
            source_url: None,
            status: AddonStatus::Installed,
            installed_at: 1,
            updated_at: 1,
        }
    }

    #[test]
    fn upsert_and_json_round_trip() {
        let db = Database::open_in_memory().unwrap();
        db.with_connection(|c| {
            seed_installation(c, "inst1");
            AddonRepository::upsert(c, &sample("inst1", "WeakAuras"))?;
            let got = AddonRepository::get(c, "inst1", "WeakAuras")?.unwrap();
            assert_eq!(got.dependencies, vec!["Dep"]);
            assert_eq!(got.saved_variables, vec!["WeakAurasSaved"]);
            assert_eq!(got.provider, Some(AddonProviderKind::GithubRelease));
            assert_eq!(got.status, AddonStatus::Installed);
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn replace_for_installation_swaps_set() {
        let db = Database::open_in_memory().unwrap();
        db.with_connection(|c| {
            seed_installation(c, "inst1");
            AddonRepository::replace_for_installation(
                c,
                "inst1",
                &[sample("inst1", "A"), sample("inst1", "B")],
            )?;
            assert_eq!(AddonRepository::list_by_installation(c, "inst1")?.len(), 2);

            AddonRepository::replace_for_installation(c, "inst1", &[sample("inst1", "C")])?;
            let list = AddonRepository::list_by_installation(c, "inst1")?;
            assert_eq!(list.len(), 1);
            assert_eq!(list[0].normalized_folder_name, "C");
            Ok(())
        })
        .unwrap();
    }

    #[test]
    fn unique_constraint_upsert_updates() {
        let db = Database::open_in_memory().unwrap();
        db.with_connection(|c| {
            seed_installation(c, "inst1");
            AddonRepository::upsert(c, &sample("inst1", "Details"))?;
            let mut updated = sample("inst1", "Details");
            updated.version = Some("2.0".into());
            AddonRepository::upsert(c, &updated)?;
            let list = AddonRepository::list_by_installation(c, "inst1")?;
            assert_eq!(list.len(), 1);
            assert_eq!(list[0].version.as_deref(), Some("2.0"));
            Ok(())
        })
        .unwrap();
    }
}
