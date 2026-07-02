use wow_addon_manager_lib::domain::{GameFlavor, PermissionCheckResult, WowInstallation};
use wow_addon_manager_lib::infra::{Database, InstallationRepository};

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
        created_at: 1,
        updated_at: 1,
    }
}

/// 使用真实文件数据库：首次建库写入，重开后数据仍在、迁移不重复报错。
#[test]
fn file_db_persists_across_reopen_and_migration_is_idempotent() {
    let tmp = tempfile::tempdir().unwrap();
    let db_path = tmp.path().join("wam.sqlite");

    {
        let db = Database::open(db_path.clone()).expect("first open creates db");
        db.with_connection(|c| InstallationRepository::upsert(c, &sample("inst1")))
            .unwrap();
    }

    // 重开：迁移应幂等，数据应存在。
    let db2 = Database::open(db_path).expect("reopen ok, migration idempotent");
    let list = db2
        .with_connection(InstallationRepository::list)
        .unwrap();
    assert_eq!(list.len(), 1);
    assert_eq!(list[0].id, "inst1");
    assert_eq!(list[0].flavor, GameFlavor::Retail);
}
