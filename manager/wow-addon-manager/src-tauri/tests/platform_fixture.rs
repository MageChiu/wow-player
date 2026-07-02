use std::path::PathBuf;

use wow_addon_manager_lib::domain::GameFlavor;
use wow_addon_manager_lib::platform::adapter::resolve_installations_from_root;

fn fixture_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("src")
        .join("tests")
        .join("fixtures")
        .join("wow_retail_mock")
}

#[test]
fn detects_retail_and_classic_from_fixture() {
    let root = fixture_root();
    let installations = resolve_installations_from_root(&root)
        .expect("fixture WoW root should resolve installations");

    assert_eq!(installations.len(), 2, "expected retail + classic");

    // Retail 优先排在首位。
    assert_eq!(installations[0].flavor, GameFlavor::Retail);

    let flavors: Vec<&GameFlavor> = installations.iter().map(|i| &i.flavor).collect();
    assert!(flavors.contains(&&GameFlavor::Retail));
    assert!(flavors.contains(&&GameFlavor::Classic));

    for inst in &installations {
        assert!(inst.addon_path.ends_with("Interface/AddOns"));
        assert!(inst.is_valid);
        assert!(inst.permission.readable);
    }
}
