use std::fs;
use std::path::Path;

use wow_addon_manager_lib::domain::{AddonStatus, Profile};
use wow_addon_manager_lib::infra::{AddonRepository, Database, ProfileRepository};
use wow_addon_manager_lib::scanner::scan_addons;
use wow_addon_manager_lib::services::ProfileService;

fn mk_addon(addons: &Path, folder: &str) {
    let dir = addons.join(folder);
    fs::create_dir_all(&dir).unwrap();
    let normalized = folder.strip_suffix(".disabled").unwrap_or(folder);
    fs::write(dir.join(format!("{normalized}.toc")), "## Title: X\n## Version: 1.0\n").unwrap();
}

fn seed_installation(db: &Database, id: &str, addon_path: &Path) {
    db.with_connection(|c| {
        c.execute(
            "INSERT INTO installations
                (id, display_name, root_path, flavor, addon_path, wtf_path, is_valid, created_at, updated_at)
             VALUES (?1, 'n', '/r', 'retail', ?2, '/w', 1, 0, 0)",
            rusqlite::params![id, addon_path.to_string_lossy()],
        )
        .map_err(|e| wow_addon_manager_lib::domain::AppError::database(e.to_string()))?;
        Ok(())
    })
    .unwrap();
}

/// 端到端：持久化 Profile → 应用（启停目录）→ 重扫写库 → 校验 DB 与磁盘一致。
#[test]
fn apply_profile_toggles_dirs_and_syncs_db() {
    let tmp = tempfile::tempdir().unwrap();
    let addons = tmp.path().join("AddOns");
    fs::create_dir_all(&addons).unwrap();
    mk_addon(&addons, "WeakAuras"); // profile 内，已启用 → 保持
    mk_addon(&addons, "Details"); // profile 外，已启用 → 禁用
    mk_addon(&addons, "BigWigs.disabled"); // profile 内，已禁用 → 启用

    let db = Database::open_in_memory().unwrap();
    seed_installation(&db, "inst1", &addons);

    // 持久化 Profile（含 profile_addons）。
    let profile = Profile {
        id: "profile_raid".into(),
        installation_id: "inst1".into(),
        name: "raid".into(),
        description: None,
        addon_folder_names: vec!["WeakAuras".into(), "BigWigs".into()],
        snapshot_id: None,
        created_at: 0,
        updated_at: 0,
    };
    db.with_transaction(|tx| ProfileRepository::upsert(tx, &profile)).unwrap();

    // 读回 profile 应包含两个目标目录。
    let loaded = db
        .with_connection(|c| ProfileRepository::get(c, "profile_raid"))
        .unwrap()
        .unwrap();
    assert_eq!(loaded.addon_folder_names, vec!["BigWigs", "WeakAuras"]);

    // 应用：启停目录。
    let outcome = ProfileService::apply_to_addons(&addons, &loaded.addon_folder_names).unwrap();
    assert_eq!(outcome.enabled, vec!["BigWigs"]);
    assert_eq!(outcome.disabled, vec!["Details"]);

    // 磁盘状态。
    assert!(addons.join("WeakAuras").is_dir());
    assert!(addons.join("BigWigs").is_dir());
    assert!(addons.join("Details.disabled").is_dir());
    assert!(!addons.join("BigWigs.disabled").exists());

    // 重扫写库，DB 应反映启用/禁用状态。
    let scanned = scan_addons("inst1", &addons).unwrap();
    db.with_transaction(|tx| AddonRepository::replace_for_installation(tx, "inst1", &scanned))
        .unwrap();

    let persisted = db
        .with_connection(|c| AddonRepository::list_by_installation(c, "inst1"))
        .unwrap();
    let status_of = |normalized: &str| {
        persisted
            .iter()
            .find(|a| a.normalized_folder_name == normalized)
            .map(|a| a.status.clone())
    };
    assert_eq!(status_of("WeakAuras"), Some(AddonStatus::Installed));
    assert_eq!(status_of("BigWigs"), Some(AddonStatus::Installed));
    assert_eq!(status_of("Details"), Some(AddonStatus::Disabled));
}

/// 空 Profile 应禁用全部插件。
#[test]
fn apply_empty_profile_disables_all() {
    let tmp = tempfile::tempdir().unwrap();
    let addons = tmp.path().join("AddOns");
    fs::create_dir_all(&addons).unwrap();
    mk_addon(&addons, "WeakAuras");
    mk_addon(&addons, "Details");

    let outcome = ProfileService::apply_to_addons(&addons, &[]).unwrap();
    assert_eq!(outcome.disabled, vec!["Details", "WeakAuras"]);
    assert!(addons.join("WeakAuras.disabled").is_dir());
    assert!(addons.join("Details.disabled").is_dir());
}
