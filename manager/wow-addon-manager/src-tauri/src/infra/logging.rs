use log::info;

/// 初始化基础日志。A0 阶段用 env_logger，后续可替换为文件日志。
pub fn init_logging() {
    let _ = env_logger::builder()
        .filter_level(log::LevelFilter::Info)
        .is_test(false)
        .try_init();
    info!("logging initialized");
}
