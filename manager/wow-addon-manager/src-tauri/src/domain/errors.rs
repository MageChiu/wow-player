use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AppErrorCode {
    InvalidInstallationPath,
    InstallationNotFound,
    AddonPathNotFound,
    WtfPathNotFound,
    PermissionDenied,
    TocParseError,
    InvalidZipFile,
    NoAddonFolderDetected,
    MultipleAddonFoldersDetected,
    InstallPlanNotFound,
    InstallFailed,
    RollbackFailed,
    SnapshotCreateFailed,
    SnapshotRestoreFailed,
    DatabaseError,
    ProviderError,
    NetworkError,
    UnsupportedPlatform,
    Unknown,
}

/// 统一对外错误类型。所有 command 必须返回 `Result<T, AppError>`。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppError {
    pub code: AppErrorCode,
    pub message: String,
    pub detail: Option<String>,
    pub recoverable: bool,
}

impl AppError {
    pub fn new(code: AppErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
            detail: None,
            recoverable: false,
        }
    }

    pub fn with_detail(mut self, detail: impl Into<String>) -> Self {
        self.detail = Some(detail.into());
        self
    }

    pub fn recoverable(mut self, recoverable: bool) -> Self {
        self.recoverable = recoverable;
        self
    }

    pub fn unknown(message: impl Into<String>) -> Self {
        Self::new(AppErrorCode::Unknown, message)
    }

    pub fn database(detail: impl Into<String>) -> Self {
        Self::new(AppErrorCode::DatabaseError, "数据库操作失败").with_detail(detail)
    }
}

impl std::fmt::Display for AppError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "[{:?}] {}", self.code, self.message)
    }
}

impl std::error::Error for AppError {}

pub type AppResult<T> = Result<T, AppError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn error_code_serializes_snake_case() {
        let json = serde_json::to_string(&AppErrorCode::PermissionDenied).unwrap();
        assert_eq!(json, "\"permission_denied\"");
    }

    #[test]
    fn app_error_round_trips() {
        let err = AppError::new(AppErrorCode::InvalidZipFile, "bad zip")
            .with_detail("eof")
            .recoverable(true);
        let json = serde_json::to_string(&err).unwrap();
        let back: AppError = serde_json::from_str(&json).unwrap();
        assert_eq!(back.code, AppErrorCode::InvalidZipFile);
        assert_eq!(back.message, "bad zip");
        assert_eq!(back.detail.as_deref(), Some("eof"));
        assert!(back.recoverable);
    }
}
