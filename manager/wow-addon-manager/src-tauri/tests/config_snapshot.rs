use std::collections::HashMap;
use std::fs;
use std::path::Path;

use wow_addon_manager_lib::domain::SnapshotScope;
use wow_addon_manager_lib::infra::{Database, SnapshotRepository};
use wow_addon_manager_lib::services::{ConfigService, CreateSnapshotParams};

fn make_wtf(root: &Path) -> std::path::PathBuf {
    let wtf = root.join("WTF");
    fs::create_dir_all(wtf.join("Account/PLAYER")).unwrap();
    fs::write(wtf.join("Config.wtf"), "SET foo 1\n").unwrap();
    wtf
}

fn seed_installation(db: &Database, id: &str) {
    db.with_connection(|c| {
        c.execute(
            "INSERT INTO installations
                (id, display_name, root_path, flavor, addon_path, wtf_path, is_valid, created_at, updated_at)
             VALUES (?1, 'n', '/r', 'retail', '/a', '/w', 1, 0, 0)",
            [id],
        )
        .map_err(|e| wow_addon_manager_lib::domain::AppError::database(e.to_string()))?;
        Ok(())
    })
    .unwrap();
}

/// 端到端：创建快照 → 落库 → 修改 WTF → 恢复 → 删除。
#[test]
fn snapshot_create_persist_restore_delete_cycle() {
    let tmp = tempfile::tempdir().unwrap();
    let wtf = make_wtf(tmp.path());
    let snaps = tmp.path().join("snapshots");
    let backups = tmp.path().join("backups");

    let db = Database::open_in_memory().unwrap();
    seed_installation(&db, "inst1");

    // 创建 + 落库。
    let snap = ConfigService::create_snapshot(CreateSnapshotParams {
        installation_id: "inst1",
        name: "before update",
        scope: SnapshotScope::FullWtf,
        target: None,
        description: None,
        wtf_path: &wtf,
        snapshots_root: &snaps,
        addon_versions: HashMap::new(),
    })
    .unwrap();
    db.with_connection(|c| SnapshotRepository::insert(c, &snap)).unwrap();

    let listed = db
        .with_connection(|c| SnapshotRepository::list_by_installation(c, "inst1"))
        .unwrap();
    assert_eq!(listed.len(), 1);

    // 修改后恢复。
    fs::write(wtf.join("Config.wtf"), "SET foo 999\n").unwrap();
    let result = ConfigService::restore_snapshot(&snap, &wtf, &backups).unwrap();
    assert!(result.success);
    assert_eq!(fs::read_to_string(wtf.join("Config.wtf")).unwrap(), "SET foo 1\n");

    // 删除文件 + DB。
    ConfigService::delete_snapshot_files(&snap).unwrap();
    db.with_connection(|c| SnapshotRepository::delete(c, &snap.id)).unwrap();
    let after = db
        .with_connection(|c| SnapshotRepository::list_by_installation(c, "inst1"))
        .unwrap();
    assert!(after.is_empty());
    assert!(!Path::new(&snap.file_path).exists());
}
