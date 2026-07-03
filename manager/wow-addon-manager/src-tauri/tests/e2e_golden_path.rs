//! A9 端到端黄金链路：添加目录 → 扫描 → 安装 zip → 建快照 → 建 Profile → 应用 → 恢复。
//!
//! 全程使用真实的 platform adapter / scanner / installer / ConfigService /
//! ProfileService / repositories，只把文件系统根目录换成临时目录，
//! 逐步断言数据库与磁盘保持一致。覆盖跨平台矩阵中的“中文路径解压”。

use std::collections::HashMap;
use std::fs;
use std::io::Write;
use std::path::Path;

use wow_addon_manager_lib::domain::{
    AddonStatus, Profile, SnapshotScope,
};
use wow_addon_manager_lib::infra::{
    AddonRepository, Database, InstallationRepository, ProfileRepository, SnapshotRepository,
};
use wow_addon_manager_lib::installer::{execute_plan, plan_from_zip};
use wow_addon_manager_lib::platform::adapter::{now_ts, resolve_installations_from_root};
use wow_addon_manager_lib::scanner::scan_addons;
use wow_addon_manager_lib::services::{ConfigService, CreateSnapshotParams, ProfileService};

/// 构造一个含单个插件目录的 zip（可指定目录名以覆盖中文路径）。
fn make_addon_zip(path: &Path, folder: &str, toc_body: &str) {
    let file = fs::File::create(path).unwrap();
    let mut zw = zip::ZipWriter::new(file);
    let opts: zip::write::FileOptions<'_, ()> = zip::write::FileOptions::default();
    zw.start_file(format!("{folder}/{folder}.toc"), opts).unwrap();
    zw.write_all(toc_body.as_bytes()).unwrap();
    zw.finish().unwrap();
}

/// 搭建一个真实结构的 WoW retail 根目录，返回 (root, wtf 内一个可辨识文件)。
fn make_wow_root(root: &Path) {
    let retail = root.join("_retail_");
    fs::create_dir_all(retail.join("Interface").join("AddOns")).unwrap();
    let wtf = retail.join("WTF");
    fs::create_dir_all(wtf.join("Account/PLAYER")).unwrap();
    fs::write(wtf.join("Config.wtf"), "SET original 1\n").unwrap();
}

