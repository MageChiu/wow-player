pub mod addon;
pub mod errors;
pub mod install;
pub mod profile;
pub mod snapshot;
pub mod toc;

pub use addon::{
    AddonFile, AddonProviderKind, AddonStatus, AddonUpdateInfo, GameFlavor, LocalAddon,
    PermissionCheckResult, RemoteAddon, WowInstallation,
};
pub use errors::{AppError, AppErrorCode, AppResult};
pub use install::{
    DetectedAddonFolder, InstallAction, InstallPlan, InstallResult, InstallSource,
};
pub use profile::{ApplyProfileResult, Profile};
pub use snapshot::{ConfigSnapshot, RestoreResult, SnapshotScope};
pub use toc::TocMetadata;
