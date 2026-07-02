use std::fs;
use std::io::Write;
use std::path::Path;

use wow_addon_manager_lib::domain::AppErrorCode;
use wow_addon_manager_lib::installer::{execute_plan, plan_from_zip};
use zip::write::SimpleFileOptions;

fn make_zip(path: &Path, entries: &[(&str, &[u8])]) {
    let file = fs::File::create(path).unwrap();
    let mut zw = zip::ZipWriter::new(file);
    let opts = SimpleFileOptions::default();
    for (name, content) in entries {
        if name.ends_with('/') {
            zw.add_directory(name.trim_end_matches('/'), opts).unwrap();
        } else {
            zw.start_file(*name, opts).unwrap();
            zw.write_all(content).unwrap();
        }
    }
    zw.finish().unwrap();
}

fn setup() -> (tempfile::TempDir, std::path::PathBuf, std::path::PathBuf) {
    let tmp = tempfile::tempdir().unwrap();
    let target = tmp.path().join("AddOns");
    fs::create_dir_all(&target).unwrap();
    let work = tmp.path().join("work");
    (tmp, target, work)
}

#[test]
fn installs_standard_zip() {
    let (tmp, target, work) = setup();
    let zip_path = tmp.path().join("std.zip");
    make_zip(&zip_path, &[("WeakAuras/WeakAuras.toc", b"## Title: WA\n")]);

    let plan = plan_from_zip("inst1", &target, &zip_path, &work).unwrap();
    let outcome = execute_plan(&plan).unwrap();
    assert_eq!(outcome.installed_folders, vec!["WeakAuras"]);
    assert!(target.join("WeakAuras/WeakAuras.toc").is_file());
}

#[test]
fn installs_interface_addons_nested_zip() {
    let (tmp, target, work) = setup();
    let zip_path = tmp.path().join("nested.zip");
    make_zip(
        &zip_path,
        &[
            ("pkg/Interface/AddOns/WeakAuras/WeakAuras.toc", b"## Title: WA\n"),
            ("pkg/Interface/AddOns/Details/Details.toc", b"## Title: D\n"),
        ],
    );

    let plan = plan_from_zip("inst1", &target, &zip_path, &work).unwrap();
    let mut outcome = execute_plan(&plan).unwrap();
    outcome.installed_folders.sort();
    assert_eq!(outcome.installed_folders, vec!["Details", "WeakAuras"]);
    assert!(target.join("WeakAuras/WeakAuras.toc").is_file());
    assert!(target.join("Details/Details.toc").is_file());
}

#[test]
fn installs_multi_addon_zip() {
    let (tmp, target, work) = setup();
    let zip_path = tmp.path().join("multi.zip");
    make_zip(
        &zip_path,
        &[
            ("addon-1.0/WeakAuras/WeakAuras.toc", b"## Title: WA\n"),
            ("addon-1.0/WeakAurasOptions/WeakAurasOptions.toc", b"## Title: O\n"),
        ],
    );

    let plan = plan_from_zip("inst1", &target, &zip_path, &work).unwrap();
    let mut outcome = execute_plan(&plan).unwrap();
    outcome.installed_folders.sort();
    assert_eq!(outcome.installed_folders, vec!["WeakAuras", "WeakAurasOptions"]);
}

#[test]
fn rejects_zip_without_toc() {
    let (tmp, target, work) = setup();
    let zip_path = tmp.path().join("empty.zip");
    make_zip(&zip_path, &[("random/readme.txt", b"nothing here")]);

    let err = plan_from_zip("inst1", &target, &zip_path, &work).unwrap_err();
    assert_eq!(err.code, AppErrorCode::NoAddonFolderDetected);
}

#[test]
fn rejects_invalid_zip() {
    let (tmp, target, work) = setup();
    let bad = tmp.path().join("bad.zip");
    fs::write(&bad, b"not a real zip").unwrap();

    let err = plan_from_zip("inst1", &target, &bad, &work).unwrap_err();
    assert_eq!(err.code, AppErrorCode::InvalidZipFile);
}

#[test]
fn updates_existing_and_keeps_backup() {
    let (tmp, target, work) = setup();
    fs::create_dir_all(target.join("WeakAuras")).unwrap();
    fs::write(target.join("WeakAuras/WeakAuras.toc"), "## Version: 1\n").unwrap();

    let zip_path = tmp.path().join("upd.zip");
    make_zip(&zip_path, &[("WeakAuras/WeakAuras.toc", b"## Version: 2\n")]);

    let plan = plan_from_zip("inst1", &target, &zip_path, &work).unwrap();
    let outcome = execute_plan(&plan).unwrap();

    assert_eq!(
        fs::read_to_string(target.join("WeakAuras/WeakAuras.toc")).unwrap(),
        "## Version: 2\n"
    );
    let backup = std::path::PathBuf::from(outcome.backup_path.unwrap());
    assert_eq!(
        fs::read_to_string(backup.join("WeakAuras/WeakAuras.toc")).unwrap(),
        "## Version: 1\n"
    );
}