#[test]
fn golden_path_add_scan_install_snapshot_profile_apply_restore() {
    let tmp = tempfile::tempdir().unwrap();
    let root = tmp.path().join("World of Warcraft");
    make_wow_root(&root);

    let db = Database::open_in_memory().unwrap();
    let work_root = tmp.path().join("work");

    // ---- 1. 添加目录：解析安装并落库 ----
    let installations = resolve_installations_from_root(&root).unwrap();
    assert_eq!(installations.len(), 1, "应识别到一个 retail 安装");
    let installation = installations.into_iter().next().unwrap();
    db.with_connection(|c| InstallationRepository::upsert(c, &installation))
        .unwrap();
    let loaded = db
        .with_connection(|c| InstallationRepository::get(c, &installation.id))
        .unwrap()
        .expect("安装应已落库");
    assert!(loaded.is_valid);

    let addon_path = Path::new(&installation.addon_path);
    let wtf_path = Path::new(&installation.wtf_path);

    // ---- 2. 首次扫描：空 AddOns ----
    let scanned = scan_addons(&installation.id, addon_path).unwrap();
    assert!(scanned.is_empty(), "初始 AddOns 应为空");
    db.with_transaction(|tx| {
        AddonRepository::replace_for_installation(tx, &installation.id, &scanned)
    })
    .unwrap();

    // ---- 3. 安装 zip（含中文目录名，覆盖中文路径解压）----
    let zip_path = tmp.path().join("addons.zip");
    make_addon_zip(&zip_path, "大脚插件", "## Title: 大脚\n## Version: 1.0.0\n");
    let plan = plan_from_zip(&installation.id, addon_path, &zip_path, &work_root).unwrap();
    let outcome = execute_plan(&plan).unwrap();
    assert_eq!(outcome.installed_folders, vec!["大脚插件"]);
    assert!(addon_path.join("大脚插件/大脚插件.toc").is_file(), "中文插件应已解压落地");

    // 安装第二个插件，供后续 Profile 启停对比。
    let zip2 = tmp.path().join("wa.zip");
    make_addon_zip(&zip2, "WeakAuras", "## Title: WeakAuras\n## Version: 5.12.0\n");
    let plan2 = plan_from_zip(&installation.id, addon_path, &zip2, &work_root).unwrap();
    execute_plan(&plan2).unwrap();

    // 安装后重扫写库。
    let after_install = scan_addons(&installation.id, addon_path).unwrap();
    assert_eq!(after_install.len(), 2);
    db.with_transaction(|tx| {
        AddonRepository::replace_for_installation(tx, &installation.id, &after_install)
    })
    .unwrap();

    // ---- 3b. 安装已存在插件触发备份（更新链路）----
    let zip_update = tmp.path().join("wa_update.zip");
    make_addon_zip(&zip_update, "WeakAuras", "## Title: WeakAuras\n## Version: 5.13.0\n");
    let plan_update = plan_from_zip(&installation.id, addon_path, &zip_update, &work_root).unwrap();
    assert!(plan_update.backup_path.is_some(), "更新已存在插件应生成备份路径");
    execute_plan(&plan_update).unwrap();
    let updated = scan_addons(&installation.id, addon_path).unwrap();
    let wa_version = updated
        .iter()
        .find(|a| a.normalized_folder_name == "WeakAuras")
        .and_then(|a| a.version.clone());
    assert_eq!(wa_version.as_deref(), Some("5.13.0"), "更新后版本应刷新");
    db.with_transaction(|tx| {
        AddonRepository::replace_for_installation(tx, &installation.id, &updated)
    })
    .unwrap();

    // ---- 4. 创建 WTF 快照并落库 ----
    let snapshots_root = tmp.path().join("snapshots");
    let mut versions = HashMap::new();
    for a in &updated {
        if let Some(v) = &a.version {
            versions.insert(a.normalized_folder_name.clone(), v.clone());
        }
    }
    let snapshot = ConfigService::create_snapshot(CreateSnapshotParams {
        installation_id: &installation.id,
        name: "黄金链路快照",
        scope: SnapshotScope::FullWtf,
        target: None,
        description: Some("e2e".to_string()),
        wtf_path,
        snapshots_root: &snapshots_root,
        addon_versions: versions,
    })
    .unwrap();
    db.with_connection(|c| SnapshotRepository::insert(c, &snapshot))
        .unwrap();
    assert!(Path::new(&snapshot.file_path).is_file(), "快照 zip 应存在");
    assert_eq!(
        db.with_connection(|c| SnapshotRepository::list_by_installation(c, &installation.id))
            .unwrap()
            .len(),
        1
    );

    // ---- 5. 创建 Profile 并落库（只启用 WeakAuras）----
    let now = now_ts();
    let profile = Profile {
        id: "profile_e2e".into(),
        installation_id: installation.id.clone(),
        name: "仅 WeakAuras".into(),
        description: None,
        addon_folder_names: vec!["WeakAuras".into()],
        snapshot_id: Some(snapshot.id.clone()),
        created_at: now,
        updated_at: now,
    };
    db.with_transaction(|tx| ProfileRepository::upsert(tx, &profile))
        .unwrap();

    // ---- 6. 应用 Profile：启用方案内、禁用方案外 ----
    let toggle = ProfileService::apply_to_addons(addon_path, &profile.addon_folder_names).unwrap();
    assert_eq!(toggle.disabled, vec!["大脚插件"], "方案外插件应被禁用");
    assert!(addon_path.join("WeakAuras").is_dir());
    assert!(addon_path.join("大脚插件.disabled").is_dir());

    // 应用后重扫写库，DB 状态应反映启停。
    let after_apply = scan_addons(&installation.id, addon_path).unwrap();
    db.with_transaction(|tx| {
        AddonRepository::replace_for_installation(tx, &installation.id, &after_apply)
    })
    .unwrap();
    let persisted = db
        .with_connection(|c| AddonRepository::list_by_installation(c, &installation.id))
        .unwrap();
    let status_of = |name: &str| {
        persisted
            .iter()
            .find(|a| a.normalized_folder_name == name)
            .map(|a| a.status.clone())
    };
    assert_eq!(status_of("WeakAuras"), Some(AddonStatus::Installed));
    assert_eq!(status_of("大脚插件"), Some(AddonStatus::Disabled));

    // ---- 7. 恢复快照：WTF 回到快照时的状态 ----
    // 先污染当前 WTF。
    fs::write(wtf_path.join("Config.wtf"), "SET original 999\n").unwrap();
    let backup_root = tmp.path().join("wtf_backups");
    let restore = ConfigService::restore_snapshot(&snapshot, wtf_path, &backup_root).unwrap();
    assert!(restore.success);
    assert_eq!(
        fs::read_to_string(wtf_path.join("Config.wtf")).unwrap(),
        "SET original 1\n",
        "恢复后 WTF 应回到快照内容"
    );

    // ---- 收尾：整链路数据一致 ----
    assert_eq!(
        db.with_connection(|c| ProfileRepository::list_by_installation(c, &installation.id))
            .unwrap()
            .len(),
        1
    );
}
