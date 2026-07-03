use std::fs;
use std::io::Write;
use std::path::Path;
use std::sync::Arc;

use wow_addon_manager_lib::domain::{AddonProviderKind, GameFlavor, InstallSource};
use wow_addon_manager_lib::installer::{execute_plan, plan_from_zip};
use wow_addon_manager_lib::providers::{
    AddonProvider, GitHubReleaseProvider, HttpClient, LocalZipProvider, ProviderService,
};

/// 构造一个含单个插件目录的 zip。
fn make_addon_zip(path: &Path) {
    let file = fs::File::create(path).unwrap();
    let mut zw = zip::ZipWriter::new(file);
    let opts: zip::write::FileOptions<'_, ()> = zip::write::FileOptions::default();
    zw.start_file("WeakAuras/WeakAuras.toc", opts).unwrap();
    zw.write_all(b"## Title: WeakAuras\n## Version: 5.12.0\n").unwrap();
    zw.finish().unwrap();
}

/// 端到端：LocalZipProvider 下载（复制）→ Installer 生成计划 → 执行 → 校验插件落地。
#[test]
fn provider_download_then_install_pipeline() {
    let tmp = tempfile::tempdir().unwrap();
    let src_zip = tmp.path().join("WeakAuras.zip");
    make_addon_zip(&src_zip);

    let provider = LocalZipProvider::new();
    let files = provider
        .get_files(src_zip.to_str().unwrap(), Some(GameFlavor::Retail))
        .unwrap();
    assert_eq!(files.len(), 1);

    // 下载到临时目录。
    let dl_dir = tmp.path().join("dl");
    let downloaded = provider.download(&files[0], &dl_dir).unwrap();
    assert!(downloaded.is_file());

    // 生成安装计划并执行。
    let addons = tmp.path().join("AddOns");
    fs::create_dir_all(&addons).unwrap();
    let work = tmp.path().join("work");
    let plan = plan_from_zip("inst1", &addons, &downloaded, &work).unwrap();
    let outcome = execute_plan(&plan).unwrap();

    assert_eq!(outcome.installed_folders, vec!["WeakAuras"]);
    assert!(addons.join("WeakAuras/WeakAuras.toc").is_file());
}

/// 用本地 HTTP 桩驱动 GitHubReleaseProvider：搜索 → 取文件 → 下载真实 zip → 安装。
#[test]
fn github_provider_via_stub_http_end_to_end() {
    let tmp = tempfile::tempdir().unwrap();
    // 桩产出的下载文件为一个真实 zip。
    let releases_json = r#"[
      {
        "tag_name": "v5.12.0",
        "published_at": "2024-01-02T03:04:05Z",
        "assets": [
          { "id": 1, "name": "WeakAuras.zip", "browser_download_url": "https://gh/dl/wa.zip" }
        ]
      }
    ]"#;

    struct ZipHttp {
        releases: String,
    }
    impl HttpClient for ZipHttp {
        fn get_text(&self, _url: &str) -> wow_addon_manager_lib::domain::AppResult<String> {
            Ok(self.releases.clone())
        }
        fn download_to(
            &self,
            _url: &str,
            dest: &Path,
        ) -> wow_addon_manager_lib::domain::AppResult<()> {
            fs::create_dir_all(dest.parent().unwrap()).unwrap();
            make_addon_zip(dest);
            Ok(())
        }
    }

    let http = Arc::new(ZipHttp {
        releases: releases_json.to_string(),
    });
    let provider = GitHubReleaseProvider::new(http);

    let files = provider
        .get_files("WeakAuras/WeakAuras2", Some(GameFlavor::Retail))
        .unwrap();
    assert_eq!(files.len(), 1);

    let dl_dir = tmp.path().join("dl");
    let downloaded = provider.download(&files[0], &dl_dir).unwrap();

    let addons = tmp.path().join("AddOns");
    fs::create_dir_all(&addons).unwrap();
    let work = tmp.path().join("work");
    let plan = plan_from_zip("inst1", &addons, &downloaded, &work).unwrap();
    let outcome = execute_plan(&plan).unwrap();
    assert_eq!(outcome.installed_folders, vec!["WeakAuras"]);
    assert!(addons.join("WeakAuras/WeakAuras.toc").is_file());
}

/// ProviderService 分发 + 未注册源返回错误。
#[test]
fn provider_service_dispatch_and_unknown() {
    let svc = ProviderService::with_http(Arc::new(NoopHttp));
    // Local 源搜索返回空（不支持搜索）。
    let out = svc.search(&AddonProviderKind::LocalZip, "x", None).unwrap();
    assert!(out.is_empty());
    // 未注册源报错。
    assert!(svc.search(&AddonProviderKind::Wago, "x", None).is_err());

    // 构造一个 Provider 来源的 InstallSource 可用于 history 归类（编译期校验字段存在）。
    let _ = InstallSource::Provider {
        provider: AddonProviderKind::GithubRelease,
        remote_id: "a/b".into(),
        file_id: None,
    };
}

struct NoopHttp;
impl HttpClient for NoopHttp {
    fn get_text(&self, _url: &str) -> wow_addon_manager_lib::domain::AppResult<String> {
        Ok("[]".to_string())
    }
    fn download_to(
        &self,
        _url: &str,
        _dest: &Path,
    ) -> wow_addon_manager_lib::domain::AppResult<()> {
        Ok(())
    }
}
