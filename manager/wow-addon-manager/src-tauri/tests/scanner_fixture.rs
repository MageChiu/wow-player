use std::collections::HashMap;
use std::path::PathBuf;

use wow_addon_manager_lib::domain::{AddonStatus, LocalAddon};
use wow_addon_manager_lib::scanner::scan_addons;

fn addons_fixture() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("src")
        .join("tests")
        .join("fixtures")
        .join("toc_samples")
        .join("AddOns")
}

fn by_normalized(addons: &[LocalAddon]) -> HashMap<String, LocalAddon> {
    addons
        .iter()
        .map(|a| (a.normalized_folder_name.clone(), a.clone()))
        .collect()
}

#[test]
fn scans_mock_addons_directory() {
    let addons = scan_addons("inst_fixture", &addons_fixture())
        .expect("mock AddOns should scan without error");

    // WeakAuras / MinimalAddon / 大脚插件 / OldAddon(.disabled) / BrokenAddon
    assert_eq!(addons.len(), 5);
    let map = by_normalized(&addons);

    let wa = map.get("WeakAuras").expect("WeakAuras present");
    assert_eq!(wa.title.as_deref(), Some("WeakAuras"));
    assert_eq!(wa.version.as_deref(), Some("5.12.0"));
    assert_eq!(wa.optional_dependencies, vec!["Details"]);
    assert_eq!(wa.saved_variables, vec!["WeakAurasSaved"]);
    assert_eq!(wa.status, AddonStatus::Installed);

    let minimal = map.get("MinimalAddon").expect("MinimalAddon present");
    assert_eq!(minimal.title.as_deref(), Some("Minimal Addon"));
    assert!(minimal.version.is_none());
    assert_eq!(minimal.status, AddonStatus::Installed);

    let cn = map.get("大脚插件").expect("Chinese addon present");
    assert_eq!(cn.title.as_deref(), Some("大脚插件"));
    assert_eq!(cn.dependencies, vec!["依赖A", "依赖B"]);

    let old = map.get("OldAddon").expect("disabled addon present");
    assert_eq!(old.folder_name, "OldAddon.disabled");
    assert_eq!(old.status, AddonStatus::Disabled);

    let broken = map.get("BrokenAddon").expect("broken addon present");
    assert_eq!(broken.status, AddonStatus::Broken);
    assert!(broken.title.is_none());
}
